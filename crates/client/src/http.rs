//! HTTP API client with retry logic and circuit breaker.

use agent_core::{
    ApiError, AgentError, QueuedRequest, RegisterRequest, RegisterResponse,
    ActivityRequest, ScreenshotRequest, HeartbeatRequest, HeartbeatResponse,
    Result,
};
use backoff::{ExponentialBackoff, backoff::Backoff};
use chrono::Utc;
use reqwest::{Client, Response};
use secrecy::{Secret, ExposeSecret};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::RwLock;
use tracing::{debug, warn, error};

/// API client configuration.
#[derive(Debug, Clone)]
pub struct ClientConfig {
    /// Server base URL.
    pub server_url: String,

    /// Request timeout in seconds.
    pub timeout_secs: u64,

    /// Connection timeout in seconds.
    pub connect_timeout_secs: u64,

    /// Maximum retry attempts.
    pub max_retries: u32,

    /// Path to queue file for offline requests.
    pub queue_path: std::path::PathBuf,
}

impl Default for ClientConfig {
    fn default() -> Self {
        Self {
            server_url: "http://localhost:8080".to_string(),
            timeout_secs: 30,
            connect_timeout_secs: 10,
            max_retries: 3,
            queue_path: std::path::PathBuf::from("queue.json"),
        }
    }
}

/// HTTP API client with retry logic and queueing.
pub struct ApiClient {
    /// HTTP client.
    client: Client,

    /// Client configuration.
    config: ClientConfig,

    /// API token (Bearer authentication).
    api_token: Arc<RwLock<Option<Secret<String>>>>,

    /// Agent ID.
    agent_id: Arc<RwLock<Option<String>>>,

    /// Request queue for offline scenarios.
    queue: Arc<tokio::sync::Mutex<super::queue::PersistentQueue>>,

    /// Circuit breaker state.
    circuit_breaker: Arc<RwLock<CircuitBreaker>>,
}

/// Circuit breaker for API calls.
#[derive(Debug)]
struct CircuitBreaker {
    /// Number of consecutive failures.
    failures: u32,

    /// Whether the circuit is open.
    is_open: bool,

    /// Last failure time.
    last_failure: Option<chrono::DateTime<Utc>>,

    /// Failure threshold before opening circuit.
    threshold: u32,

    /// Timeout before attempting to close circuit (in seconds).
    timeout_secs: u64,
}

impl CircuitBreaker {
    /// Create a new circuit breaker.
    fn new(threshold: u32, timeout_secs: u64) -> Self {
        Self {
            failures: 0,
            is_open: false,
            last_failure: None,
            threshold,
            timeout_secs,
        }
    }

    /// Check if we should allow a request.
    fn can_attempt(&self) -> bool {
        if !self.is_open {
            return true;
        }

        if let Some(last_failure) = self.last_failure {
            let elapsed = Utc::now().signed_duration_since(last_failure);
            if elapsed.num_seconds() > self.timeout_secs as i64 {
                return true;
            }
        }

        false
    }

    /// Record a successful request.
    fn on_success(&mut self) {
        self.failures = 0;
        self.is_open = false;
        self.last_failure = None;
    }

    /// Record a failed request.
    fn on_failure(&mut self) {
        self.failures += 1;
        self.last_failure = Some(Utc::now());

        if self.failures >= self.threshold {
            self.is_open = true;
            warn!("Circuit breaker opened after {} failures", self.failures);
        }
    }
}

impl ApiClient {
    /// Create a new API client.
    pub async fn new(config: ClientConfig) -> Result<Self> {
        let client = Client::builder()
            .timeout(Duration::from_secs(config.timeout_secs))
            .connect_timeout(Duration::from_secs(config.connect_timeout_secs))
            .pool_max_idle_per_host(10)
            .pool_idle_timeout(Duration::from_secs(90))
            .build()
            .map_err(|e| AgentError::Api(ApiError::Other(e.to_string())))?;

        // Initialize queue
        let queue = super::queue::PersistentQueue::new(&config.queue_path)
            .await
            .unwrap_or_else(|e| {
                warn!("Failed to initialize queue: {}, using in-memory queue", e);
                super::queue::PersistentQueue::memory()
            });

        Ok(Self {
            client,
            config,
            api_token: Arc::new(RwLock::new(None)),
            agent_id: Arc::new(RwLock::new(None)),
            queue: Arc::new(tokio::sync::Mutex::new(queue)),
            circuit_breaker: Arc::new(RwLock::new(CircuitBreaker::new(5, 60))),
        })
    }

    /// Set the API token for authentication.
    pub async fn set_token(&self, token: String) {
        *self.api_token.write().await = Some(Secret::new(token));
    }

    /// Set the agent ID.
    pub async fn set_agent_id(&self, agent_id: String) {
        *self.agent_id.write().await = Some(agent_id);
    }

    /// Register the agent with the server.
    pub async fn register(&self, request: &RegisterRequest) -> Result<RegisterResponse> {
        let response = self.post("/api/v1/agents/register", request).await?;

        // Parse response
        let register_response: RegisterResponse = response
            .json()
            .await
            .map_err(|e| AgentError::Api(ApiError::Other(e.to_string())))?;

        // Store credentials - use employee_id as agent_id
        self.set_token(register_response.api_token.clone()).await;
        self.set_agent_id(register_response.employee_id.clone()).await;

        Ok(register_response)
    }

    /// Send a heartbeat to the server.
    pub async fn heartbeat(&self, request: &HeartbeatRequest) -> Result<HeartbeatResponse> {
        self.post("/api/v1/agents/heartbeat", request).await?.json().await
            .map_err(|e| AgentError::Api(ApiError::Other(e.to_string())))
    }

