//! # Screenshot Capture Module
//!
//! This module provides cross-platform screenshot capture functionality.

use agent_core::{ImageFormat, Result, Screenshot};
use async_trait::async_trait;
use std::sync::Arc;
use tokio::sync::Mutex;

/// Screenshot capturer trait.
#[async_trait]
pub trait ScreenshotCapturer: Send + Sync {
    /// Create a new capturer instance.
    fn new() -> Result<Self>
    where
        Self: Sized;

    /// Capture the entire screen.
    async fn capture_screen(&self) -> Result<Screenshot>;

    /// Capture a specific region of the screen.
    async fn capture_region(&self, x: u32, y: u32, width: u32, height: u32) -> Result<Screenshot>;

    /// Get the number of displays.
    async fn get_display_count(&self) -> Result<u32>;

    /// Get display information for all displays.
    async fn get_displays(&self) -> Result<Vec<agent_core::models::DisplayInfo>>;
}

/// Platform-agnostic screenshot capturer wrapper.
pub struct Capturer {
    inner: Arc<Mutex<dyn ScreenshotCapturer>>,
}

impl Capturer {
    /// Create a new capturer for the current platform.
    pub async fn new() -> Result<Self> {
        #[cfg(target_os = "linux")]
        let inner = linux::LinuxScreenshotCapturer::new()?;

        #[cfg(target_os = "macos")]
        let inner = macos::MacosScreenshotCapturer::new()?;

        #[cfg(target_os = "windows")]
        let inner = windows::WindowsScreenshotCapturer::new()?;

        Ok(Self {
            inner: Arc::new(Mutex::new(inner)),
        })
    }

    /// Capture the primary screen.
    pub async fn capture(&self) -> Result<Screenshot> {
        let capturer = self.inner.lock().await;
        capturer.capture_screen().await
    }

    /// Capture a specific region.
    pub async fn capture_region(&self, x: u32, y: u32, width: u32, height: u32) -> Result<Screenshot> {
        let capturer = self.inner.lock().await;
        capturer.capture_region(x, y, width, height).await
    }

    /// Get the number of displays.
    pub async fn display_count(&self) -> Result<u32> {
        let capturer = self.inner.lock().await;
        capturer.get_display_count().await
    }

    /// Get information about all displays.
    pub async fn displays(&self) -> Result<Vec<agent_core::models::DisplayInfo>> {
        let capturer = self.inner.lock().await;
        capturer.get_displays().await
    }
}

// Linux implementation using X11
#[cfg(target_os = "linux")]
mod linux {
    use super::*;
    use std::ptr;
    use agent_core::PlatformError;

    pub struct LinuxScreenshotCapturer {
        display: Option<*mut x11::xlib::Display>,
        screen: i32,
    }

    unsafe impl Send for LinuxScreenshotCapturer {}
    unsafe impl Sync for LinuxScreenshotCapturer {}

