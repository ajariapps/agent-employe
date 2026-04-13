//! # Platform Abstraction Layer
//!
//! This crate provides a unified interface for platform-specific operations
//! across Linux, macOS, and Windows.

use agent_core::{models::WindowInfo, Result};
use async_trait::async_trait;

// Common utilities
mod common;

pub use common::SystemInfo;

/// Main platform abstraction trait.
#[async_trait]
pub trait Platform: Send + Sync {
    /// Create a new platform instance.
    fn new() -> Result<Self>
    where
        Self: Sized;

    /// Get the currently active window.
    async fn get_active_window(&self) -> Result<WindowInfo>;

    /// Check if the user is currently idle.
    async fn is_idle(&self) -> Result<bool>;

    /// Get system information.
    fn get_system_info(&self) -> SystemInfo;
}

// Platform-specific implementations
#[cfg(target_os = "linux")]
mod linux;
#[cfg(target_os = "linux")]
pub use linux::LinuxPlatform as PlatformImpl;

#[cfg(target_os = "macos")]
mod macos;
#[cfg(target_os = "macos")]
pub use macos::MacosPlatform as PlatformImpl;

#[cfg(target_os = "windows")]
mod windows;
#[cfg(target_os = "windows")]
pub use windows::WindowsPlatform as PlatformImpl;

/// Platform handle that uses the appropriate implementation for the current OS.
pub struct PlatformWrapper {
    inner: PlatformImpl,
}

impl PlatformWrapper {
    /// Create a new platform wrapper.
    pub fn new() -> Result<Self> {
        Ok(Self {
            inner: PlatformImpl::new()?,
        })
    }

    /// Get system info.
    pub fn get_system_info(&self) -> SystemInfo {
        self.inner.get_system_info()
    }

    /// Get active window.
    pub async fn get_active_window(&self) -> Result<WindowInfo> {
        self.inner.get_active_window().await
    }

    /// Check if idle.
    pub async fn is_idle(&self) -> Result<bool> {
        self.inner.is_idle().await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_platform_init() {
        let platform = PlatformWrapper::new();
        assert!(platform.is_ok());
    }
}
