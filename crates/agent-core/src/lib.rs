//! # Employee Monitoring Agent - Core Library
//!
//! This crate provides the core functionality for the employee monitoring agent,
//! including configuration management, data models, and error types.
//!
//! ## Example
//!
//! ```no_run
//! use agent_core::config::ConfigLoader;
//!
//! #[tokio::main]
//! async fn main() -> Result<(), Box<dyn std::error::Error>> {
//!     let loader = ConfigLoader::new();
//!     let config = loader.load().await?;
//!     println!("Loaded config for server: {}", config.server.url);
//!     Ok(())
//! }
//! ```

pub mod config;
pub mod error;
pub mod models;

// Re-export commonly used types
pub use error::{AgentError, PlatformError, ApiError, Result};
pub use models::{
    Activity,
    Screenshot,
    SystemInfo,
    WindowInfo,
    DisplayInfo,
    AgentStatus,
    ServiceStatus,
    ImageFormat,
    RegisterRequest,
    RegisterResponse,
    HeartbeatRequest,
    HeartbeatResponse,
    ActivityRequest,
    ScreenshotRequest,
    QueuedRequest,
};
pub use config::{
    AgentConfig,
    ServerConfig,
    AgentSettings,
    IntervalConfig,
    ThresholdConfig,
    LoggingConfig,
    ScreenshotConfig,
    LogFormat,
    ConfigLoader,
};

/// Agent version.
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

/// Agent name.
pub const AGENT_NAME: &str = "Employee Monitoring Agent";
