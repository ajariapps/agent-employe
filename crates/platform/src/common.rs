//! Common utilities and types shared across platform implementations.

use sysinfo::System;

/// System information shared across platforms.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct SystemInfo {
    /// OS type (linux, macos, windows).
    pub os_type: String,

    /// OS version.
    pub os_version: String,

    /// Architecture (x86_64, aarch64, etc.).
    pub arch: String,

    /// Hostname.
    pub hostname: String,

    /// Total memory in bytes.
    pub total_memory: u64,

    /// Number of CPU cores.
    pub cpu_count: usize,
}

impl SystemInfo {
    /// Get current system information.
    pub fn current() -> Self {
        let os_type = std::env::consts::OS.to_string();
        let arch = std::env::consts::ARCH.to_string();

        let os_version = Self::get_os_version();

        let mut sys = System::new();
        let hostname = System::host_name().unwrap_or_else(|| "Unknown".to_string());
        sys.refresh_memory();
        let total_memory = sys.total_memory();

        Self {
            os_type,
            os_version,
            arch,
            hostname,
            total_memory,
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
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_system_info() {
        let info = SystemInfo::current();
        assert!(!info.os_type.is_empty());
        assert!(!info.arch.is_empty());
        assert!(!info.hostname.is_empty());
        assert!(info.cpu_count > 0);
    }
}
