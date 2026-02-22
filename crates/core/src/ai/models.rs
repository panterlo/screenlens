use serde::{Deserialize, Serialize};

/// Result of AI analysis on a screenshot.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnalysisResult {
    /// One-line summary of what the screenshot shows.
    pub summary: String,
    /// Category tags (e.g. "error", "code", "ui-mockup", "terminal", "documentation").
    pub tags: Vec<String>,
    /// Extracted text content (OCR-like extraction by the vision model).
    pub extracted_text: Option<String>,
    /// Detected application or context.
    pub application: Option<String>,
    /// Confidence score 0.0 - 1.0.
    pub confidence: f32,
}

/// OpenAI-compatible chat completion request.
#[derive(Debug, Serialize)]
pub(crate) struct ChatCompletionRequest {
    pub model: String,
    pub messages: Vec<ChatMessage>,
    pub max_tokens: u32,
    pub temperature: f32,
}

#[derive(Debug, Serialize)]
pub(crate) struct ChatMessage {
    pub role: String,
    pub content: Vec<ContentPart>,
}

#[derive(Debug, Serialize)]
#[serde(tag = "type")]
pub(crate) enum ContentPart {
    #[serde(rename = "text")]
    Text { text: String },
    #[serde(rename = "image_url")]
    ImageUrl { image_url: ImageUrl },
}

#[derive(Debug, Serialize)]
pub(crate) struct ImageUrl {
    pub url: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub detail: Option<String>,
}

/// OpenAI-compatible chat completion response.
#[derive(Debug, Deserialize)]
pub(crate) struct ChatCompletionResponse {
    pub choices: Vec<Choice>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct Choice {
    pub message: ResponseMessage,
}

#[derive(Debug, Deserialize)]
pub(crate) struct ResponseMessage {
    pub content: String,
}