    /// Log an activity event.
    pub async fn log_activity(&self, request: &ActivityRequest) -> Result<()> {
        self.post("/api/v1/activity", request).await?;
        Ok(())
    }

    /// Upload a screenshot.
    pub async fn upload_screenshot(&self, request: &ScreenshotRequest) -> Result<()> {
        self.post("/api/v1/screenshots", request).await?;
        Ok(())
    }

    /// Process queued requests.
    pub async fn process_queue(&self) -> Result<usize> {
        let queue = self.queue.lock().await;
        let mut processed = 0;

        loop {
            match queue.pop().await {
                Ok(Some(request)) => {
                    match self.post(&request.endpoint, &request.body).await {
                        Ok(_) => processed += 1,
                        Err(e) => {
                            // Re-queue with incremented attempts
                            let mut updated = request;
                            updated.attempts += 1;

                            if updated.attempts < self.config.max_retries {
                                queue.push_front(updated).await?;
                            } else {
                                warn!("Dropping request after {} attempts: {}", updated.attempts, updated.endpoint);
                            }

                            // Return the error to stop processing
                            return Err(e);
                        }
                    }
                }
                Ok(None) => break,
                Err(e) => {
                    error!("Error reading from queue: {}", e);
                    break;
                }
            }
        }

        Ok(processed)
    }

    /// Queue a request for later processing.
    pub async fn queue_request(&self, endpoint: String, body: serde_json::Value) -> Result<()> {
        let queued = QueuedRequest {
            endpoint,
            body,
            timestamp: Utc::now(),
            attempts: 0,
            max_attempts: self.config.max_retries,
        };

        let queue = self.queue.lock().await;
        queue.push(queued).await?;
        Ok(())
    }

    /// Make a POST request with retry logic.
    async fn post<T: serde::Serialize>(&self, endpoint: &str, body: &T) -> Result<Response> {
        // Check circuit breaker
        {
            let cb = self.circuit_breaker.read().await;
            if !cb.can_attempt() {
                return Err(AgentError::Api(ApiError::RateLimited(60)));
            }
        }

        let url = format!("{}{}", self.config.server_url, endpoint);
        let token = self.api_token.read().await;

        debug!("POST {}", url);

        // Clone request for retry
        let body_bytes = serde_json::to_vec(body)
            .map_err(|e| AgentError::Api(ApiError::Other(e.to_string())))?;

        let mut attempt = 0u32;
        let mut backoff = ExponentialBackoff::default();

        loop {
            attempt += 1;

            // Build request
            let mut request_builder = self.client.post(&url).header("Content-Type", "application/json");

            if let Some(ref token) = *token {
                request_builder = request_builder.header(
                    "Authorization",
                    format!("Bearer {}", token.expose_secret()),
                );
            }

            let request_builder = request_builder
                .timeout(Duration::from_secs(self.config.timeout_secs));

            // Execute request
            match request_builder
                .body(body_bytes.clone())
                .send()
                .await
            {
                Ok(response) => {
                    let status = response.status();

                    if status.is_success() {
                        // Record success
                        self.circuit_breaker.write().await.on_success();
                        return Ok(response);
                    }

                    if status.is_client_error() {
                        // Client errors are permanent
                        let error_text = response.text().await.unwrap_or_else(|_| "Unknown error".to_string());
                        return Err(AgentError::Api(ApiError::Server(status.as_u16(), error_text)));
                    }

                    if status.is_server_error() {
                        // Server errors are transient - retry
                        if attempt >= self.config.max_retries {
                            let error_text = response.text().await.unwrap_or_else(|_| "Unknown error".to_string());
                            return Err(AgentError::Api(ApiError::Server(status.as_u16(), error_text)));
                        }

                        warn!("Server error {} on attempt {}, retrying...", status, attempt);
                        self.circuit_breaker.write().await.on_failure();
                    }
                }
                Err(e) => {
                    if e.is_timeout() {
                        if attempt >= self.config.max_retries {
                            return Err(AgentError::Api(ApiError::Timeout(self.config.timeout_secs)));
                        }

                        warn!("Timeout on attempt {}, retrying...", attempt);
                    } else if e.is_connect() {
                        if attempt >= self.config.max_retries {
                            return Err(AgentError::Api(ApiError::Other(e.to_string())));
                        }

                        warn!("Connection error on attempt {}, retrying...", attempt);
                    } else {
                        return Err(AgentError::Api(ApiError::Other(e.to_string())));
                    }

                    self.circuit_breaker.write().await.on_failure();
                }
            }

            // Wait before retry
            let wait_duration = backoff.next_backoff()
                .unwrap_or(Duration::from_secs(60));

            debug!("Waiting {:?} before retry", wait_duration);
            tokio::time::sleep(wait_duration).await;
        }
    }

    /// Get the agent ID.
    pub async fn agent_id(&self) -> Option<String> {
        self.agent_id.read().await.clone()
    }

    /// Get the queue size.
    pub async fn queue_size(&self) -> Result<usize> {
        let queue = self.queue.lock().await;
        Ok(queue.len().await?)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_circuit_breaker() {
        let mut cb = CircuitBreaker::new(3, 10);

        assert!(cb.can_attempt());

        // Simulate failures
        cb.on_failure();
        cb.on_failure();
        cb.on_failure();

        // Circuit should be open
        assert!(!cb.can_attempt());

        // Wait for timeout
        std::thread::sleep(std::time::Duration::from_secs(11));

        // Should be able to attempt again
        assert!(cb.can_attempt());
    }
}
