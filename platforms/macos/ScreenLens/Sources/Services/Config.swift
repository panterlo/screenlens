import Foundation
import TOMLKit

/// App configuration — mirrors the Rust `Config` struct.
/// Loaded from `~/Library/Application Support/com.screenlens.ScreenLens/config.toml`.
struct AppConfig {
    var capture: CaptureConfig
    var ai: AIConfig
    var database: DatabaseConfig
    var sharing: SharingConfig

    struct CaptureConfig {
        var saveDir: String
        var format: String
        var jpegQuality: Int
    }

    struct AIConfig {
        var apiUrl: String
        var apiKey: String
        var model: String
        var autoAnalyze: Bool
    }

    struct DatabaseConfig {
        var path: String
    }

    struct SharingConfig {
        var serverUrl: String
        var apiKey: String
        var autoUpload: Bool
    }

    /// The application support directory for ScreenLens.
    static func dataDir() -> String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.path
        return (appSupport as NSString).appendingPathComponent("com.screenlens.ScreenLens")
    }

    /// Resolve a path relative to the data directory (absolute paths pass through).
    private static func resolvePath(_ raw: String, relativeTo base: String) -> String {
        if (raw as NSString).isAbsolutePath {
            return raw
        }
        return (base as NSString).appendingPathComponent(raw)
    }

    /// Absolute path to the screenshots directory.
    var screenshotsDir: String {
        Self.resolvePath(capture.saveDir, relativeTo: Self.dataDir())
    }

    /// Absolute path to the database file.
    var databasePath: String {
        Self.resolvePath(database.path, relativeTo: Self.dataDir())
    }

    /// Load configuration from the standard config.toml location.
    static func load() throws -> AppConfig {
        let dataDir = Self.dataDir()
        let configPath = (dataDir as NSString).appendingPathComponent("config.toml")

        guard FileManager.default.fileExists(atPath: configPath) else {
            throw ConfigError.notFound(configPath)
        }

        let contents = try String(contentsOfFile: configPath, encoding: .utf8)
        let table = try TOMLTable(string: contents)

        // Capture
        let captureTable = table["capture"] as? TOMLTable
        let captureConfig = CaptureConfig(
            saveDir: (captureTable?["save_dir"] as? String) ?? "screenshots",
            format: (captureTable?["format"] as? String) ?? "png",
            jpegQuality: (captureTable?["jpeg_quality"] as? Int) ?? 90
        )

        // AI
        let aiTable = table["ai"] as? TOMLTable
        let aiConfig = AIConfig(
            apiUrl: (aiTable?["api_url"] as? String) ?? "",
            apiKey: (aiTable?["api_key"] as? String) ?? "",
            model: (aiTable?["model"] as? String) ?? "",
            autoAnalyze: (aiTable?["auto_analyze"] as? Bool) ?? true
        )

        // Database
        let dbTable = table["database"] as? TOMLTable
        let dbConfig = DatabaseConfig(
            path: (dbTable?["path"] as? String) ?? "screenlens.db"
        )

        // Sharing
        let sharingTable = table["sharing"] as? TOMLTable
        let sharingConfig = SharingConfig(
            serverUrl: (sharingTable?["server_url"] as? String) ?? "",
            apiKey: (sharingTable?["api_key"] as? String) ?? "",
            autoUpload: (sharingTable?["auto_upload"] as? Bool) ?? false
        )

        return AppConfig(
            capture: captureConfig,
            ai: aiConfig,
            database: dbConfig,
            sharing: sharingConfig
        )
    }
}

enum ConfigError: LocalizedError {
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let path):
            return "Config file not found at \(path). Copy config.example.toml and fill in your settings."
        }
    }
}
