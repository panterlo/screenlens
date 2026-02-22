import Foundation

/// Native AI client — replaces the Rust `AiClient`.
/// Posts to an OpenAI-compatible multimodal endpoint using Foundation URLSession.
class AIClient {
    private let apiUrl: String
    private let apiKey: String
    private let model: String

    // System prompt copied verbatim from crates/core/src/ai/client.rs
    private static let systemPrompt = """
        You are a screenshot analysis assistant. Analyze the provided screenshot and respond with a JSON object containing:
        - "summary": a concise one-line description of what the screenshot shows
        - "tags": an array of category tags (e.g. "error", "code", "terminal", "browser", "ui-design", "documentation", "chat", "spreadsheet", "email")
        - "extracted_text": key text content visible in the screenshot (keep it concise, focus on important text)
        - "application": the application or context shown (e.g. "VS Code", "Chrome", "Terminal", "Figma")
        - "confidence": your confidence in the analysis from 0.0 to 1.0

        Respond with ONLY the JSON object, no markdown fencing or extra text.
        """

    init(apiUrl: String, apiKey: String, model: String) {
        self.apiUrl = apiUrl
        self.apiKey = apiKey
        self.model = model
    }

    /// Analyze a screenshot image, returning structured metadata.
    func analyze(imageData: Data) async throws -> AnalysisResult {
        let base64Image = imageData.base64EncodedString()
        let dataUrl = "data:image/png;base64,\(base64Image)"

        let url = URL(string: "\(apiUrl.hasSuffix("/") ? String(apiUrl.dropLast()) : apiUrl)/chat/completions")!

        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "system",
                    "content": [
                        ["type": "text", "text": Self.systemPrompt]
                    ]
                ],
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": "Analyze this screenshot:"],
                        ["type": "image_url", "image_url": ["url": dataUrl, "detail": "high"]]
                    ]
                ]
            ],
            "max_tokens": 1024,
            "temperature": 0.1,
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIClientError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIClientError.apiError(statusCode: httpResponse.statusCode, body: body)
        }

        // Parse OpenAI-compatible response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw AIClientError.parseError("Failed to extract content from API response")
        }

        let contentData = Data(content.utf8)
        let result = try JSONDecoder().decode(AnalysisResult.self, from: contentData)
        return result
    }
}

enum AIClientError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int, body: String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from AI API"
        case .apiError(let code, let body):
            return "AI API returned \(code): \(body)"
        case .parseError(let msg):
            return msg
        }
    }
}
