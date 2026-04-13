//! Configuration management for the agent.
//!
//! This module provides hierarchical configuration loading from multiple sources:
//! 1. Default values (embedded in code)
//! 2. Global config file (/etc/agent-rust/config.toml on Unix)
//! 3. User config file (~/.config/agent-rust/config.toml on Unix)
//! 4. Local config file (./config.toml)
//! 5. Environment variables (AGENT_*)
//! 6. Command-line arguments (highest priority)

use crate::error::{ConfigError, Result, AgentError};
use crate::models::ImageFormat;
use serde::{Deserialize, Serialize};
use secrecy::Secret;
use std::path::PathBuf;
use tokio::fs;

/// Main agent configuration.
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(default)]
pub struct AgentConfig {
    /// Server configuration.
    pub server: ServerConfig,

    /// Agent settings.
    pub agent: AgentSettings,

    /// Monitoring intervals.
    pub intervals: IntervalConfig,

    /// Thresholds and limits.
    pub thresholds: ThresholdConfig,

    /// Logging configuration.
    pub logging: LoggingConfig,

    /// Screenshot configuration.
    pub screenshot: ScreenshotConfig,

    /// API token (loaded from env or secure storage).
    #[serde(skip)]
    pub api_token: Option<Secret<String>>,
}

/// Server connection configuration.
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(default)]
pub struct ServerConfig {
    /// Server URL.
    pub url: String,

    /// Request timeout in seconds.
    pub timeout_secs: u64,

    /// Connection timeout in seconds.
    pub connect_timeout_secs: u64,

    /// Maximum retry attempts.
    pub max_retries: u32,
}

impl Default for ServerConfig {
    fn default() -> Self {
        Self {
            url: "http://localhost:8080".to_string(),
            timeout_secs: 30,
            connect_timeout_secs: 10,
            max_retries: 3,
        }
    }
}

/// Agent-specific settings.
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(default)]
pub struct AgentSettings {
    /// Hostname to report (auto-detected if not set).
    pub hostname: Option<String>,

    /// Override auto-detected hostname.
    pub override_hostname: bool,

    /// Data directory for storage.
    pub data_dir: PathBuf,

    /// Cache directory.
    pub cache_dir: PathBuf,

    /// Queue file path.
    pub queue_file: PathBuf,

    /// Log directory (overrides logging.dir if set).
    pub log_dir: Option<PathBuf>,
}

impl Default for AgentSettings {
    fn default() -> Self {
        let data_dir = default_data_dir();
        let cache_dir = default_cache_dir();

        Self {
            hostname: None,
            override_hostname: false,
            data_dir: data_dir.clone(),
            cache_dir: cache_dir.clone(),
            queue_file: data_dir.join("queue.json"),
            log_dir: None,
        }
    }
}

/// Interval configuration for periodic tasks.
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(default)]
pub struct IntervalConfig {
    /// Heartbeat interval in seconds.
    pub heartbeat_secs: u64,

    /// Activity tracking interval in seconds.
    pub activity_secs: u64,

    /// Screenshot interval in seconds.
    pub screenshot_secs: u64,

    /// Update check interval in seconds.
    pub update_check_secs: u64,
}

impl Default for IntervalConfig {
    fn default() -> Self {
        Self {
            heartbeat_secs: 30,
            activity_secs: 60,
            screenshot_secs: 300, // 5 minutes
            update_check_secs: 3600, // 1 hour
        }
    }
}

/// Thresholds and limits configuration.
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(default)]
pub struct ThresholdConfig {
    /// Idle threshold in seconds.
    pub idle_secs: u64,

    /// Maximum queue size in bytes.
    pub queue_max_bytes: usize,

    /// Maximum queue items.
    pub queue_max_items: usize,
}

impl Default for ThresholdConfig {
    fn default() -> Self {
        Self {
            idle_secs: 300, // 5 minutes
            queue_max_bytes: 100 * 1024 * 1024, // 100 MB
            queue_max_items: 10000,
        }
    }
}

/// Logging configuration.
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(default)]
pub struct LoggingConfig {
    /// Log level (trace, debug, info, warn, error).
    pub level: String,

    /// Log format.
    pub format: LogFormat,

    /// Log directory.
    pub dir: PathBuf,

    /// Maximum number of log files to keep.
    pub max_files: usize,

    /// Maximum log file size in MB.
    pub max_file_size_mb: usize,

    /// Whether to log to console.
    pub console: bool,

    /// Whether to log to file.
    pub file: bool,
}

impl Default for LoggingConfig {
    fn default() -> Self {
        Self {
            level: "info".to_string(),
            format: LogFormat::Json,
            dir: default_log_dir(),
            max_files: 10,
            max_file_size_mb: 100,
            console: true,
            file: true,
        }
    }
}

/// Screenshot configuration.
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(default)]
pub struct ScreenshotConfig {
    /// Image format (png, jpeg).
    pub format: ImageFormat,

    /// JPEG quality (1-100, only for JPEG format).
    pub jpeg_quality: u8,

    /// Whether to capture all monitors.
    pub capture_all_monitors: bool,

