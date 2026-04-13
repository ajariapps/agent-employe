//! macOS platform implementation.

use crate::common::SystemInfo;
use agent_core::{models::WindowInfo, Result};
use async_trait::async_trait;

/// Platform handle for macOS.
pub struct MacosPlatform {
    system_info: SystemInfo,
}

impl MacosPlatform {
    /// Create a new macOS platform instance.
    pub fn new() -> Result<Self> {
        Ok(Self {
            system_info: SystemInfo::current(),
        })
    }
}

#[async_trait::async_trait]
impl super::Platform for MacosPlatform {
    fn new() -> Result<Self>
    where
        Self: Sized,
    {
        Self::new()
    }

    async fn get_active_window(&self) -> Result<WindowInfo> {
        // Simplified implementation for now
        Ok(WindowInfo {
            title: "Unknown".to_string(),
            app_name: "Unknown".to_string(),
            app_path: None,
            window_id: None,
            pid: None,
        })
    }

    async fn is_idle(&self) -> Result<bool> {
        Ok(false)
    }

    fn get_system_info(&self) -> SystemInfo {
        self.system_info.clone()
    }
}

pub type PlatformWrapper = MacosPlatform;
