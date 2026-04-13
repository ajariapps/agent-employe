//! Data models for the employee monitoring agent.
//!
//! This module defines all data structures used throughout the agent,
//! including API requests/responses, configuration models, and internal state.

use base64::prelude::*;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sysinfo::System;

/// Registration request sent to the server.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RegisterRequest {
    /// Hostname of the agent machine.
    pub hostname: String,

    /// Operating system type (linux, macos, windows).
    pub os_type: String,

    /// OS version.
    pub os_version: String,

    /// IP address (optional).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ip_address: Option<String>,

    /// MAC address (optional).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mac_address: Option<String>,
}

/// Registration response from the server.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RegisterResponse {
    /// Assigned employee ID (also used as agent_id).
    pub employee_id: String,

    /// API authentication token.
    pub api_token: String,

    /// Response message.
    pub message: String,
}

/// Heartbeat request sent to keep connection alive.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HeartbeatRequest {
    /// Hostname.
    pub hostname: String,
}

/// Heartbeat response from the server.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HeartbeatResponse {
    /// Response status.
    pub status: String,

    /// Response message.
    pub message: String,

    /// New API token (optional).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub api_token: Option<String>,
}

/// Activity log request.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActivityRequest {
    /// Hostname.
    pub hostname: String,

    /// Activity timestamp.
    pub timestamp: String,

    /// Window title.
    pub window_title: String,

    /// Application name.
    pub app_name: String,

    /// URL if browser window.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,

    /// Activity type.
    #[serde(default = "default_activity_type")]
    pub activity_type: String,

    /// Notes.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,

    /// Duration in seconds.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub duration_seconds: Option<i32>,
}

/// Screenshot upload request.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScreenshotRequest {
    /// Hostname.
    pub hostname: String,

    /// Screenshot timestamp.
    pub timestamp: String,

    /// Base64-encoded screenshot data.
    pub image_data: String,

    /// Width in pixels.
    pub width: i32,

    /// Height in pixels.
    pub height: i32,

    /// Associated window title.
    pub window_title: String,

    /// Associated application name.
    pub app_name: String,
}

fn default_activity_type() -> String {
    "window_change".to_string()
}

/// Activity information tracked by the agent.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Activity {
    /// Window title.
    pub window_title: String,

    /// Application name.
    pub app_name: String,

    /// Application executable path.
    pub app_path: Option<String>,

    /// URL if browser window detected.
    pub url: Option<String>,

    /// When this activity was captured.
    pub timestamp: DateTime<Utc>,
}

impl Activity {
    /// Create a new activity record.
    pub fn new(
        window_title: String,
        app_name: String,
        app_path: Option<String>,
        url: Option<String>,
    ) -> Self {
        Self {
            window_title,
            app_name,
            app_path,
            url,
            timestamp: Utc::now(),
        }
    }

    /// Check if this activity is from a browser.
    pub fn is_browser(&self) -> bool {
        self.url.is_some()
    }
}

/// Screenshot data captured by the agent.
#[derive(Debug, Clone)]
pub struct Screenshot {
    /// Image data.
    pub data: Vec<u8>,

    /// Image width.
    pub width: u32,

    /// Image height.
    pub height: u32,

    /// Image format.
    pub format: ImageFormat,

    /// Capture timestamp.
    pub timestamp: DateTime<Utc>,

    /// Associated window title.
    pub window_title: String,

    /// Associated application name.
    pub app_name: String,
}

/// Supported image formats.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ImageFormat {
    /// PNG format.
    Png,

    /// JPEG format.
    Jpeg,
}

impl ImageFormat {
    /// Get the MIME type for this format.
    pub fn mime_type(&self) -> &'static str {
        match self {
            Self::Png => "image/png",
            Self::Jpeg => "image/jpeg",
        }
    }

    /// Get the file extension for this format.
    pub fn extension(&self) -> &'static str {
        match self {
            Self::Png => "png",
            Self::Jpeg => "jpg",
        }
    }
}

impl Screenshot {
    /// Create a new screenshot.
    pub fn new(
        data: Vec<u8>,
        width: u32,
        height: u32,
        format: ImageFormat,
        window_title: String,
        app_name: String,
    ) -> Self {
        Self {
            data,
            width,
            height,
            format,
            timestamp: Utc::now(),
            window_title,
            app_name,
        }
    }

