use anyhow::{Context, Result};
use base64::Engine;
use reqwest::Client;

use super::models::*;
use crate::config::AiConfig;

const SYSTEM_PROMPT: &str = r#"You are a screenshot analysis assistant. Analyze the provided screenshot and respond with a JSON object containing:
- "summary": a concise one-line description of what the screenshot shows
- "tags": an array of category tags (e.g. "error", "code", "terminal", "browser", "ui-design", "documentation", "chat", "spreadsheet", "email")
- "extracted_text": key text content visible in the screenshot (keep it concise, focus on important text)
- "application": the application or context shown (e.g. "VS Code", "Chrome", "Terminal", "Figma")
- "confidence": your confidence in the analysis from 0.0 to 1.0

Respond with ONLY the JSON object, no markdown fencing or extra text."#;

pub struct AiClient {
    http: Client,
    config: AiConfig,
}

impl AiClient {
    pub fn new(config: AiConfig) -> Self {
        Self {
            http: Client::new(),
            config,
        }
    }

    /// Analyze a screenshot image, returning structured metadata.
    pub async fn analyze_screenshot(&self, image_bytes: &[u8]) -> Result<AnalysisResult> {
        let base64_image = base64::engine::general_purpose::STANDARD.encode(image_bytes);
        let data_url = format!("data:image/png;base64,{}", base64_image);

        let request = ChatCompletionRequest {
            model: self.config.model.clone(),
            messages: vec![
                ChatMessage {
                    role: "system".into(),
                    content: vec![ContentPart::Text { text: SYSTEM_PROMPT.into() }],
                },
                ChatMessage {
                    role: "user".into(),
                    content: vec![
                        ContentPart::Text {
                            text: "Analyze this screenshot:".into(),
                        },
                        ContentPart::ImageUrl {
                            image_url: ImageUrl {
                                url: data_url,
                                detail: Some("high".into()),
                            },
                        },
                    ],
                },
            ],
            max_tokens: 1024,
            temperature: 0.1,
        };

        let url = format!("{}/chat/completions", self.config.api_url.trim_end_matches('/'));

        let response = self
            .http
            .post(&url)
            .header("Authorization", format!("Bearer {}", self.config.api_key))
            .json(&request)
            .send()
            .await
            .context("sending request to AI API")?;

        let status = response.status();
        if !status.is_success() {
            let body = response.text().await.unwrap_or_default();
            anyhow::bail!("AI API returned {}: {}", status, body);
        }

        let completion: ChatCompletionResponse = response
            .json()
            .await
            .context("parsing AI API response")?;

        let content = &completion
            .choices
            .first()
            .context("no choices in AI response")?
            .message
            .content;

        // Parse the JSON response from the model
        let result: AnalysisResult =
            serde_json::from_str(content).context("parsing analysis JSON from model response")?;

        Ok(result)
    }
}
