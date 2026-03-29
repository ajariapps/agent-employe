//! # API Client
//!
//! HTTP client for communicating with the monitoring server.
//! Features retry logic, exponential backoff, and persistent queuing.

pub mod http;
pub mod queue;

pub use http::ApiClient;
pub use queue::PersistentQueue;
