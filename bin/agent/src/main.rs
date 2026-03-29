//! # Employee Monitoring Agent
//!
//! Cross-platform employee monitoring agent written in Rust.

use agent_core::{
    AgentConfig, Activity, ActivityRequest, ConfigLoader, RegisterRequest,
    ScreenshotRequest, SystemInfo, VERSION,
    HeartbeatRequest,
};
use anyhow::Result;
use client::ApiClient;
use clap::{Parser, Subcommand};
use secrecy::ExposeSecret;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::time::interval;
use tracing::{error, info, warn, debug};
use tracing_subscriber::fmt::format::FmtSpan;

/// Employee Monitoring Agent
#[derive(Parser, Debug)]
#[command(name = "agent")]
#[command(author = "Employee Monitoring Team")]
#[command(version = VERSION)]
#[command(about = "Cross-platform employee monitoring agent", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,

    /// Server URL
    #[arg(long, env = "AGENT_SERVER_URL")]
    server_url: Option<String>,

    /// API token
    #[arg(long, env = "AGENT_API_TOKEN")]
    api_token: Option<String>,

    /// Log level
    #[arg(long, env = "AGENT_LOG_LEVEL", default_value = "info")]
    log_level: String,

    /// Config file path
    #[arg(short, long, env = "AGENT_CONFIG")]
    config: Option<String>,

    /// Run in foreground (don't daemonize)
    #[arg(long, default_value = "false")]
    foreground: bool,
}

#[derive(Subcommand, Debug)]
enum Commands {
    /// Run the agent
    Run {
        /// Server URL
        #[arg(long, env = "AGENT_SERVER_URL")]
        server_url: Option<String>,

        /// API token
        #[arg(long, env = "AGENT_API_TOKEN")]
        api_token: Option<String>,

        /// Agent ID
        #[arg(long, env = "AGENT_ID")]
        agent_id: Option<String>,

        /// Skip registration
        #[arg(long, default_value = "false")]
        skip_registration: bool,
    },

    /// Register with the server
    Register {
        /// Server URL
        #[arg(long, env = "AGENT_SERVER_URL")]
        server_url: Option<String>,
    },

    /// Show status
    Status,

    /// Show version
    Version,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    // Initialize logging
    init_logging(&cli.log_level);

    info!("Employee Monitoring Agent v{} starting", VERSION);

    match cli.command.unwrap_or(Commands::Run {
        server_url: cli.server_url,
        api_token: cli.api_token,
        agent_id: None,
        skip_registration: false,
    }) {
        Commands::Run { server_url, api_token, agent_id, skip_registration } => {
            run_agent(server_url, api_token, agent_id, skip_registration).await
        }
        Commands::Register { server_url } => {
            register_agent(server_url).await
        }
        Commands::Status => {
            show_status().await
        }
        Commands::Version => {
            println!("Employee Monitoring Agent v{}", VERSION);
            Ok(())
        }
    }
}

/// Initialize logging
fn init_logging(level: &str) {
    let log_level = match level.to_lowercase().as_str() {
        "trace" => tracing::Level::TRACE,
        "debug" => tracing::Level::DEBUG,
        "info" => tracing::Level::INFO,
        "warn" => tracing::Level::WARN,
        "error" => tracing::Level::ERROR,
        _ => tracing::Level::INFO,
    };

    tracing_subscriber::fmt()
        .with_max_level(log_level)
        .with_span_events(FmtSpan::CLOSE)
        .with_target(false)
        .compact()
        .init();
}