    /// Whether to compress screenshots before sending.
    pub compress: bool,

    /// Maximum screenshot dimension (width or height).
    pub max_dimension: Option<u32>,
}

impl Default for ScreenshotConfig {
    fn default() -> Self {
        Self {
            format: ImageFormat::Png,
            jpeg_quality: 85,
            capture_all_monitors: false,
            compress: true,
            max_dimension: None,
        }
    }
}

/// Log format options.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum LogFormat {
    /// JSON format for structured logging.
    Json,

    /// Pretty human-readable format.
    Pretty,

    /// Compact single-line format.
    Compact,
}

impl Default for LogFormat {
    fn default() -> Self {
        Self::Json
    }
}

impl Default for AgentConfig {
    fn default() -> Self {
        Self {
            server: ServerConfig::default(),
            agent: AgentSettings::default(),
            intervals: IntervalConfig::default(),
            thresholds: ThresholdConfig::default(),
            logging: LoggingConfig::default(),
            screenshot: ScreenshotConfig::default(),
            api_token: None,
        }
    }
}

/// Configuration loader.
pub struct ConfigLoader {
    /// Paths to search for configuration files.
    paths: Vec<PathBuf>,
}

impl ConfigLoader {
    /// Create a new config loader with default paths.
    pub fn new() -> Self {
        let mut paths = Vec::new();

        // Add platform-specific global config path
        let global_config = default_global_config_dir();
        if global_config.exists() || global_config.parent().map_or(false, |p| p.exists()) {
            paths.push(global_config);
        }

        // Add user config path
        let user_config = default_user_config_dir();
        if user_config.exists() || user_config.parent().map_or(false, |p| p.exists()) {
            paths.push(user_config);
        }

        // Add local config paths
        paths.push(PathBuf::from("config.toml"));
        paths.push(PathBuf::from("agent.toml"));

        Self { paths }
    }

    /// Create a config loader with custom paths.
    pub fn with_paths(paths: Vec<PathBuf>) -> Self {
        Self { paths }
    }

    /// Load configuration from files and environment variables.
    pub async fn load(&self) -> Result<AgentConfig> {
        let mut config = AgentConfig::default();

        // Try loading from each path
        for path in &self.paths {
            if path.exists() {
                let content = fs::read_to_string(path).await
                    .map_err(|e| AgentError::Config(format!("Failed to read config file {:?}: {}", path, e)))?;

                let file_config: AgentConfig = toml::from_str(&content)
                    .map_err(|e| AgentError::Config(format!("Failed to parse config file {:?}: {}", path, e)))?;

                config = Self::merge_configs(config, file_config);
                tracing::debug!("Loaded configuration from {:?}", path);
                break;
            }
        }

        // Apply environment variable overrides
        Self::apply_env_overrides(&mut config)?;

        // Validate configuration
        config.validate()?;

        // Ensure directories exist
        Self::ensure_directories(&config).await?;

        Ok(config)
    }

    /// Merge two configurations, with `override_config` taking precedence.
    fn merge_configs(base: AgentConfig, override_config: AgentConfig) -> AgentConfig {
        AgentConfig {
            server: if override_config.server.url != ServerConfig::default().url {
                override_config.server
            } else {
                base.server
            },
            agent: override_config.agent,
            intervals: override_config.intervals,
            thresholds: override_config.thresholds,
            logging: override_config.logging,
            screenshot: override_config.screenshot,
            api_token: override_config.api_token.or(base.api_token),
        }
    }

    /// Apply environment variable overrides.
    fn apply_env_overrides(config: &mut AgentConfig) -> Result<()> {
        // Server URL
        if let Ok(url) = std::env::var("AGENT_SERVER_URL") {
            config.server.url = url;
        }

        // API token
        if let Ok(token) = std::env::var("AGENT_API_TOKEN") {
            config.api_token = Some(Secret::new(token));
        }

        // Hostname
        if let Ok(hostname) = std::env::var("AGENT_HOSTNAME") {
            config.agent.hostname = Some(hostname);
            config.agent.override_hostname = true;
        }

        // Intervals
        if let Ok(val) = std::env::var("AGENT_HEARTBEAT_SECS") {
            config.intervals.heartbeat_secs = val.parse()
                .map_err(|_| ConfigError::InvalidValue("AGENT_HEARTBEAT_SECS must be a number".to_string()))?;
        }

        if let Ok(val) = std::env::var("AGENT_ACTIVITY_SECS") {
            config.intervals.activity_secs = val.parse()
                .map_err(|_| ConfigError::InvalidValue("AGENT_ACTIVITY_SECS must be a number".to_string()))?;
        }

        if let Ok(val) = std::env::var("AGENT_SCREENSHOT_SECS") {
            config.intervals.screenshot_secs = val.parse()
                .map_err(|_| ConfigError::InvalidValue("AGENT_SCREENSHOT_SECS must be a number".to_string()))?;
        }

        if let Ok(val) = std::env::var("AGENT_IDLE_SECS") {
            config.thresholds.idle_secs = val.parse()
                .map_err(|_| ConfigError::InvalidValue("AGENT_IDLE_SECS must be a number".to_string()))?;
        }

        // Log level
        if let Ok(level) = std::env::var("AGENT_LOG_LEVEL") {
            config.logging.level = level;
        }

        // Data directory
        if let Ok(dir) = std::env::var("AGENT_DATA_DIR") {
            config.agent.data_dir = PathBuf::from(dir);
        }

        // Log directory
        if let Ok(dir) = std::env::var("AGENT_LOG_DIR") {
            config.agent.log_dir = Some(PathBuf::from(dir));
        }

        Ok(())
    }

