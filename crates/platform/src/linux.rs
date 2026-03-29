//! Linux platform implementation using X11.

use crate::common::SystemInfo;
use agent_core::{models::WindowInfo, PlatformError, Result};
use std::ptr;
use std::os::raw::c_long;
use std::ffi::CStr;
use std::fs;

/// Platform handle for Linux.
pub struct LinuxPlatform {
    system_info: SystemInfo,
    display: Option<*mut x11::xlib::Display>,
    screen: i32,
}

unsafe impl Send for LinuxPlatform {}
unsafe impl Sync for LinuxPlatform {}

impl LinuxPlatform {
    /// Create a new Linux platform instance.
    pub fn new() -> Result<Self> {
        unsafe {
            let display = x11::xlib::XOpenDisplay(ptr::null());
            if display.is_null() {
                return Err(agent_core::AgentError::Platform(
                    PlatformError::NoDisplay,
                ));
            }

            let screen = x11::xlib::XDefaultScreen(display);

            Ok(Self {
                system_info: SystemInfo::current(),
                display: Some(display),
                screen,
            })
        }
    }

    /// Get the active window using X11.
    pub fn get_active_window_sync(&self) -> Result<WindowInfo> {
        unsafe {
            let display = self.display.unwrap();

            // Get the window with focus
            let mut focused: x11::xlib::Window = 0;
            let mut revert_to: i32 = 0;

            x11::xlib::XGetInputFocus(
                display,
                &mut focused as *mut x11::xlib::Window,
                &mut revert_to as *mut i32,
            );

            if focused == 0 {
                return Ok(WindowInfo {
                    title: "Unknown".to_string(),
                    app_name: "Unknown".to_string(),
                    app_path: None,
                    window_id: None,
                    pid: None,
                });
            }

            // Get window title (try multiple methods)
            let title = self.get_window_title(focused);

            // Get window class (application name)
            let app_name = self.get_window_class(focused);

            // Get process ID
            let pid = self.get_window_pid(focused);

            // Try to get app path from PID
            let app_path = pid.and_then(|p| self.get_process_path(p));

            Ok(WindowInfo {
                title: title.unwrap_or_else(|| "Unknown".to_string()),
                app_name,
                app_path,
                window_id: Some(focused as u64),
                pid,
            })
        }
    }

    fn get_window_title(&self, window: x11::xlib::Window) -> Option<String> {
        unsafe {
            let display = self.display.unwrap();

            // Try _NET_WM_NAME first (UTF-8)
            let net_wm_name = x11::xlib::XInternAtom(
                display,
                b"_NET_WM_NAME\0".as_ptr() as *const i8,
                x11::xlib::False,
            );

            if let Some(title) = self.get_window_property_utf8(window, net_wm_name) {
                if !title.is_empty() {
                    return Some(title);
                }
            }

            // Fallback to WM_NAME (legacy)
            let title = self.get_window_property_text(window, x11::xlib::XA_WM_NAME);
            if title.is_some() {
                title
            } else {
                Some("Unknown".to_string())
            }
        }
    }

    fn get_window_property_utf8(&self, window: x11::xlib::Window, atom: x11::xlib::Atom) -> Option<String> {
        unsafe {
            let display = self.display.unwrap();

            // Get UTF8_STRING atom
            let utf8_string = x11::xlib::XInternAtom(
                display,
                b"UTF8_STRING\0".as_ptr() as *const i8,
                x11::xlib::False,
            );

            let mut actual_type: x11::xlib::Atom = 0;
            let mut format: i32 = 0;
            let mut nitems: u64 = 0;
            let mut bytes_after: u64 = 0;
            let mut prop: *mut u8 = ptr::null_mut();

            let result = x11::xlib::XGetWindowProperty(
                display,
                window,
                atom,
                0,
                c_long::MAX / 4,
                x11::xlib::False,
                utf8_string,
                &mut actual_type as *mut x11::xlib::Atom,
                &mut format as *mut i32,
                &mut nitems as *mut u64,
                &mut bytes_after as *mut u64,
                &mut prop as *mut *mut u8,
            );

            if result != 0 || prop.is_null() || nitems == 0 || actual_type != utf8_string {
                if !prop.is_null() {
                    x11::xlib::XFree(prop as *mut _);
                }
                return None;
            }

            let bytes = std::slice::from_raw_parts(prop, nitems as usize);
            let string = String::from_utf8(bytes.to_vec()).ok();

            x11::xlib::XFree(prop as *mut _);

            string
        }
    }

    fn get_window_property_text(&self, window: x11::xlib::Window, atom: x11::xlib::Atom) -> Option<String> {
        unsafe {
            let display = self.display.unwrap();

            let mut atom_type: x11::xlib::Atom = 0;
            let mut format: i32 = 0;
            let mut nitems: u64 = 0;
            let mut bytes_after: u64 = 0;
            let mut prop: *mut u8 = ptr::null_mut();

            let result = x11::xlib::XGetWindowProperty(
                display,
                window,
                atom,
                0,
                c_long::MAX / 4,
                x11::xlib::False,
                0, // AnyPropertyType
                &mut atom_type as *mut x11::xlib::Atom,
                &mut format as *mut i32,
                &mut nitems as *mut u64,
                &mut bytes_after as *mut u64,
                &mut prop as *mut *mut u8,
            );

            if result != 0 || prop.is_null() || nitems == 0 {
                if !prop.is_null() {
                    x11::xlib::XFree(prop as *mut _);
                }
                return None;
            }

            let text = if format == 8 {
                // Null-terminated string
                let c_str = CStr::from_ptr(prop as *const i8);
                c_str.to_string_lossy().into_owned()
            } else {
                String::new()
            };

            x11::xlib::XFree(prop as *mut _);

            Some(text)
        }
    }

