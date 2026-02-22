use anyhow::{Context, Result};
use reqwest::Client;
use serde::{Deserialize, Serialize};

use crate::config::SharingConfig;

/// Client for interacting with the ScreenLens sharing server.
pub struct SharingClient {
    http: Client,
    config: SharingConfig,
}

#[derive(Debug, Serialize)]
struct UploadRequest {
    screenshot_id: String,
    filename: String,
    summary: Option<String>,
    tags: Option<Vec<String>>,
}

#[derive(Debug, Deserialize)]
pub struct ShareResponse {
    /// The public share ID / short link.
    pub share_id: String,
    /// Full URL to access the shared image.
    pub url: String,
}

#[derive(Debug, Deserialize)]
pub struct SharedImage {
    pub share_id: String,
    pub filename: String,
    pub summary: Option<String>,
    pub tags: Vec<String>,
    pub created_at: String,
    /// Direct image download URL.
    pub image_url: String,
}

impl SharingClient {
    pub fn new(config: SharingConfig) -> Self {
        Self {
            http: Client::new(),
            config,
        }
    }

    /// Upload a screenshot to the sharing server.
    pub async fn upload(
        &self,
        screenshot_id: &str,
        filename: &str,
        image_bytes: Vec<u8>,
        summary: Option<String>,
        tags: Option<Vec<String>>,
    ) -> Result<ShareResponse> {
        let form = reqwest::multipart::Form::new()
            .text("screenshot_id", screenshot_id.to_string())
            .text("filename", filename.to_string())
            .text("summary", serde_json::to_string(&summary)?)
            .text("tags", serde_json::to_string(&tags)?)
            .part(
                "image",
                reqwest::multipart::Part::bytes(image_bytes)
                    .file_name(filename.to_string())
                    .mime_str("image/png")?,
            );

        let url = format!("{}/api/v1/images/upload", self.config.server_url.trim_end_matches('/'));

        let resp = self
            .http
            .post(&url)
            .header("Authorization", format!("Bearer {}", self.config.api_key))
            .multipart(form)
            .send()
            .await
            .context("uploading to sharing server")?;

        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            anyhow::bail!("sharing server returned {}: {}", status, body);
        }

        resp.json().await.context("parsing upload response")
    }

    /// Get info about a shared image.
    pub async fn get_shared(&self, share_id: &str) -> Result<SharedImage> {
        let url = format!(
            "{}/api/v1/images/{}",
            self.config.server_url.trim_end_matches('/'),
            share_id
        );

        let resp = self
            .http
            .get(&url)
            .header("Authorization", format!("Bearer {}", self.config.api_key))
            .send()
            .await
            .context("fetching shared image")?;

        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            anyhow::bail!("sharing server returned {}: {}", status, body);
        }

        resp.json().await.context("parsing shared image response")
    }

    /// Revoke sharing for an image.
    pub async fn revoke(&self, share_id: &str) -> Result<()> {
        let url = format!(
            "{}/api/v1/images/{}",
            self.config.server_url.trim_end_matches('/'),
            share_id
        );

        let resp = self
            .http
            .delete(&url)
            .header("Authorization", format!("Bearer {}", self.config.api_key))
            .send()
            .await
            .context("revoking share")?;

        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            anyhow::bail!("sharing server returned {}: {}", status, body);
        }

        Ok(())
    }
}
