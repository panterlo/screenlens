import Foundation
import GRDB

/// Native SQLite database wrapper — replaces the Rust FFI database layer.
/// Schema is identical to `crates/core/src/db/mod.rs` so databases are portable.
class ScreenLensDatabase {
    private let dbQueue: DatabaseQueue

    init(path: String) throws {
        // Ensure the parent directory exists
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)

        dbQueue = try DatabaseQueue(path: path)
        try runMigrations()
    }

    // MARK: - Migrations (verbatim from Rust crates/core/src/db/mod.rs:28-85)

    private func runMigrations() throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS screenshots (
                    id          TEXT PRIMARY KEY,
                    filepath    TEXT NOT NULL,
                    filename    TEXT NOT NULL,
                    captured_at TEXT NOT NULL,
                    mode        TEXT NOT NULL,
                    size_bytes  INTEGER NOT NULL,
                    width       INTEGER,
                    height      INTEGER,
                    -- AI analysis fields
                    summary     TEXT,
                    tags        TEXT,
                    extracted_text TEXT,
                    application TEXT,
                    confidence  REAL,
                    analyzed_at TEXT,
                    -- Sharing
                    share_id    TEXT,
                    shared      INTEGER NOT NULL DEFAULT 0,
                    uploaded    INTEGER NOT NULL DEFAULT 0,
                    -- Metadata
                    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
                    updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
                );

                CREATE VIRTUAL TABLE IF NOT EXISTS screenshots_fts USING fts5(
                    summary,
                    tags,
                    extracted_text,
                    application,
                    content='screenshots',
                    content_rowid='rowid'
                );

                CREATE TRIGGER IF NOT EXISTS screenshots_ai AFTER INSERT ON screenshots BEGIN
                    INSERT INTO screenshots_fts(rowid, summary, tags, extracted_text, application)
                    VALUES (new.rowid, new.summary, new.tags, new.extracted_text, new.application);
                END;

                CREATE TRIGGER IF NOT EXISTS screenshots_au AFTER UPDATE ON screenshots BEGIN
                    INSERT INTO screenshots_fts(screenshots_fts, rowid, summary, tags, extracted_text, application)
                    VALUES ('delete', old.rowid, old.summary, old.tags, old.extracted_text, old.application);
                    INSERT INTO screenshots_fts(rowid, summary, tags, extracted_text, application)
                    VALUES (new.rowid, new.summary, new.tags, new.extracted_text, new.application);
                END;

                CREATE TRIGGER IF NOT EXISTS screenshots_ad AFTER DELETE ON screenshots BEGIN
                    INSERT INTO screenshots_fts(screenshots_fts, rowid, summary, tags, extracted_text, application)
                    VALUES ('delete', old.rowid, old.summary, old.tags, old.extracted_text, old.application);
                END;

                CREATE INDEX IF NOT EXISTS idx_screenshots_captured_at ON screenshots(captured_at);
                CREATE INDEX IF NOT EXISTS idx_screenshots_share_id ON screenshots(share_id);
                CREATE INDEX IF NOT EXISTS idx_screenshots_tags ON screenshots(tags);
                """)
        }
    }

    // MARK: - Insert (matches Rust insert_screenshot)

    func insertScreenshot(
        id: String,
        filepath: String,
        filename: String,
        capturedAt: String,
        mode: CaptureMode,
        sizeBytes: Int64,
        width: Int? = nil,
        height: Int? = nil
    ) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO screenshots (id, filepath, filename, captured_at, mode, size_bytes, width, height)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [id, filepath, filename, capturedAt, mode.rawValue, sizeBytes, width, height]
            )
        }
    }

    // MARK: - Update analysis (matches Rust update_analysis)

    func updateAnalysis(id: String, analysis: AnalysisResult) throws {
        let tagsJson = try JSONEncoder().encode(analysis.tags)
        let tagsString = String(data: tagsJson, encoding: .utf8)

        try dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE screenshots SET
                        summary = ?, tags = ?, extracted_text = ?,
                        application = ?, confidence = ?, analyzed_at = datetime('now'),
                        updated_at = datetime('now')
                    WHERE id = ?
                    """,
                arguments: [
                    analysis.summary,
                    tagsString,
                    analysis.extractedText,
                    analysis.application,
                    analysis.confidence,
                    id,
                ]
            )
        }
    }

    // MARK: - List recent (matches Rust list_recent)

    func listRecent(limit: Int = 50, offset: Int = 0) throws -> [Screenshot] {
        try dbQueue.read { db in
            try Screenshot.fetchAll(db, sql: """
                SELECT * FROM screenshots ORDER BY captured_at DESC LIMIT ? OFFSET ?
                """,
                arguments: [limit, offset]
            )
        }
    }

    // MARK: - FTS5 search (matches Rust search)

    func search(text: String, limit: Int = 50, offset: Int = 0) throws -> [Screenshot] {
        try dbQueue.read { db in
            try Screenshot.fetchAll(db, sql: """
                SELECT screenshots.* FROM screenshots
                JOIN screenshots_fts ON screenshots.rowid = screenshots_fts.rowid
                WHERE screenshots_fts MATCH ?
                ORDER BY rank
                LIMIT ? OFFSET ?
                """,
                arguments: [text, limit, offset]
            )
        }
    }
}
