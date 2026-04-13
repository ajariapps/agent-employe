//! Error types for the employee monitoring agent.
//!
//! This module provides centralized error types with context preservation
//! and detailed error information for debugging and reporting.

use thiserror::Error;

/// Result type alias for the agent.
pub type Result<T> = std::result::Result<T, AgentError>;

/// Main error type for the agent.
#[derive(Error, Debug)]
pub enum AgentError {
    /// Configuration-related errors.
    #[error("Configuration error: {0}")]
    Config(String),

    /// Platform-specific errors.
    #[error("Platform error: {0}")]
    Platform(#[from] PlatformError),

    /// API communication errors.
    #[error("API communication failed: {0}")]
    Api(#[from] ApiError),

    /// Screenshot capture errors.
    #[error("Screenshot capture failed: {0}")]
    Screenshot(String),

    /// Activity detection errors.
    #[error("Activity detection failed: {0}")]
    Activity(String),

    /// Service management errors.
    #[error("Service error: {0}")]
    Service(String),

    /// Update errors.
    #[error("Update failed: {0}")]
    Update(String),

    /// IO errors.
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    /// Serialization errors.
    #[error("Serialization error: {0}")]
    Serialization(#[from] serde_json::Error),

    /// TOML parsing errors.
    #[error("TOML parsing error: {0}")]
    TomlParse(#[from] toml::de::Error),

    /// URL parsing errors.
    #[error("URL parsing error: {0}")]
    UrlParse(#[from] url::ParseError),
}

/// Platform-specific errors.
#[derive(Error, Debug)]
pub enum PlatformError {
    /// No display available (Linux X11/Wayland).
    #[error("No display available")]
    NoDisplay,

    /// X11-specific errors.
    #[cfg(target_os = "linux")]
    #[error("X11 error: {0}")]
    X11(String),

    /// Wayland-specific errors.
    #[cfg(target_os = "linux")]
    #[error("Wayland error: {0}")]
    Wayland(String),

    /// Core Graphics errors (macOS).
    #[cfg(target_os = "macos")]
    #[error("Core Graphics error: {0}")]
    CoreGraphics(String),

    /// Cocoa/AppKit errors (macOS).
    #[cfg(target_os = "macos")]
    #[error("AppKit error: {0}")]
    AppKit(String),

    /// Win32 API errors (Windows).
    #[cfg(target_os = "windows")]
    #[error("Win32 error: {0} (code: {1})")]
    Win32(String, u32),

    /// Operation not supported on this platform.
    #[error("Unsupported operation on this platform: {0}")]
    Unsupported(&'static str),

    /// Generic platform error.
    #[error("Platform error: {0}")]
    Other(String),
}

/// API client errors.
#[derive(Error, Debug)]
pub enum ApiError {
    /// Server returned an error.
    #[error("Server returned error: {0} - {1}")]
    Server(u16, String),

    /// Authentication failed.
    #[error("Authentication failed")]
    Authentication,

    /// Rate limited.
    #[error("Rate limited, retry after {0}s")]
    RateLimited(u64),

    /// Connection timeout.
    #[error("Connection timeout after {0}s")]
    Timeout(u64),

    /// Queue operation failed.
    #[error("Queue operation failed: {0}")]
    Queue(String),

    /// Generic error message.
    #[error("{0}")]
    Other(String),
}

impl From<String> for ApiError {
    fn from(msg: String) -> Self {
        Self::Other(msg)
    }
}

impl AgentError {
    /// Create a configuration error.
    pub fn config(msg: impl Into<String>) -> Self {
        Self::Config(msg.into())
    }

    /// Create a screenshot error.
    pub fn screenshot(msg: impl Into<String>) -> Self {
        Self::Screenshot(msg.into())
    }

    /// Create an activity error.
    pub fn activity(msg: impl Into<String>) -> Self {
        Self::Activity(msg.into())
    }

    /// Create a service error.
    pub fn service(msg: impl Into<String>) -> Self {
        Self::Service(msg.into())
    }

    /// Create an update error.
    pub fn update(msg: impl Into<String>) -> Self {
        Self::Update(msg.into())
    }
}

impl PlatformError {
    /// Create an X11 error.
    #[cfg(target_os = "linux")]
    pub fn x11(msg: impl Into<String>) -> Self {
        Self::X11(msg.into())
    }

    /// Create a Wayland error.
    #[cfg(target_os = "linux")]
    pub fn wayland(msg: impl Into<String>) -> Self {
        Self::Wayland(msg.into())
    }

    /// Create a Core Graphics error.
    #[cfg(target_os = "macos")]
    pub fn core_graphics(msg: impl Into<String>) -> Self {
        Self::CoreGraphics(msg.into())
    }

    /// Create an AppKit error.
    #[cfg(target_os = "macos")]
    pub fn app_kit(msg: impl Into<String>) -> Self {
        Self::AppKit(msg.into())
    }

    /// Create a Win32 error.
    #[cfg(target_os = "windows")]
    pub fn win32(msg: impl Into<String>, code: u32) -> Self {
        Self::Win32(msg.into(), code)
    }

    /// Create an unsupported error.
    pub fn unsupported(operation: &'static str) -> Self {
        Self::Unsupported(operation)
    }

    /// Create a generic platform error.
    pub fn other(msg: impl Into<String>) -> Self {
        Self::Other(msg.into())
    }
}

/// Configuration validation error.
#[derive(Error, Debug)]
pub enum ConfigError {
    #[error("Invalid URL: {0}")]
    InvalidUrl(String),

    #[error("Invalid interval: {0}")]
    InvalidInterval(String),

    #[error("Missing required field: {0}")]
    MissingField(String),

    #[error("Invalid value: {0}")]
    InvalidValue(String),
}

impl From<ConfigError> for AgentError {
    fn from(err: ConfigError) -> Self {
        AgentError::Config(err.to_string())
    }
}
