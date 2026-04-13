//! # Idle Detection Module
//!
//! This module provides cross-platform idle detection functionality.

use chrono::{DateTime, Utc};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;
use tracing::debug;

/// Idle detector configuration.
#[derive(Debug, Clone)]
pub struct IdleConfig {
    /// Idle threshold in seconds.
    pub threshold_secs: u64,

    /// Check interval in seconds.
    pub check_interval_secs: u64,
}

impl Default for IdleConfig {
    fn default() -> Self {
        Self {
            threshold_secs: 300, // 5 minutes
            check_interval_secs: 1,
        }
    }
}

/// Idle state information.
#[derive(Debug, Clone)]
pub struct IdleState {
    /// Whether the user is currently idle.
    pub is_idle: bool,

    /// How long the user has been idle (if idle).
    pub idle_duration_secs: Option<u64>,

    /// Last activity timestamp.
    pub last_activity: DateTime<Utc>,
}

/// Idle detector.
pub struct IdleDetector {
    config: IdleConfig,
    last_activity_time: Arc<Mutex<DateTime<Utc>>>,
    mouse_position: Arc<Mutex<(i32, i32)>>,
}

impl IdleDetector {
    /// Create a new idle detector.
    pub fn new(config: IdleConfig) -> Self {
        Self {
            config,
            last_activity_time: Arc::new(Mutex::new(Utc::now())),
            mouse_position: Arc::new(Mutex::new((-1, -1))),
        }
    }

    /// Create with default configuration.
    pub fn default() -> Self {
        Self::new(IdleConfig::default())
    }

    /// Start monitoring idle state.
    pub fn start(&self) -> tokio::task::JoinHandle<()> {
        let _mouse_pos = self.mouse_position.clone();
        let check_interval = Duration::from_secs(self.config.check_interval_secs);

        tokio::spawn(async move {
            let mut interval = tokio::time::interval(check_interval);

            loop {
                interval.tick().await;

                // Check for activity (simplified - just check time)
                // In a real implementation, you would check mouse/keyboard
                // For now, just update to show we're checking
                // Real implementation would detect actual user input
                debug!("Idle detector check");
            }
        })
    }

    /// Check if the user is currently idle.
    pub async fn is_idle(&self) -> bool {
        let last = *self.last_activity_time.lock().await;
        let elapsed = Utc::now().signed_duration_since(last);

        elapsed.num_seconds() as u64 > self.config.threshold_secs
    }

    /// Get the current idle state.
    pub async fn get_state(&self) -> IdleState {
        let last_activity = *self.last_activity_time.lock().await;
        let elapsed = Utc::now().signed_duration_since(last_activity);
        let idle_duration = elapsed.num_seconds() as u64;
        let is_idle = idle_duration > self.config.threshold_secs;

        IdleState {
            is_idle,
            idle_duration_secs: if is_idle { Some(idle_duration) } else { None },
            last_activity,
        }
    }

    /// Manually update activity (call when you detect user activity).
    pub async fn update_activity(&self) {
        *self.last_activity_time.lock().await = Utc::now();
    }

    /// Get the idle threshold in seconds.
    pub fn threshold(&self) -> Duration {
        Duration::from_secs(self.config.threshold_secs)
    }

    /// Set a new idle threshold.
    pub fn set_threshold(&mut self, threshold_secs: u64) {
        self.config.threshold_secs = threshold_secs;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_detector_creation() {
        let detector = IdleDetector::default();
        let state = detector.get_state().await;

        // Should not be idle immediately
        assert!(!state.is_idle);
    }

    #[tokio::test]
    async fn test_activity_update() {
        let detector = IdleDetector::default();

        // Update activity
        detector.update_activity().await;

        let state = detector.get_state().await;
        // Should not be idle after update
        assert!(!state.is_idle);
    }
}