/// Run the agent
async fn run_agent(
    server_url: Option<String>,
    api_token: Option<String>,
    agent_id: Option<String>,
    skip_registration: bool,
) -> Result<()> {
    info!("Loading configuration...");

    let mut config = load_config().await?;

    // Override with CLI args
    if let Some(url) = server_url {
        config.server.url = url;
    }
    if let Some(token) = api_token {
        config.api_token = Some(token.into());
    }

    info!("Server URL: {}", config.server.url);

    // Initialize API client
    let client_config = client::http::ClientConfig {
        server_url: config.server.url.clone(),
        timeout_secs: config.server.timeout_secs,
        connect_timeout_secs: config.server.connect_timeout_secs,
        max_retries: config.server.max_retries,
        queue_path: config.agent.queue_file.clone(),
    };

    let client = Arc::new(ApiClient::new(client_config).await?);

    // Set token if provided
    if let Some(token) = &config.api_token {
        client.set_token(token.expose_secret().clone()).await;
    }

    // Set agent ID if provided
    if let Some(id) = agent_id {
        client.set_agent_id(id).await;
    }

    // Initialize platform
    let platform = Arc::new(platform::PlatformWrapper::new()?);
    let sys_info = SystemInfo::current();

    info!("OS: {}", sys_info.os_type);
    info!("Arch: {}", sys_info.arch);
    info!("Hostname: {}", sys_info.hostname);

    // Register if needed
    if !skip_registration && client.agent_id().await.is_none() {
        info!("Registering with server...");
        let req = RegisterRequest {
            hostname: sys_info.hostname.clone(),
            os_type: sys_info.os_type.clone(),
            os_version: sys_info.os_version.clone(),
            ip_address: None, // Server will detect
            mac_address: None, // Server will detect
        };

        match client.register(&req).await {
            Ok(resp) => {
                info!("Registered successfully. Employee ID: {}", resp.employee_id);
                // Store employee_id as agent_id for local reference
                client.set_agent_id(resp.employee_id.clone()).await;
            }
            Err(e) => {
                warn!("Registration failed: {}. Continuing in offline mode.", e);
            }
        }
    }

    // Create agent instance
    let agent = Agent::new(config, client, platform).await?;
    let running = Arc::new(AtomicBool::new(true));

    // Setup signal handlers
    let running_clone = running.clone();
    tokio::spawn(async move {
        #[cfg(unix)]
        {
            use tokio::signal::unix::{signal, SignalKind};

            let mut sigterm = signal(SignalKind::terminate()).unwrap();
            let mut sigint = signal(SignalKind::interrupt()).unwrap();

            tokio::select! {
                _ = sigterm.recv() => {
                    info!("Received SIGTERM, shutting down...");
                    running_clone.store(false, Ordering::Relaxed);
                }
                _ = sigint.recv() => {
                    info!("Received SIGINT, shutting down...");
                    running_clone.store(false, Ordering::Relaxed);
                }
            }
        }

        #[cfg(windows)]
        {
            use tokio::signal::windows;

            let mut ctrl_c = windows::ctrl_c().unwrap();
            let _ = ctrl_c.recv().await;
            info!("Received Ctrl+C, shutting down...");
            running_clone.store(false, Ordering::Relaxed);
        }
    });

    // Run agent main loop
    info!("Agent started successfully");
    info!("Press Ctrl+C to stop");

    agent.run(running).await?;

    info!("Agent stopped");
    Ok(())
}

/// Load configuration
async fn load_config() -> Result<AgentConfig> {
    let loader = ConfigLoader::new();
    loader.load().await.map_err(Into::into)
}

/// Register with server
async fn register_agent(server_url: Option<String>) -> Result<()> {
    let config = load_config().await?;
    let url = server_url.unwrap_or(config.server.url);

    info!("Registering with server: {}", url);

    let sys_info = SystemInfo::current();
    let req = RegisterRequest {
        hostname: sys_info.hostname.clone(),
        os_type: sys_info.os_type.clone(),
        os_version: sys_info.os_version.clone(),
        ip_address: None,
        mac_address: None,
    };

    println!("Registration request:");
    println!("  Hostname: {}", req.hostname);
    println!("  OS: {} {}", req.os_type, req.os_version);
    println!("\nNote: Run 'agent run' to start the agent with actual server connection");

    Ok(())
}

/// Show status
async fn show_status() -> Result<()> {
    let sys_info = SystemInfo::current();

    println!("Employee Monitoring Agent v{}", VERSION);
    println!("OS: {}", sys_info.os_type);
    println!("Arch: {}", sys_info.arch);
    println!("Hostname: {}", sys_info.hostname);
    println!("CPUs: {}", sys_info.cpu_count);
    println!("Total Memory: {} MB", sys_info.total_memory / (1024 * 1024));

    Ok(())
}

/// Main agent implementation
struct Agent {
    config: AgentConfig,
    client: Arc<ApiClient>,
    platform: Arc<platform::PlatformWrapper>,
    last_activity: Arc<tokio::sync::Mutex<Option<Activity>>>,
    idle_since: Arc<tokio::sync::Mutex<Option<Instant>>>,
}

impl Agent {
    /// Create a new agent instance
    async fn new(
        config: AgentConfig,
        client: Arc<ApiClient>,
        platform: Arc<platform::PlatformWrapper>,
    ) -> Result<Self> {
        Ok(Self {
            config,
            client,
            platform,
            last_activity: Arc::new(tokio::sync::Mutex::new(None)),
            idle_since: Arc::new(tokio::sync::Mutex::new(None)),
        })
    }