    /// Convert to base64 encoding for API transmission.
    pub fn to_base64(&self) -> String {
        BASE64_STANDARD.encode(&self.data)
    }

    /// Calculate approximate size in bytes.
    pub fn size_bytes(&self) -> usize {
        self.data.len()
    }
}

/// System information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SystemInfo {
    /// OS type.
    pub os_type: String,

    /// OS version.
    pub os_version: String,

    /// Architecture.
    pub arch: String,

    /// Hostname.
    pub hostname: String,

    /// Total memory in bytes.
    pub total_memory: u64,

    /// CPU count.
    pub cpu_count: usize,
}

impl SystemInfo {
    /// Get current system information.
    pub fn current() -> Self {
        let os_type = std::env::consts::OS.to_string();
        let arch = std::env::consts::ARCH.to_string();

        let os_version = Self::get_os_version();

        let hostname = Self::get_hostname();

        let mut sys = System::new();
        sys.refresh_memory();
        let total_memory = sys.total_memory();

        Self {
            os_type,
            os_version,
            arch,
            hostname,
            total_memory: total_memory,
            cpu_count: num_cpus::get(),
        }
    }

    #[cfg(target_os = "linux")]
    fn get_os_version() -> String {
        std::fs::read_to_string("/proc/version")
            .ok()
            .and_then(|v| {
                v.split_whitespace()
                    .nth(2)
                    .map(|s| s.to_string())
            })
            .unwrap_or_else(|| "Unknown".to_string())
    }

    #[cfg(target_os = "macos")]
    fn get_os_version() -> String {
        std::process::Command::new("sw_vers")
            .arg("-productVersion")
            .output()
            .ok()
            .and_then(|o| String::from_utf8(o.stdout).ok())
            .map(|s| s.trim().to_string())
            .unwrap_or_else(|| "Unknown".to_string())
    }

    #[cfg(target_os = "windows")]
    fn get_os_version() -> String {
        std::process::Command::new("cmd")
            .args(["/c", "ver"])
            .output()
            .ok()
            .and_then(|o| String::from_utf8(o.stdout).ok())
            .and_then(|s| s.lines().next().map(|l| l.to_string()))
            .unwrap_or_else(|| "Unknown".to_string())
    }

    #[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
    fn get_os_version() -> String {
        "Unknown".to_string()
    }

    fn get_hostname() -> String {
        sysinfo::System::host_name().unwrap_or_else(|| "Unknown".to_string())
    }
}

/// Display information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DisplayInfo {
    /// Display ID.
    pub id: u32,

    /// X position.
    pub x: i32,

    /// Y position.
    pub y: i32,

    /// Width in pixels.
    pub width: u32,

    /// Height in pixels.
    pub height: u32,

    /// Scale factor (DPI).
    pub scale_factor: f32,

    /// Is this the primary display.
    pub primary: bool,
}

/// Window information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WindowInfo {
    /// Window title.
    pub title: String,

    /// Application name.
    pub app_name: String,

    /// Application path.
    pub app_path: Option<String>,

    /// Window ID (platform-specific).
    pub window_id: Option<u64>,

    /// Process ID.
    pub pid: Option<u32>,
}

/// Agent status for health checks.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentStatus {
    /// Agent ID.
    pub agent_id: String,

    /// Uptime in seconds.
    pub uptime_secs: u64,

    /// Current status.
    pub status: ServiceStatus,

    /// Last heartbeat time.
    pub last_heartbeat: Option<DateTime<Utc>>,

    /// Current idle state.
    pub is_idle: bool,

    /// Idle duration in seconds.
    pub idle_duration_secs: Option<u64>,

    /// Activities logged since start.
    pub activities_logged: u64,

    /// Screenshots captured since start.
    pub screenshots_captured: u64,
}

/// Service status.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ServiceStatus {
    /// Service is starting.
    Starting,

    /// Service is running.
    Running,

    /// Service is stopping.
    Stopping,

    /// Service is stopped.
    Stopped,

    /// Service encountered an error.
    Error,
}

/// Queue item for offline/pending requests.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QueuedRequest {
    /// Request endpoint.
    pub endpoint: String,

    /// Request body.
    pub body: serde_json::Value,

    /// When this request was queued.
    pub timestamp: DateTime<Utc>,

    /// Number of retry attempts.
    pub attempts: u32,

    /// Maximum retry attempts allowed.
    pub max_attempts: u32,
}
