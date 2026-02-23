import Foundation
import GRDB

struct DateGroupRow {
    let year: Int, month: Int, day: Int, count: Int
}

struct AppGroupRow {
    let name: String, count: Int
}

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

            // Add window metadata columns (safe to run repeatedly — IF NOT EXISTS via catch)
            for col in ["window_title TEXT", "bundle_id TEXT", "source_url TEXT", "annotations TEXT"] {
                do {
                    try db.execute(sql: "ALTER TABLE screenshots ADD COLUMN \(col)")
                } catch {
                    // Column already exists — ignore
                }
            }
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
        height: Int? = nil,
        application: String? = nil,
        windowTitle: String? = nil,
        bundleId: String? = nil,
        sourceUrl: String? = nil
    ) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO screenshots (id, filepath, filename, captured_at, mode, size_bytes, width, height, application, window_title, bundle_id, source_url)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [id, filepath, filename, capturedAt, mode.rawValue, sizeBytes, width, height, application, windowTitle, bundleId, sourceUrl]
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

    // MARK: - Update annotations

    func updateAnnotations(id: String, annotations: [Annotation]) throws {
        let json = try JSONEncoder().encode(annotations)
        let jsonString = String(data: json, encoding: .utf8)
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE screenshots SET annotations = ?, updated_at = datetime('now') WHERE id = ?",
                arguments: [jsonString, id]
            )
        }
    }

    // MARK: - Sidebar aggregation queries

    func fetchDateGroups() throws -> [DateGroupRow] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT CAST(strftime('%Y', captured_at) AS INTEGER),
                       CAST(strftime('%m', captured_at) AS INTEGER),
                       CAST(strftime('%d', captured_at) AS INTEGER),
                       COUNT(*)
                FROM screenshots
                GROUP BY 1, 2, 3
                ORDER BY 1 DESC, 2 DESC, 3 DESC
                """)
            return rows.map { row in
                DateGroupRow(
                    year: row[0] as Int,
                    month: row[1] as Int,
                    day: row[2] as Int,
                    count: row[3] as Int
                )
            }
        }
    }

    func fetchAppGroups() throws -> [AppGroupRow] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT COALESCE(application, 'Unknown'), COUNT(*)
                FROM screenshots
                GROUP BY 1
                ORDER BY 2 DESC
                """)
            return rows.map { row in
                AppGroupRow(name: row[0] as String, count: row[1] as Int)
            }
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

    // MARK: - Filtered search (text + mode/date/app filters)

    func searchFiltered(text: String, filters: GalleryFilters, sidebarFilter: SidebarFilter = SidebarFilter(), limit: Int = 50, offset: Int = 0) throws -> [Screenshot] {
        var conditions: [String] = []
        var args: [DatabaseValueConvertible?] = []

        // FTS5 text match
        let useFTS = !text.isEmpty
        var baseQuery: String
        if useFTS {
            baseQuery = "SELECT screenshots.* FROM screenshots JOIN screenshots_fts ON screenshots.rowid = screenshots_fts.rowid"
            conditions.append("screenshots_fts MATCH ?")
            args.append(text)
        } else {
            baseQuery = "SELECT * FROM screenshots"
        }

        // Mode filter
        if let mode = filters.mode {
            conditions.append("mode = ?")
            args.append(mode.rawValue)
        }

        // Date filter (from filter bar)
        if let dateRange = filters.dateRange {
            conditions.append("captured_at >= ?")
            args.append(dateRange.startDate)
        }

        // App name filter (from filter bar — LIKE match)
        if let app = filters.appName, !app.isEmpty {
            conditions.append("application LIKE ?")
            args.append("%\(app)%")
        }

        // Sidebar date range filter (AND with filter bar)
        if let dateStart = sidebarFilter.dateStart {
            conditions.append("captured_at >= ?")
            args.append(dateStart)
        }
        if let dateEnd = sidebarFilter.dateEnd {
            conditions.append("captured_at < ?")
            args.append(dateEnd)
        }

        // Sidebar app exact match filter
        if let app = sidebarFilter.application {
            conditions.append("application = ?")
            args.append(app)
        }

        var sql = baseQuery
        if !conditions.isEmpty {
            sql += " WHERE " + conditions.joined(separator: " AND ")
        }
        sql += useFTS ? " ORDER BY rank" : " ORDER BY captured_at DESC"
        sql += " LIMIT ? OFFSET ?"
        args.append(limit)
        args.append(offset)

        return try dbQueue.read { db in
            try Screenshot.fetchAll(db, sql: sql, arguments: StatementArguments(args.map { $0 ?? DatabaseValue.null })!)
        }
    }
}