    /// Run the agent main loop
    async fn run(&self, running: Arc<AtomicBool>) -> Result<()> {
        // Spawn heartbeat task
        let heartbeat_client = self.client.clone();
        let heartbeat_interval = self.config.intervals.heartbeat_secs;
        let sys_info = SystemInfo::current();

        let heartbeat_running = running.clone();
        tokio::spawn(async move {
            let mut timer = interval(Duration::from_secs(heartbeat_interval));

            while heartbeat_running.load(Ordering::Relaxed) {
                timer.tick().await;

                let req = HeartbeatRequest {
                    hostname: sys_info.hostname.clone(),
                };

                match heartbeat_client.heartbeat(&req).await {
                    Ok(resp) => {
                        debug!("Heartbeat successful: {}", resp.message);

                        // Update API token if provided
                        if let Some(new_token) = resp.api_token {
                            heartbeat_client.set_token(new_token).await;
                        }
                    }
                    Err(e) => {
                        error!("Heartbeat failed: {}", e);
                    }
                }
            }
        });

        // Spawn activity tracking task
        let activity_platform = self.platform.clone();
        let activity_client = self.client.clone();
        let activity_interval = self.config.intervals.activity_secs;
        let last_activity = self.last_activity.clone();
        let idle_since = self.idle_since.clone();
        let sys_info = SystemInfo::current();

        let activity_running = running.clone();
        tokio::spawn(async move {
            let mut timer = interval(Duration::from_secs(activity_interval));

            while activity_running.load(Ordering::Relaxed) {
                timer.tick().await;

                // Check idle status
                let is_idle = match activity_platform.is_idle().await {
                    Ok(idle) => idle,
                    Err(e) => {
                        warn!("Failed to check idle status: {}", e);
                        false
                    }
                };

                if is_idle {
                    let mut idle = idle_since.lock().await;
                    if idle.is_none() {
                        *idle = Some(Instant::now());
                        info!("User became idle");
                    }
                    continue;
                } else {
                    *idle_since.lock().await = None;
                }

                // Get current activity
                match activity_platform.get_active_window().await {
                    Ok(window_info) => {
                        let activity = Activity::new(
                            window_info.title.clone(),
                            window_info.app_name.clone(),
                            window_info.app_path.clone(),
                            None, // TODO: Extract URL if browser
                        );

                        // Check if activity changed
                        let should_log = {
                            let last = last_activity.lock().await;
                            last.as_ref().map_or(true, |l| {
                                l.window_title != activity.window_title
                                    || l.app_name != activity.app_name
                            })
                        };

                        if should_log {
                            debug!("Activity changed: {} - {}", activity.app_name, activity.window_title);

                            let req = ActivityRequest {
                                hostname: sys_info.hostname.clone(),
                                timestamp: activity.timestamp.to_rfc3339(),
                                window_title: activity.window_title.clone(),
                                app_name: activity.app_name.clone(),
                                url: activity.url.clone(),
                                activity_type: "window_change".to_string(),
                                notes: None,
                                duration_seconds: None,
                            };

                            if let Err(e) = activity_client.log_activity(&req).await {
                                error!("Failed to log activity: {}", e);
                            } else {
                                *last_activity.lock().await = Some(activity);
                            }
                        }
                    }
                    Err(e) => {
                        error!("Failed to get active window: {}", e);
                    }
                }
            }
        });

        // Spawn screenshot task
        let screenshot_platform = self.platform.clone();
        let screenshot_client = self.client.clone();
        let screenshot_interval = self.config.intervals.screenshot_secs;
        let sys_info = SystemInfo::current();

        let screenshot_running = running.clone();
        tokio::spawn(async move {
            let mut timer = interval(Duration::from_secs(screenshot_interval));

            // Initialize screenshot capturer
            let capturer = match screenshot::Capturer::new().await {
                Ok(c) => c,
                Err(e) => {
                    warn!("Failed to initialize screenshot capturer: {}", e);
                    return;
                }
            };

            while screenshot_running.load(Ordering::Relaxed) {
                timer.tick().await;

                // Check if idle
                let is_idle = match screenshot_platform.is_idle().await {
                    Ok(idle) => idle,
                    Err(e) => {
                        warn!("Failed to check idle status: {}", e);
                        false
                    }
                };

                if is_idle {
                    debug!("Skipping screenshot - user is idle");
                    continue;
                }

                // Capture screenshot
                match capturer.capture().await {
                    Ok(screenshot) => {
                        debug!("Captured screenshot: {}x{}, {} bytes",
                               screenshot.width, screenshot.height, screenshot.size_bytes());

                        // Get current window info for context
                        let (title, app_name) = match screenshot_platform.get_active_window().await {
                            Ok(info) => (info.title, info.app_name),
                            Err(_) => ("Unknown".to_string(), "Unknown".to_string()),
                        };

                        // Prepare screenshot request
                        let req = ScreenshotRequest {
                            hostname: sys_info.hostname.clone(),
                            timestamp: screenshot.timestamp.to_rfc3339(),
                            image_data: screenshot.to_base64(),
                            width: screenshot.width as i32,
                            height: screenshot.height as i32,
                            window_title: title,
                            app_name,
                        };

                        // Upload screenshot
                        if let Err(e) = screenshot_client.upload_screenshot(&req).await {
                            error!("Failed to upload screenshot: {}", e);
                        } else {
                            debug!("Screenshot uploaded successfully");
                        }
                    }
                    Err(e) => {
                        error!("Failed to capture screenshot: {}", e);
                    }
                }
            }
        });

        // Spawn queue processing task
        let queue_client = self.client.clone();
        let queue_running = running.clone();

        tokio::spawn(async move {
            let mut timer = interval(Duration::from_secs(30));

            while queue_running.load(Ordering::Relaxed) {
                timer.tick().await;

                match queue_client.process_queue().await {
                    Ok(count) if count > 0 => {
                        info!("Processed {} queued requests", count);
                    }
                    Err(e) => {
                        warn!("Failed to process queue: {}", e);
                    }
                    _ => {}
                }
            }
        });

        // Wait for shutdown signal
        while running.load(Ordering::Relaxed) {
            tokio::time::sleep(Duration::from_secs(1)).await;
        }

        Ok(())
    }
}