    /// Ensure all required directories exist.
    async fn ensure_directories(config: &AgentConfig) -> Result<()> {
        fs::create_dir_all(&config.agent.data_dir).await
            .map_err(|e| AgentError::Config(format!("Failed to create data directory: {}", e)))?;

        fs::create_dir_all(&config.agent.cache_dir).await
            .map_err(|e| AgentError::Config(format!("Failed to create cache directory: {}", e)))?;

        let log_dir = config.agent.log_dir.as_ref().unwrap_or(&config.logging.dir);
        fs::create_dir_all(log_dir).await
            .map_err(|e| AgentError::Config(format!("Failed to create log directory: {}", e)))?;

        Ok(())
    }
}

impl AgentConfig {
    /// Validate the configuration.
    pub fn validate(&self) -> Result<()> {
        // Validate server URL
        let url = url::Url::parse(&self.server.url)
            .map_err(|e| ConfigError::InvalidUrl(format!("Invalid server URL: {}", e)))?;

        if url.scheme() != "http" && url.scheme() != "https" {
            return Err(ConfigError::InvalidUrl(
                "Server URL must use http or https scheme".to_string()
            ).into());
        }

        // Validate intervals are reasonable
        if self.intervals.heartbeat_secs < 10 {
            return Err(ConfigError::InvalidInterval(
                "Heartbeat interval must be at least 10 seconds".to_string()
            ).into());
        }

        if self.intervals.activity_secs < 5 {
            return Err(ConfigError::InvalidInterval(
                "Activity interval must be at least 5 seconds".to_string()
            ).into());
        }

        if self.intervals.screenshot_secs < 30 {
            return Err(ConfigError::InvalidInterval(
                "Screenshot interval must be at least 30 seconds".to_string()
            ).into());
        }

        // Validate JPEG quality
        if self.screenshot.format == ImageFormat::Jpeg
            && (self.screenshot.jpeg_quality < 1 || self.screenshot.jpeg_quality > 100)
        {
            return Err(ConfigError::InvalidValue(
                "JPEG quality must be between 1 and 100".to_string()
            ).into());
        }

        Ok(())
    }
}

// Default directory helpers

fn default_data_dir() -> PathBuf {
    if cfg!(target_os = "windows") {
        dirs::data_local_dir()
            .unwrap_or_else(|| PathBuf::from("."))
            .join("agent-rust")
    } else {
        dirs::data_dir()
            .unwrap_or_else(|| PathBuf::from("."))
            .join("agent-rust")
    }
}

fn default_cache_dir() -> PathBuf {
    dirs::cache_dir()
        .unwrap_or_else(|| PathBuf::from(".cache"))
        .join("agent-rust")
}

fn default_log_dir() -> PathBuf {
    // Use user-writable location by default
    if cfg!(target_os = "windows") {
        dirs::data_local_dir()
            .unwrap_or_else(|| PathBuf::from("."))
            .join("agent-rust/logs")
    } else {
        dirs::data_dir()
            .unwrap_or_else(|| PathBuf::from("."))
            .join("agent-rust/logs")
    }
}

fn default_global_config_dir() -> PathBuf {
    if cfg!(target_os = "windows") {
        dirs::config_dir()
            .unwrap_or_else(|| PathBuf::from("."))
            .join("agent-rust/config.toml")
    } else if cfg!(target_os = "macos") {
        PathBuf::from("/Library/Preferences/agent-rust/config.toml")
    } else {
        PathBuf::from("/etc/agent-rust/config.toml")
    }
}

fn default_user_config_dir() -> PathBuf {
    dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("agent-rust/config.toml")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = AgentConfig::default();
        assert!(config.validate().is_ok());
    }

    #[test]
    fn test_config_merge() {
        let base = AgentConfig {
            server: ServerConfig {
                url: "http://base.example.com".to_string(),
                ..Default::default()
            },
            ..Default::default()
        };

        let override_config = AgentConfig {
            server: ServerConfig {
                url: "http://override.example.com".to_string(),
                ..Default::default()
            },
            ..Default::default()
        };

        let merged = ConfigLoader::merge_configs(base, override_config);
        assert_eq!(merged.server.url, "http://override.example.com");
    }

    #[test]
    fn test_invalid_url() {
        let mut config = AgentConfig::default();
        config.server.url = "not-a-valid-url".to_string();
        assert!(config.validate().is_err());
    }

    #[test]
    fn test_min_interval_validation() {
        let mut config = AgentConfig::default();
        config.intervals.screenshot_secs = 10; // Too low
        assert!(config.validate().is_err());
    }
}