    fn get_window_class(&self, window: x11::xlib::Window) -> String {
        unsafe {
            let display = self.display.unwrap();
            let mut class_hint: x11::xlib::XClassHint = std::mem::zeroed();

            let status = x11::xlib::XGetClassHint(display, window, &mut class_hint);

            if status == 0 {
                return "Unknown".to_string();
            }

            // Try res_class first (more descriptive), fall back to res_name
            let app_name = if !class_hint.res_class.is_null() {
                let name = CStr::from_ptr(class_hint.res_class)
                    .to_string_lossy()
                    .into_owned();

                if !name.is_empty() {
                    name
                } else if !class_hint.res_name.is_null() {
                    CStr::from_ptr(class_hint.res_name)
                        .to_string_lossy()
                        .into_owned()
                } else {
                    "Unknown".to_string()
                }
            } else if !class_hint.res_name.is_null() {
                CStr::from_ptr(class_hint.res_name)
                    .to_string_lossy()
                    .into_owned()
            } else {
                "Unknown".to_string()
            };

            // Free the class hint
            if !class_hint.res_name.is_null() {
                x11::xlib::XFree(class_hint.res_name as *mut _);
            }
            if !class_hint.res_class.is_null() {
                x11::xlib::XFree(class_hint.res_class as *mut _);
            }

            // Capitalize first letter for consistency
            if app_name != "Unknown" {
                let mut chars = app_name.chars();
                match chars.next() {
                    None => String::new(),
                    Some(first) => first.to_uppercase().collect::<String>() + chars.as_str(),
                }
            } else {
                app_name
            }
        }
    }

    fn get_window_pid(&self, window: x11::xlib::Window) -> Option<u32> {
        unsafe {
            let display = self.display.unwrap();

            // Get _NET_WM_PID atom
            let net_wm_pid = x11::xlib::XInternAtom(
                display,
                b"_NET_WM_PID\0".as_ptr() as *const i8,
                x11::xlib::False,
            );

            let mut atom_type: x11::xlib::Atom = 0;
            let mut format: i32 = 0;
            let mut nitems: u64 = 0;
            let mut bytes_after: u64 = 0;
            let mut prop: *mut u8 = ptr::null_mut();

            let result = x11::xlib::XGetWindowProperty(
                display,
                window,
                net_wm_pid,
                0,
                1,
                x11::xlib::False,
                x11::xlib::XA_CARDINAL,
                &mut atom_type as *mut x11::xlib::Atom,
                &mut format as *mut i32,
                &mut nitems as *mut u64,
                &mut bytes_after as *mut u64,
                &mut prop as *mut *mut u8,
            );

            if result == 0 && !prop.is_null() && nitems == 1 {
                let pid_ptr = prop as *const u32;
                let pid = *pid_ptr;

                x11::xlib::XFree(prop as *mut _);

                if pid > 0 {
                    return Some(pid);
                }
            }

            None
        }
    }

    fn get_process_path(&self, pid: u32) -> Option<String> {
        // Try to read from /proc/[pid]/exe
        let exe_path = format!("/proc/{}/exe", pid);

        if let Ok(link_target) = fs::read_link(&exe_path) {
            return Some(link_target.to_string_lossy().to_string());
        }

        // Fallback: try to read from /proc/[pid]/cmdline
        let cmdline_path = format!("/proc/{}/cmdline", pid);
        if let Ok(cmdline) = fs::read_to_string(&cmdline_path) {
            // The first null-separated string is the executable path
            if let Some(first_arg) = cmdline.split('\0').next() {
                if !first_arg.is_empty() {
                    return Some(first_arg.to_string());
                }
            }
        }

        None
    }

    /// Check if the user is idle using XScreenSaver.
    pub fn check_idle_sync(&self) -> Result<bool> {
        unsafe {
            let display = self.display.unwrap();

            // Get MIT-SCREEN-SAVER extension info
            // For simplicity, just return false for now
            // A full implementation would use XScreenSaverQueryInfo
            Ok(false)
        }
    }
}

impl Drop for LinuxPlatform {
    fn drop(&mut self) {
        if let Some(display) = self.display {
            unsafe {
                x11::xlib::XCloseDisplay(display);
            }
        }
    }
}

#[async_trait::async_trait]
impl super::Platform for LinuxPlatform {
    fn new() -> Result<Self>
    where
        Self: Sized,
    {
        Self::new()
    }

    async fn get_active_window(&self) -> Result<WindowInfo> {
        self.get_active_window_sync()
    }

    async fn is_idle(&self) -> Result<bool> {
        self.check_idle_sync()
    }

    fn get_system_info(&self) -> SystemInfo {
        self.system_info.clone()
    }
}

#[async_trait::async_trait]
impl super::Platform for PlatformWrapper {
    fn new() -> Result<Self>
    where
        Self: Sized,
    {
        Ok(Self {
            inner: LinuxPlatform::new()?,
        })
    }

    async fn get_active_window(&self) -> Result<WindowInfo> {
        self.inner.get_active_window().await
    }

    async fn is_idle(&self) -> Result<bool> {
        self.inner.is_idle().await
    }

    fn get_system_info(&self) -> SystemInfo {
        self.inner.get_system_info()
    }
}

pub use crate::PlatformWrapper;
