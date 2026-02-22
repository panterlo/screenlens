import Foundation

/// Saves screenshot images to disk and inserts database records.
/// Matches the Rust `sl_screenshot_save` FFI function behavior.
class ScreenshotStore {
    private let database: ScreenLensDatabase
    private let saveDir: String

    init(database: ScreenLensDatabase, saveDir: String) {
        self.database = database
        self.saveDir = saveDir
    }

    /// Save PNG image data to disk and insert a DB row.
    /// Filename format: `YYYYMMDD_HHmmss_<uuid8>.png` (matching Rust pattern).
    func save(imageData: Data, mode: CaptureMode) throws -> SaveResult {
        // Ensure save directory exists
        try FileManager.default.createDirectory(
            atPath: saveDir, withIntermediateDirectories: true)

        // Generate filename matching Rust's format
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let timestamp = formatter.string(from: now)

        let uuid = UUID().uuidString.lowercased()
        let uuidPrefix = String(uuid.prefix(8))
        let filename = "\(timestamp)_\(uuidPrefix).png"

        let filepath = (saveDir as NSString).appendingPathComponent(filename)

        // Write PNG to disk
        try imageData.write(to: URL(fileURLWithPath: filepath))

        // ISO 8601 timestamp for DB (matching Rust chrono to_rfc3339)
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let capturedAt = isoFormatter.string(from: now)

        // Insert DB record
        let id = UUID().uuidString.lowercased()
        try database.insertScreenshot(
            id: id,
            filepath: filepath,
            filename: filename,
            capturedAt: capturedAt,
            mode: mode,
            sizeBytes: Int64(imageData.count)
        )

        return SaveResult(
            id: id,
            filepath: filepath,
            filename: filename,
            sizeBytes: imageData.count,
            mode: mode,
            capturedAt: capturedAt
        )
    }
}