    impl LinuxScreenshotCapturer {
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
                    display: Some(display),
                    screen,
                })
            }
        }

        fn get_screen_size(&self) -> (u32, u32) {
            unsafe {
                let display = self.display.unwrap();
                let screen = self.screen;

                let width = x11::xlib::XDisplayWidth(display, screen) as u32;
                let height = x11::xlib::XDisplayHeight(display, screen) as u32;

                (width, height)
            }
        }

        fn capture_region_impl(&self, x: u32, y: u32, width: u32, height: u32) -> Result<Screenshot> {
            unsafe {
                let display = self.display.unwrap();
                let screen = self.screen;

                // Get the root window
                let root_window = x11::xlib::XRootWindow(display, screen);

                // Create a graphics context
                let gc = x11::xlib::XCreateGC(display, root_window, 0, ptr::null_mut());

                // Capture the screen region using XGetImage
                let ximage = x11::xlib::XGetImage(
                    display,
                    root_window,
                    x as i32,
                    y as i32,
                    width,
                    height,
                    0xFFFFFFFF, // All planes
                    x11::xlib::ZPixmap,
                );

                if ximage.is_null() {
                    x11::xlib::XFreeGC(display, gc);
                    // Fall back to external tool for Wayland
                    return self.capture_with_fallback();
                }

                // Get image properties
                let img_width = (*ximage).width;
                let img_height = (*ximage).height;
                let depth = (*ximage).depth;

                tracing::debug!("Captured screenshot: {}x{} at depth {}", img_width, img_height, depth);

                // Convert XImage data to RGB
                let rgb_data = if depth == 24 || depth == 32 {
                    self.convert_ximage_to_rgb(ximage, width, height)
                } else {
                    // Fallback for other depths
                    x11::xlib::XDestroyImage(ximage);
                    x11::xlib::XFreeGC(display, gc);
                    return Err(agent_core::AgentError::Screenshot(
                        format!("Unsupported color depth: {}", depth),
                    ));
                };

                // Free the XImage and graphics context
                x11::xlib::XDestroyImage(ximage);
                x11::xlib::XFreeGC(display, gc);

                // Create RGB image
                let img: image::RgbImage =
                    image::ImageBuffer::from_raw(width, height, rgb_data).ok_or_else(|| {
                        agent_core::AgentError::Screenshot(
                            "Failed to create image buffer from raw data".to_string(),
                        )
                    })?;

                // Encode to PNG
                let mut buffer = Vec::new();
                {
                    let mut cursor = std::io::Cursor::new(&mut buffer);
                    img.write_to(&mut cursor, image::ImageFormat::Png).map_err(|e| {
                        agent_core::AgentError::Screenshot(format!("Failed to encode PNG: {}", e))
                    })?;
                }

                Ok(Screenshot::new(
                    buffer,
                    width,
                    height,
                    ImageFormat::Png,
                    "Unknown".to_string(),
                    "Unknown".to_string(),
                ))
            }
        }

        fn convert_ximage_to_rgb(
            &self,
            ximage: *mut x11::xlib::XImage,
            width: u32,
            height: u32,
        ) -> Vec<u8> {
            unsafe {
                let data = (*ximage).data as *const u8;
                let bytes_per_line = (*ximage).bytes_per_line as usize;

                let mut rgb_data = Vec::with_capacity((width * height * 3) as usize);

                for y in 0..height {
                    for x in 0..width {
                        let pixel_offset = (y as usize * bytes_per_line) + (x as usize * 4);
                        let b = *data.add(pixel_offset);
                        let g = *data.add(pixel_offset + 1);
                        let r = *data.add(pixel_offset + 2);
                        // Skip alpha channel (byte 3)

                        rgb_data.push(r);
                        rgb_data.push(g);
                        rgb_data.push(b);
                    }
                }

                rgb_data
            }
        }

        fn capture_with_fallback(&self) -> Result<Screenshot> {
            use std::process::Command;
            use std::io::Read;

            // Try grim (Wayland screenshot tool)
            if let Ok(output) = Command::new("grim")
                .arg("-")
                .output()
            {
                if output.status.success() && !output.stdout.is_empty() {
                    tracing::info!("Captured screenshot using grim");
                    return Ok(Screenshot::new(
                        output.stdout,
                        1920, // Default, will be updated from PNG
                        1080,
                        ImageFormat::Png,
                        "Unknown".to_string(),
                        "Unknown".to_string(),
                    ));
                }
            }

            // Try gnome-screenshot
            let temp_file = "/tmp/agent-screenshot-fallback.png";
            let _ = std::fs::remove_file(temp_file);

            if let Ok(_) = Command::new("gnome-screenshot")
                .arg("-f")
                .arg(temp_file)
                .output()
            {
                // Give it a moment to capture
                std::thread::sleep(std::time::Duration::from_millis(100));

                if let Ok(mut data) = std::fs::read(temp_file) {
                    let _ = std::fs::remove_file(temp_file);
                    tracing::info!("Captured screenshot using gnome-screenshot");
                    return Ok(Screenshot::new(
                        data,
                        1920,
                        1080,
                        ImageFormat::Png,
                        "Unknown".to_string(),
                        "Unknown".to_string(),
                    ));
                }
            }

            // No fallback available
            tracing::error!("Screenshot failed: X11 capture failed and no Wayland screenshot tool available");
            tracing::error!("Install 'grim' or 'gnome-screenshot' for Wayland support");
            Err(agent_core::AgentError::Screenshot(
                "Screenshot failed on Wayland. Install 'grim' or 'gnome-screenshot'".to_string(),
            ))
        }
    }

    impl Drop for LinuxScreenshotCapturer {
        fn drop(&mut self) {
            if let Some(display) = self.display {
                unsafe {
                    x11::xlib::XCloseDisplay(display);
                }
            }
        }
    }

    #[async_trait]
    impl ScreenshotCapturer for LinuxScreenshotCapturer {
        fn new() -> Result<Self>
        where
            Self: Sized,
        {
            Self::new()
        }

        async fn capture_screen(&self) -> Result<Screenshot> {
            let (width, height) = self.get_screen_size();
            self.capture_region_impl(0, 0, width, height)
        }

        async fn capture_region(&self, x: u32, y: u32, width: u32, height: u32) -> Result<Screenshot> {
            self.capture_region_impl(x, y, width, height)
        }

        async fn get_display_count(&self) -> Result<u32> {
            Ok(1) // Simplified
        }

        async fn get_displays(&self) -> Result<Vec<agent_core::models::DisplayInfo>> {
            let (width, height) = self.get_screen_size();

            Ok(vec![agent_core::models::DisplayInfo {
                id: 0,
                x: 0,
                y: 0,
                width,
                height,
                scale_factor: 1.0,
                primary: true,
            }])
        }
    }
}

