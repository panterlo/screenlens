import Foundation
import GRDB

/// Matches the Rust `CaptureMode` enum — values use Rust's `Debug` format.
enum CaptureMode: String, Codable, DatabaseValueConvertible {
    case fullscreen = "Fullscreen"
    case window = "Window"
    case region = "Region"
}

/// Database record matching the Rust `screenshots` table schema.
struct Screenshot: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "screenshots"

    var id: String
    var filepath: String
    var filename: String
    var capturedAt: String
    var mode: CaptureMode
    var sizeBytes: Int64
    var width: Int?
    var height: Int?
    // AI analysis
    var summary: String?
    var tags: String?           // JSON array string
    var extractedText: String?
    var application: String?
    var confidence: Double?
    var analyzedAt: String?
    // Sharing
    var shareId: String?
    var shared: Int
    var uploaded: Int
    // Metadata
    var createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey, ColumnExpression {
        case id, filepath, filename
        case capturedAt = "captured_at"
        case mode
        case sizeBytes = "size_bytes"
        case width, height
        case summary, tags
        case extractedText = "extracted_text"
        case application, confidence
        case analyzedAt = "analyzed_at"
        case shareId = "share_id"
        case shared, uploaded
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Decoded tags array from the JSON string.
    var tagList: [String] {
        guard let tags = tags,
              let data = tags.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return array
    }
}

/// Result of AI analysis — matches the Rust `AnalysisResult` struct.
struct AnalysisResult: Codable {
    var summary: String
    var tags: [String]
    var extractedText: String?
    var application: String?
    var confidence: Double

    enum CodingKeys: String, CodingKey {
        case summary, tags
        case extractedText = "extracted_text"
        case application, confidence
    }
}

/// Result returned from saving a screenshot to disk + DB.
struct SaveResult {
    var id: String
    var filepath: String
    var filename: String
    var sizeBytes: Int
    var mode: CaptureMode
    var capturedAt: String
}
