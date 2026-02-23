import Foundation
import TOMLKit

/// App configuration — mirrors the Rust `Config` struct.
/// Loaded from `~/Library/Application Support/com.screenlens.ScreenLens/config.toml`.
struct AppConfig {
    var capture: CaptureConfig
    var ai: AIConfig
    var database: DatabaseConfig
    var sharing: SharingConfig
    var hotkeys: HotkeyConfig

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

    struct HotkeyConfig {
        var captureFullscreen: String
        var captureRegion: String
        var captureWindow: String
        var openGallery: String

        static let defaults = HotkeyConfig(
            captureFullscreen: "Ctrl+Shift+F",
            captureRegion: "Ctrl+Shift+R",
            captureWindow: "Ctrl+Shift+W",
            openGallery: "Ctrl+Shift+G"
        )
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

        // Hotkeys
        let hotkeyTable = table["hotkeys"] as? TOMLTable
        let hotkeyConfig = HotkeyConfig(
            captureFullscreen: (hotkeyTable?["capture_fullscreen"] as? String) ?? HotkeyConfig.defaults.captureFullscreen,
            captureRegion: (hotkeyTable?["capture_region"] as? String) ?? HotkeyConfig.defaults.captureRegion,
            captureWindow: (hotkeyTable?["capture_window"] as? String) ?? HotkeyConfig.defaults.captureWindow,
            openGallery: (hotkeyTable?["open_gallery"] as? String) ?? HotkeyConfig.defaults.openGallery
        )

        return AppConfig(
            capture: captureConfig,
            ai: aiConfig,
            database: dbConfig,
            sharing: sharingConfig,
            hotkeys: hotkeyConfig
        )
    }

    /// Path to the config.toml file.
    static func configPath() -> String {
        (dataDir() as NSString).appendingPathComponent("config.toml")
    }

    /// Save current configuration back to config.toml.
    /// Re-parses the existing file to preserve comments/ordering for sections we don't modify,
    /// then updates the values we manage.
    func save() throws {
        let path = Self.configPath()
        let table: TOMLTable
        if FileManager.default.fileExists(atPath: path),
           let contents = try? String(contentsOfFile: path, encoding: .utf8),
           let existing = try? TOMLTable(string: contents) {
            table = existing
        } else {
            table = TOMLTable()
        }

        // Capture
        let captureT = (table["capture"] as? TOMLTable) ?? TOMLTable()
        captureT["save_dir"] = capture.saveDir
        captureT["format"] = capture.format
        captureT["jpeg_quality"] = capture.jpegQuality
        table["capture"] = captureT

        // AI
        let aiT = (table["ai"] as? TOMLTable) ?? TOMLTable()
        aiT["api_url"] = ai.apiUrl
        aiT["api_key"] = ai.apiKey
        aiT["model"] = ai.model
        aiT["auto_analyze"] = ai.autoAnalyze
        table["ai"] = aiT

        // Database
        let dbT = (table["database"] as? TOMLTable) ?? TOMLTable()
        dbT["path"] = database.path
        table["database"] = dbT

        // Sharing
        let sharingT = (table["sharing"] as? TOMLTable) ?? TOMLTable()
        sharingT["server_url"] = sharing.serverUrl
        sharingT["api_key"] = sharing.apiKey
        sharingT["auto_upload"] = sharing.autoUpload
        table["sharing"] = sharingT

        // Hotkeys
        let hotkeyT = (table["hotkeys"] as? TOMLTable) ?? TOMLTable()
        hotkeyT["capture_fullscreen"] = hotkeys.captureFullscreen
        hotkeyT["capture_region"] = hotkeys.captureRegion
        hotkeyT["capture_window"] = hotkeys.captureWindow
        hotkeyT["open_gallery"] = hotkeys.openGallery
        table["hotkeys"] = hotkeyT

        let tomlString = table.convert()
        try tomlString.write(toFile: path, atomically: true, encoding: .utf8)
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
