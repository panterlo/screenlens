import Foundation
import GRDB

/// Matches the Rust `CaptureMode` enum — values use Rust's `Debug` format.
enum CaptureMode: String, Codable, DatabaseValueConvertible {
    case fullscreen = "Fullscreen"
    case window = "Window"
    case region = "Region"

    var displayName: String { rawValue }
    var sfSymbol: String {
        switch self {
        case .fullscreen: return "rectangle.dashed"
        case .window: return "macwindow"
        case .region: return "crop"
        }
    }
}

// MARK: - Annotation Models

enum AnnotationType: String, Codable {
    case arrow, rectangle, text
}

enum RectangleFill: String, Codable {
    case outline, solid, highlight
}

struct AnnotationStyle: Codable, Equatable {
    var color: String            // hex e.g. "#FF0000"
    var lineWidth: CGFloat
    var opacity: CGFloat
    var fill: RectangleFill?     // rectangles only
    var fontSize: CGFloat?       // text only
}

struct AnnotationGeometry: Codable, Equatable {
    var startX: CGFloat?
    var startY: CGFloat?
    var endX: CGFloat?
    var endY: CGFloat?
    var x: CGFloat?
    var y: CGFloat?
    var width: CGFloat?
    var height: CGFloat?

    var rect: NSRect? {
        if let x = x, let y = y, let w = width, let h = height {
            return NSRect(x: x, y: y, width: w, height: h)
        }
        return nil
    }

    var line: (start: NSPoint, end: NSPoint)? {
        if let sx = startX, let sy = startY, let ex = endX, let ey = endY {
            return (NSPoint(x: sx, y: sy), NSPoint(x: ex, y: ey))
        }
        return nil
    }
}

struct Annotation: Codable, Identifiable, Equatable {
    var id: String
    var type: AnnotationType
    var geometry: AnnotationGeometry
    var style: AnnotationStyle
    var text: String?

    init(id: String = UUID().uuidString, type: AnnotationType, geometry: AnnotationGeometry, style: AnnotationStyle, text: String? = nil) {
        self.id = id
        self.type = type
        self.geometry = geometry
        self.style = style
        self.text = text
    }
}

// MARK: - Gallery Filters

enum DateRange: String, CaseIterable {
    case today = "Today"
    case lastWeek = "Last 7 Days"
    case lastMonth = "Last 30 Days"

    var startDate: String {
        let cal = Calendar.current
        let now = Date()
        let date: Date
        switch self {
        case .today: date = cal.startOfDay(for: now)
        case .lastWeek: date = cal.date(byAdding: .day, value: -7, to: now)!
        case .lastMonth: date = cal.date(byAdding: .day, value: -30, to: now)!
        }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return fmt.string(from: date)
    }
}

struct GalleryFilters {
    var mode: CaptureMode?
    var dateRange: DateRange?
    var appName: String?

    var isEmpty: Bool {
        mode == nil && dateRange == nil && (appName ?? "").isEmpty
    }
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
    // Window metadata
    var windowTitle: String?
    var bundleId: String?
    var sourceUrl: String?
    // Annotations (JSON array)
    var annotations: String?
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
        case windowTitle = "window_title"
        case bundleId = "bundle_id"
        case sourceUrl = "source_url"
        case annotations
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

    /// Decoded annotations array from the JSON string.
    var annotationList: [Annotation] {
        get {
            guard let annotations = annotations,
                  let data = annotations.data(using: .utf8),
                  let array = try? JSONDecoder().decode([Annotation].self, from: data)
            else { return [] }
            return array
        }
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

/// Metadata captured from the source window (window capture mode only).
struct WindowInfo {
    var appName: String?
    var bundleId: String?
    var windowTitle: String?
    var sourceUrl: String?
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
