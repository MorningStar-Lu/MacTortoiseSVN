import CSQLite
import CoreTypes
import Foundation

public struct DirtyRefreshState: Sendable, Hashable, Codable {
    public var rootPath: String
    public var requiresFullRefresh: Bool
    public var paths: [String]

    public init(rootPath: String, requiresFullRefresh: Bool, paths: [String]) {
        self.rootPath = rootPath
        self.requiresFullRefresh = requiresFullRefresh
        self.paths = paths
    }
}

public struct SQLiteStatusCacheError: Error, Sendable, LocalizedError, Equatable {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}

public actor SQLiteStatusCacheStore {
    public let databaseURL: URL

    private let connection: SQLiteConnection

    public init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let database = try Self.openDatabase(at: databaseURL)
        try Self.configureDatabase(database)
        try Self.installSchema(on: database)
        self.connection = SQLiteConnection(handle: database)
    }

    public func save(snapshot: BadgeSnapshot) throws {
        try inTransaction {
            try execute(
                """
                INSERT INTO snapshots (root_path, generated_at)
                VALUES (?, ?)
                ON CONFLICT(root_path) DO UPDATE SET generated_at = excluded.generated_at
                """,
                bindings: [
                    .text(snapshot.rootPath),
                    .double(snapshot.generatedAt.timeIntervalSince1970),
                ]
            )

            try execute(
                "DELETE FROM snapshot_entries WHERE root_path = ?",
                bindings: [.text(snapshot.rootPath)]
            )

            for (path, status) in snapshot.entries.sorted(by: { $0.key < $1.key }) {
                try execute(
                    """
                    INSERT INTO snapshot_entries (root_path, path, status)
                    VALUES (?, ?, ?)
                    """,
                    bindings: [
                        .text(snapshot.rootPath),
                        .text(path),
                        .text(status.rawValue),
                    ]
                )
            }
        }
    }

    public func loadSnapshot(for rootPath: String) throws -> BadgeSnapshot? {
        let headerRows = try query(
            "SELECT generated_at FROM snapshots WHERE root_path = ?",
            bindings: [.text(rootPath)]
        )

        guard let generatedAt = headerRows.first?.double(named: "generated_at") else {
            return nil
        }

        let entryRows = try query(
            """
            SELECT path, status
            FROM snapshot_entries
            WHERE root_path = ?
            ORDER BY path ASC
            """,
            bindings: [.text(rootPath)]
        )

        var entries: [String: VersionControlStatus] = [:]
        for row in entryRows {
            guard
                let path = row.string(named: "path"),
                let rawStatus = row.string(named: "status"),
                let status = VersionControlStatus(rawValue: rawStatus)
            else {
                continue
            }
            entries[path] = status
        }

        return BadgeSnapshot(
            rootPath: rootPath,
            generatedAt: Date(timeIntervalSince1970: generatedAt),
            entries: entries
        )
    }

    public func deleteSnapshot(for rootPath: String) throws {
        try inTransaction {
            try execute(
                "DELETE FROM snapshot_entries WHERE root_path = ?",
                bindings: [.text(rootPath)]
            )
            try execute(
                "DELETE FROM snapshots WHERE root_path = ?",
                bindings: [.text(rootPath)]
            )
        }
    }

    public func markDirty(rootPath: String, paths: [String]) throws {
        guard !paths.isEmpty else {
            try scheduleFullRefresh(rootPath: rootPath)
            return
        }

        try inTransaction {
            try execute(
                """
                INSERT INTO dirty_roots (root_path, requires_full_refresh, updated_at)
                VALUES (?, 0, ?)
                ON CONFLICT(root_path) DO UPDATE SET updated_at = excluded.updated_at
                """,
                bindings: [
                    .text(rootPath),
                    .double(Date().timeIntervalSince1970),
                ]
            )

            for path in Set(paths) {
                try execute(
                    """
                    INSERT INTO dirty_paths (root_path, path, first_seen_at)
                    VALUES (?, ?, ?)
                    ON CONFLICT(root_path, path) DO NOTHING
                    """,
                    bindings: [
                        .text(rootPath),
                        .text(path),
                        .double(Date().timeIntervalSince1970),
                    ]
                )
            }
        }
    }

    public func scheduleFullRefresh(rootPath: String) throws {
        try inTransaction {
            try execute(
                """
                INSERT INTO dirty_roots (root_path, requires_full_refresh, updated_at)
                VALUES (?, 1, ?)
                ON CONFLICT(root_path) DO UPDATE SET
                    requires_full_refresh = 1,
                    updated_at = excluded.updated_at
                """,
                bindings: [
                    .text(rootPath),
                    .double(Date().timeIntervalSince1970),
                ]
            )
            try execute(
                "DELETE FROM dirty_paths WHERE root_path = ?",
                bindings: [.text(rootPath)]
            )
        }
    }

    public func dirtyPathCount(for rootPath: String) throws -> Int {
        let rows = try query(
            "SELECT COUNT(*) AS path_count FROM dirty_paths WHERE root_path = ?",
            bindings: [.text(rootPath)]
        )
        return Int(rows.first?.int64(named: "path_count") ?? 0)
    }

    public func loadDirtyState(for rootPath: String) throws -> DirtyRefreshState? {
        let rootRows = try query(
            """
            SELECT requires_full_refresh
            FROM dirty_roots
            WHERE root_path = ?
            """,
            bindings: [.text(rootPath)]
        )

        guard let requiresFullRefresh = rootRows.first?.bool(named: "requires_full_refresh") else {
            return nil
        }

        let pathRows: [SQLiteRow]
        if requiresFullRefresh {
            pathRows = []
        } else {
            pathRows = try query(
                """
                SELECT path
                FROM dirty_paths
                WHERE root_path = ?
                ORDER BY path ASC
                """,
                bindings: [.text(rootPath)]
            )
        }

        return DirtyRefreshState(
            rootPath: rootPath,
            requiresFullRefresh: requiresFullRefresh,
            paths: pathRows.compactMap { $0.string(named: "path") }
        )
    }

    public func loadDirtyRoots() throws -> [DirtyRefreshState] {
        let rootRows = try query(
            """
            SELECT root_path
            FROM dirty_roots
            ORDER BY root_path ASC
            """
        )

        return try rootRows.compactMap { row in
            guard let rootPath = row.string(named: "root_path") else {
                return nil
            }
            return try loadDirtyState(for: rootPath)
        }
    }

    public func clearDirtyState(for rootPath: String) throws {
        try inTransaction {
            try execute(
                "DELETE FROM dirty_paths WHERE root_path = ?",
                bindings: [.text(rootPath)]
            )
            try execute(
                "DELETE FROM dirty_roots WHERE root_path = ?",
                bindings: [.text(rootPath)]
            )
        }
    }

    private static func openDatabase(at databaseURL: URL) throws -> OpaquePointer? {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let result = databaseURL.path.withCString { path in
            sqlite3_open_v2(path, &database, flags, nil)
        }
        guard result == SQLITE_OK else {
            throw SQLiteStatusCacheError(
                "Failed to open SQLite database at \(databaseURL.path): \(lastErrorMessage(from: database))"
            )
        }
        return database
    }

    private static func configureDatabase(_ database: OpaquePointer?) throws {
        try execute("PRAGMA foreign_keys = ON", on: database)
        try execute("PRAGMA journal_mode = WAL", on: database)
        try execute("PRAGMA synchronous = NORMAL", on: database)
    }

    private static func installSchema(on database: OpaquePointer?) throws {
        try executeScript(schemaSQL, on: database)
    }

    private func execute(_ sql: String, bindings: [SQLiteBinding] = []) throws {
        try Self.execute(sql, bindings: bindings, on: connection.handle)
    }

    private func query(_ sql: String, bindings: [SQLiteBinding] = []) throws -> [SQLiteRow] {
        guard let database = connection.handle else {
            throw SQLiteStatusCacheError("SQLite database is not open.")
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteStatusCacheError(
                "Failed to prepare query: \(sql). \(Self.lastErrorMessage(from: database))"
            )
        }
        defer { sqlite3_finalize(statement) }

        try Self.bind(bindings, to: statement, database: database)

        var rows: [SQLiteRow] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                break
            }
            guard result == SQLITE_ROW else {
                throw SQLiteStatusCacheError(
                    "Failed to query SQL: \(sql). \(Self.lastErrorMessage(from: database))"
                )
            }
            rows.append(SQLiteRow(statement: statement))
        }

        return rows
    }

    private static func execute(
        _ sql: String,
        bindings: [SQLiteBinding] = [],
        on database: OpaquePointer?
    ) throws {
        guard let database else {
            throw SQLiteStatusCacheError("SQLite database is not open.")
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteStatusCacheError(
                "Failed to prepare SQL: \(sql). \(lastErrorMessage(from: database))"
            )
        }
        defer { sqlite3_finalize(statement) }

        try bind(bindings, to: statement, database: database)

        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                break
            }
            guard result == SQLITE_ROW else {
                throw SQLiteStatusCacheError(
                    "Failed to execute SQL: \(sql). \(lastErrorMessage(from: database))"
                )
            }
        }
    }

    private static func executeScript(_ sql: String, on database: OpaquePointer?) throws {
        guard let database else {
            throw SQLiteStatusCacheError("SQLite database is not open.")
        }

        var errorPointer: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorPointer)
        if let errorPointer {
            sqlite3_free(errorPointer)
        }
        guard result == SQLITE_OK else {
            throw SQLiteStatusCacheError(
                "Failed to execute SQLite script. \(lastErrorMessage(from: database))"
            )
        }
    }

    private static func bind(
        _ bindings: [SQLiteBinding],
        to statement: OpaquePointer?,
        database: OpaquePointer?
    ) throws {
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32

            switch binding {
            case let .text(value):
                result = value.withCString { pointer in
                    sqlite3_bind_text(statement, index, pointer, -1, sqliteTransient)
                }
            case let .double(value):
                result = sqlite3_bind_double(statement, index, value)
            case let .int64(value):
                result = sqlite3_bind_int64(statement, index, value)
            case let .bool(value):
                result = sqlite3_bind_int(statement, index, value ? 1 : 0)
            case .null:
                result = sqlite3_bind_null(statement, index)
            }

            guard result == SQLITE_OK else {
                throw SQLiteStatusCacheError(
                    "Failed to bind SQLite parameter #\(index): \(lastErrorMessage(from: database))"
                )
            }
        }
    }

    private func inTransaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private static func lastErrorMessage(from database: OpaquePointer?) -> String {
        guard let database else {
            return "Unknown SQLite error."
        }
        guard let message = sqlite3_errmsg(database) else {
            return "Unknown SQLite error."
        }
        return String(cString: message)
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private final class SQLiteConnection: @unchecked Sendable {
    let handle: OpaquePointer?

    init(handle: OpaquePointer?) {
        self.handle = handle
    }

    deinit {
        if let handle {
            sqlite3_close(handle)
        }
    }
}

private enum SQLiteBinding {
    case text(String)
    case double(Double)
    case int64(Int64)
    case bool(Bool)
    case null
}

private struct SQLiteRow {
    private let values: [String: SQLiteValue]

    init(statement: OpaquePointer?) {
        var values: [String: SQLiteValue] = [:]
        let columnCount = sqlite3_column_count(statement)
        for index in 0..<columnCount {
            guard let namePointer = sqlite3_column_name(statement, index) else {
                continue
            }
            let name = String(cString: namePointer)
            values[name] = SQLiteValue(statement: statement, index: index)
        }
        self.values = values
    }

    func string(named name: String) -> String? {
        values[name]?.stringValue
    }

    func double(named name: String) -> Double? {
        values[name]?.doubleValue
    }

    func int64(named name: String) -> Int64? {
        values[name]?.int64Value
    }

    func bool(named name: String) -> Bool? {
        values[name]?.boolValue
    }
}

private enum SQLiteValue {
    case null
    case integer(Int64)
    case double(Double)
    case text(String)

    init(statement: OpaquePointer?, index: Int32) {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            self = .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            self = .double(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            if let pointer = sqlite3_column_text(statement, index) {
                self = .text(String(cString: pointer))
            } else {
                self = .null
            }
        default:
            self = .null
        }
    }

    var stringValue: String? {
        switch self {
        case let .text(value):
            return value
        default:
            return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case let .double(value):
            return value
        case let .integer(value):
            return Double(value)
        default:
            return nil
        }
    }

    var int64Value: Int64? {
        switch self {
        case let .integer(value):
            return value
        default:
            return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case let .integer(value):
            return value != 0
        default:
            return nil
        }
    }
}

private let schemaSQL = """
CREATE TABLE IF NOT EXISTS snapshots (
    root_path TEXT PRIMARY KEY,
    generated_at REAL NOT NULL
);

CREATE TABLE IF NOT EXISTS snapshot_entries (
    root_path TEXT NOT NULL,
    path TEXT NOT NULL,
    status TEXT NOT NULL,
    PRIMARY KEY (root_path, path),
    FOREIGN KEY (root_path) REFERENCES snapshots(root_path) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_snapshot_entries_root_path
ON snapshot_entries(root_path);

CREATE TABLE IF NOT EXISTS dirty_roots (
    root_path TEXT PRIMARY KEY,
    requires_full_refresh INTEGER NOT NULL DEFAULT 0,
    updated_at REAL NOT NULL
);

CREATE TABLE IF NOT EXISTS dirty_paths (
    root_path TEXT NOT NULL,
    path TEXT NOT NULL,
    first_seen_at REAL NOT NULL,
    PRIMARY KEY (root_path, path),
    FOREIGN KEY (root_path) REFERENCES dirty_roots(root_path) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_dirty_paths_root_path
ON dirty_paths(root_path);
"""
