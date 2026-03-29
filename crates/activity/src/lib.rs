//! # Activity Tracking Module
//!
//! This module provides activity tracking functionality, including window tracking
//! and URL detection for browsers.

use agent_core::{Activity, Result, WindowInfo};
use platform::PlatformWrapper;
use std::sync::Arc;
use tokio::sync::Mutex;

/// Activity tracker configuration.
#[derive(Debug, Clone)]
pub struct TrackerConfig {
    /// Whether to track browser URLs.
    pub track_urls: bool,

    /// List of browser process names to detect.
    pub browser_processes: Vec<String>,
}

impl Default for TrackerConfig {
    fn default() -> Self {
        Self {
            track_urls: true,
            browser_processes: vec![
                "firefox".to_string(),
                "chrome".to_string(),
                "chromium".to_string(),
                "edge".to_string(),
                "brave".to_string(),
                "opera".to_string(),
                "safari".to_string(),
            ],
        }
    }
}

/// Activity tracker.
pub struct ActivityTracker {
    platform: Arc<PlatformWrapper>,
    config: TrackerConfig,
    last_activity: Arc<Mutex<Option<Activity>>>,
}

impl ActivityTracker {
    /// Create a new activity tracker.
    pub async fn new(config: TrackerConfig) -> Result<Self> {
        let platform = Arc::new(PlatformWrapper::new()?);

        Ok(Self {
            platform,
            config,
            last_activity: Arc::new(Mutex::new(None)),
        })
    }

    /// Create with default configuration.
    pub async fn default() -> Result<Self> {
        Self::new(TrackerConfig::default()).await
    }

    /// Get the current activity.
    pub async fn get_current_activity(&self) -> Result<Activity> {
        let window_info = self.platform.get_active_window().await?;

        // Check if this is a browser window
        let url = if self.config.track_urls && self.is_browser(&window_info.app_name) {
            self.extract_browser_url(&window_info).await
        } else {
            None
        };

        let activity = Activity::new(
            window_info.title.clone(),
            window_info.app_name.clone(),
            window_info.app_path.clone(),
            url,
        );

        Ok(activity)
    }

    /// Check if activity has changed since last check.
    pub async fn has_activity_changed(&self) -> Result<bool> {
        let current = self.get_current_activity().await?;
        let last = self.last_activity.lock().await;

        Ok(last.as_ref().map_or(true, |l| {
            l.window_title != current.window_title || l.app_name != current.app_name
        }))
    }

    /// Update the last known activity.
    pub async fn update_last_activity(&self, activity: Activity) {
        *self.last_activity.lock().await = Some(activity);
    }

    /// Get the last tracked activity.
    pub async fn get_last_activity(&self) -> Option<Activity> {
        self.last_activity.lock().await.clone()
    }

    /// Check if the given app name is a browser.
    fn is_browser(&self, app_name: &str) -> bool {
        let app_name_lower = app_name.to_lowercase();
        self.config
            .browser_processes
            .iter()
            .any(|b| app_name_lower.contains(&b.to_lowercase()))
    }

    /// Extract URL from browser window (simplified).
    async fn extract_browser_url(&self, _window_info: &WindowInfo) -> Option<String> {
        // This is a simplified implementation
        // In a real implementation, you would:
        // - Use browser-specific APIs (e.g., chrome.debugger API)
        // - Read browser databases/cookies
        // - Use accessibility APIs to get URL from address bar
        // For now, return None
        None
    }

    /// Detect if the window title contains a URL.
    pub fn detect_url_in_title(&self, title: &str) -> Option<String> {
        // Simple heuristic to detect URLs in window titles
        // Many browsers put the URL in the title
        let url_patterns = vec![
            "https://",
            "http://",
            "www.",
            ".com",
            ".org",
            ".net",
            ".io",
            ".co",
        ];

        for pattern in &url_patterns {
            if title.contains(pattern) {
                // Try to extract the URL
                if let Some(pos) = title.find(pattern) {
                    let url_part = &title[pos..];
                    // Split on common separators
                    let url = url_part
                        .split(|c| c == ' ' || c == '-' || c == '|' || c == '—')
                        .next()?
                        .trim();
                    if !url.is_empty() {
                        return Some(url.to_string());
                    }
                }
            }
        }

        None
    }

    /// Get application name from window title (heuristic).
    pub fn extract_app_name_from_title(&self, title: &str) -> String {
        // Try to extract app name from title
        // Common patterns: "AppName - Title", "Title — AppName", etc.
        let separators = vec![" - ", " — ", " | ", " • ", ": "];

        for sep in &separators {
            if let Some(pos) = title.find(sep) {
                let potential_app = &title[..pos];
                if !potential_app.is_empty() && potential_app.len() < 50 {
                    return potential_app.to_string();
                }
            }
        }

        // If no separator found, use first word
        title
            .split_whitespace()
            .next()
            .unwrap_or("Unknown")
            .to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_browser_detection() {
        let config = TrackerConfig::default();
        let tracker = ActivityTracker {
            platform: unsafe { std::sync::Arc::from_raw(std::ptr::null()) }, // Dummy for test
            config,
            last_activity: Arc::new(Mutex::new(None)),
        };

        assert!(tracker.is_browser("Google Chrome"));
        assert!(tracker.is_browser("Mozilla Firefox"));
        assert!(tracker.is_browser("Brave Browser"));
        assert!(!tracker.is_browser("Terminal"));
    }

    #[test]
    fn test_url_detection() {
        let config = TrackerConfig::default();
        let tracker = ActivityTracker {
            platform: unsafe { std::sync::Arc::from_raw(std::ptr::null()) }, // Dummy for test
            config,
            last_activity: Arc::new(Mutex::new(None)),
        };

        let title = "Example.com - Hello World";
        let url = tracker.detect_url_in_title(title);
        assert!(url.is_some());

        let title = "No URL Here";
        let url = tracker.detect_url_in_title(title);
        assert!(url.is_none());
    }

    #[test]
    fn test_app_name_extraction() {
        let config = TrackerConfig::default();
        let tracker = ActivityTracker {
            platform: unsafe { std::sync::Arc::from_raw(std::ptr::null()) }, // Dummy for test
            config,
            last_activity: Arc::new(Mutex::new(None)),
        };

        let title = "Terminal - bash";
        let app = tracker.extract_app_name_from_title(title);
        assert_eq!(app, "Terminal");

        let title = "Document - Text Editor";
        let app = tracker.extract_app_name_from_title(title);
        assert_eq!(app, "Document");
    }
}
