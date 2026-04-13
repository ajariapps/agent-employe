//! Persistent queue for offline request handling.

use agent_core::{QueuedRequest, Result};
use std::path::Path;
use tokio::fs;
use tokio::sync::Mutex;

/// Persistent queue for storing requests when offline.
pub struct PersistentQueue {
    /// Queue storage backend.
    backend: Mutex<QueueBackend>,
}

/// Queue backend implementation.
enum QueueBackend {
    /// File-based persistent storage.
    File {
        path: std::path::PathBuf,
        queue: Vec<QueuedRequest>,
        dirty: bool,
    },

    /// In-memory storage (fallback).
    Memory(Vec<QueuedRequest>),
}

impl PersistentQueue {
    /// Create a new persistent queue.
    pub async fn new(path: &Path) -> Result<Self> {
        // Ensure parent directory exists
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).await
                .map_err(|e| agent_core::AgentError::Io(e))?;
        }

        let backend = if path.exists() {
            // Load existing queue from file
            let content = fs::read_to_string(path).await
                .map_err(|e| agent_core::AgentError::Io(e))?;

            let queue: Vec<QueuedRequest> = serde_json::from_str(&content)
                .map_err(|e| agent_core::AgentError::Serialization(e))?;

            tracing::info!("Loaded {} items from queue file", queue.len());

            QueueBackend::File {
                path: path.to_path_buf(),
                queue,
                dirty: false,
            }
        } else {
            // Create new file-based queue
            tracing::info!("Creating new queue at {:?}", path);
            QueueBackend::File {
                path: path.to_path_buf(),
                queue: Vec::new(),
                dirty: false,
            }
        };

        Ok(Self {
            backend: Mutex::new(backend),
        })
    }

    /// Create an in-memory queue (fallback).
    pub fn memory() -> Self {
        Self {
            backend: Mutex::new(QueueBackend::Memory(Vec::new())),
        }
    }

    /// Push an item to the back of the queue.
    pub async fn push(&self, item: QueuedRequest) -> Result<()> {
        let mut backend = self.backend.lock().await;

        match &mut *backend {
            QueueBackend::File { queue, dirty, .. } => {
                queue.push(item);
                *dirty = true;
            }
            QueueBackend::Memory(queue) => {
                queue.push(item);
            }
        }

        // Flush if size threshold reached
        if backend.len() >= 100 {
            drop(backend);
            self.flush().await?;
        }

        Ok(())
    }

    /// Push an item to the front of the queue (for retries).
    pub async fn push_front(&self, item: QueuedRequest) -> Result<()> {
        let mut backend = self.backend.lock().await;

        match &mut *backend {
            QueueBackend::File { queue, dirty, .. } => {
                queue.insert(0, item);
                *dirty = true;
            }
            QueueBackend::Memory(queue) => {
                queue.insert(0, item);
            }
        }

        Ok(())
    }

    /// Pop an item from the front of the queue.
    pub async fn pop(&self) -> Result<Option<QueuedRequest>> {
        let mut backend = self.backend.lock().await;

        let item = match &mut *backend {
            QueueBackend::File { queue, dirty, .. } => {
                let item = queue.pop();
                if item.is_some() {
                    *dirty = true;
                }
                item
            }
            QueueBackend::Memory(queue) => {
                queue.pop()
            }
        };

        // Flush if queue is now empty
        if item.is_none() {
            drop(backend);
            self.flush().await?;
        }

        Ok(item)
    }

    /// Get the queue length.
    pub async fn len(&self) -> Result<usize> {
        let backend = self.backend.lock().await;
        Ok(backend.len())
    }

    /// Check if the queue is empty.
    pub async fn is_empty(&self) -> Result<bool> {
        let backend = self.backend.lock().await;
        Ok(backend.len() == 0)
    }

    /// Flush the queue to disk.
    pub async fn flush(&self) -> Result<()> {
        let mut backend = self.backend.lock().await;

        match &mut *backend {
            QueueBackend::File { path, queue, dirty } => {
                if !*dirty {
                    return Ok(());
                }

                let content = serde_json::to_string_pretty(queue)
                    .map_err(|e| agent_core::AgentError::Serialization(e))?;

                // Write to temporary file first
                let temp_path = path.with_extension("tmp");
                fs::write(&temp_path, content).await
                    .map_err(|e| agent_core::AgentError::Io(e))?;

                // Atomic rename
                fs::rename(&temp_path, path).await
                    .map_err(|e| agent_core::AgentError::Io(e))?;

                *dirty = false;

                tracing::debug!("Flushed {} items to queue", queue.len());
            }
            QueueBackend::Memory(_) => {
                // Nothing to flush for in-memory queue
            }
        }

        Ok(())
    }

    /// Clear the queue.
    pub async fn clear(&self) -> Result<()> {
        let mut backend = self.backend.lock().await;

        match &mut *backend {
            QueueBackend::File { queue, dirty, .. } => {
                queue.clear();
                *dirty = true;
            }
            QueueBackend::Memory(queue) => {
                queue.clear();
            }
        }

        Ok(())
    }
}

impl QueueBackend {
    /// Get the length of the queue.
    fn len(&self) -> usize {
        match self {
            Self::File { queue, .. } => queue.len(),
            Self::Memory(queue) => queue.len(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[tokio::test]
    async fn test_queue_push_pop() {
        let temp_dir = tempdir().unwrap();
        let queue_path = temp_dir.path().join("queue.json");

        let queue = PersistentQueue::new(&queue_path).await.unwrap();

        assert!(queue.is_empty().await.unwrap());

        let item = QueuedRequest {
            endpoint: "/api/test".to_string(),
            body: serde_json::json!({"test": true}),
            timestamp: chrono::Utc::now(),
            attempts: 0,
            max_attempts: 3,
        };

        queue.push(item.clone()).await.unwrap();
        assert_eq!(queue.len().await.unwrap(), 1);

        let popped = queue.pop().await.unwrap().unwrap();
        assert_eq!(popped.endpoint, item.endpoint);
        assert!(queue.is_empty().await.unwrap());
    }

    #[tokio::test]
    async fn test_queue_persistence() {
        let temp_dir = tempdir().unwrap();
        let queue_path = temp_dir.path().join("queue.json");

        // Create and populate queue
        {
            let queue = PersistentQueue::new(&queue_path).await.unwrap();
            queue.push(QueuedRequest {
                endpoint: "/api/test".to_string(),
                body: serde_json::json!({"test": true}),
                timestamp: chrono::Utc::now(),
                attempts: 0,
                max_attempts: 3,
            }).await.unwrap();
            queue.flush().await.unwrap();
        }

        // Reload queue
        let queue = PersistentQueue::new(&queue_path).await.unwrap();
        assert_eq!(queue.len().await.unwrap(), 1);
    }

    #[tokio::test]
    async fn test_memory_queue() {
        let queue = PersistentQueue::memory();

        let item = QueuedRequest {
            endpoint: "/api/test".to_string(),
            body: serde_json::json!({"test": true}),
            timestamp: chrono::Utc::now(),
            attempts: 0,
            max_attempts: 3,
        };

        queue.push(item).await.unwrap();
        assert_eq!(queue.len().await.unwrap(), 1);

        let popped = queue.pop().await.unwrap().unwrap();
        assert_eq!(popped.endpoint, "/api/test");
    }
}