// macOS implementation using Core Graphics
#[cfg(target_os = "macos")]
mod macos {
    use super::*;

    pub struct MacosScreenshotCapturer;

    impl MacosScreenshotCapturer {
        pub fn new() -> Result<Self> {
            Ok(Self)
        }
    }

    #[async_trait]
    impl ScreenshotCapturer for MacosScreenshotCapturer {
        fn new() -> Result<Self>
        where
            Self: Sized,
        {
            Self::new()
        }

        async fn capture_screen(&self) -> Result<Screenshot> {
            tracing::warn!("Screenshot capture not implemented on macOS yet");
            Err(agent_core::AgentError::Screenshot("Not implemented".to_string()))
        }

        async fn capture_region(&self, _x: u32, _y: u32, _width: u32, _height: u32) -> Result<Screenshot> {
            tracing::warn!("Screenshot capture not implemented on macOS yet");
            Err(agent_core::AgentError::Screenshot("Not implemented".to_string()))
        }

        async fn get_display_count(&self) -> Result<u32> {
            Ok(1)
        }

        async fn get_displays(&self) -> Result<Vec<agent_core::models::DisplayInfo>> {
            Ok(vec![])
        }
    }
}

// Windows implementation using GDI+
#[cfg(target_os = "windows")]
mod windows {
    use super::*;

    pub struct WindowsScreenshotCapturer;

    impl WindowsScreenshotCapturer {
        pub fn new() -> Result<Self> {
            Ok(Self)
        }
    }

    #[async_trait]
    impl ScreenshotCapturer for WindowsScreenshotCapturer {
        fn new() -> Result<Self>
        where
            Self: Sized,
        {
            Self::new()
        }

        async fn capture_screen(&self) -> Result<Screenshot> {
            tracing::warn!("Screenshot capture not implemented on Windows yet");
            Err(agent_core::AgentError::Screenshot("Not implemented".to_string()))
        }

        async fn capture_region(&self, _x: u32, _y: u32, _width: u32, _height: u32) -> Result<Screenshot> {
            tracing::warn!("Screenshot capture not implemented on Windows yet");
            Err(agent_core::AgentError::Screenshot("Not implemented".to_string()))
        }

        async fn get_display_count(&self) -> Result<u32> {
            Ok(1)
        }

        async fn get_displays(&self) -> Result<Vec<agent_core::models::DisplayInfo>> {
            Ok(vec![])
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_capturer_creation() {
        let capturer = Capturer::new().await;
        assert!(capturer.is_ok());
    }

    #[tokio::test]
    async fn test_get_display_count() {
        let capturer = Capturer::new().await.unwrap();
        let count = capturer.display_count().await.unwrap();
        assert!(count > 0);
    }
}
