//
//  YavenSQLiteDatabase.swift
//  leanring-buddy
//

import Foundation
import SQLite3

enum YavenSQLiteError: LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case executeFailed(String)
    case bindFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message): return "Could not open Yaven database: \(message)"
        case .prepareFailed(let message): return "Could not prepare database statement: \(message)"
        case .executeFailed(let message): return "Could not execute database statement: \(message)"
        case .bindFailed(let message): return "Could not bind database value: \(message)"
        }
    }
}

enum YavenSQLiteValue {
    case null
    case text(String)
    case integer(Int64)
    case real(Double)
}

final class YavenSQLiteDatabase {
    private let url: URL
    private var handle: OpaquePointer?
    private let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(handle))
            throw YavenSQLiteError.openFailed(message)
        }

        try execute("PRAGMA foreign_keys = ON")
        try execute("PRAGMA journal_mode = WAL")
    }

    deinit {
        sqlite3_close(handle)
    }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            throw YavenSQLiteError.executeFailed(lastErrorMessage)
        }
    }

    func run(_ sql: String, bindings: [YavenSQLiteValue] = []) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw YavenSQLiteError.executeFailed(lastErrorMessage)
        }
    }

    func query<T>(
        _ sql: String,
        bindings: [YavenSQLiteValue] = [],
        map: (OpaquePointer) throws -> T
    ) throws -> [T] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)

        var rows: [T] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                rows.append(try map(statement))
            } else if result == SQLITE_DONE {
                return rows
            } else {
                throw YavenSQLiteError.executeFailed(lastErrorMessage)
            }
        }
    }

    func scalarInt(_ sql: String, bindings: [YavenSQLiteValue] = []) throws -> Int {
        try query(sql, bindings: bindings) { statement in
            Int(sqlite3_column_int64(statement, 0))
        }.first ?? 0
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
              let preparedStatement = statement else {
            throw YavenSQLiteError.prepareFailed(lastErrorMessage)
        }
        return preparedStatement
    }

    private func bind(_ bindings: [YavenSQLiteValue], to statement: OpaquePointer) throws {
        for (offset, value) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .null:
                result = sqlite3_bind_null(statement, index)
            case .text(let text):
                result = sqlite3_bind_text(statement, index, text, -1, transientDestructor)
            case .integer(let integer):
                result = sqlite3_bind_int64(statement, index, integer)
            case .real(let double):
                result = sqlite3_bind_double(statement, index, double)
            }

            guard result == SQLITE_OK else {
                throw YavenSQLiteError.bindFailed(lastErrorMessage)
            }
        }
    }

    private var lastErrorMessage: String {
        String(cString: sqlite3_errmsg(handle))
    }
}

extension OpaquePointer {
    func yavenText(at index: Int32) -> String {
        guard let value = sqlite3_column_text(self, index) else { return "" }
        return String(cString: value)
    }

    func yavenOptionalText(at index: Int32) -> String? {
        guard sqlite3_column_type(self, index) != SQLITE_NULL else { return nil }
        return yavenText(at: index)
    }

    func yavenDate(at index: Int32) -> Date {
        Date(timeIntervalSince1970: sqlite3_column_double(self, index))
    }

    func yavenOptionalDate(at index: Int32) -> Date? {
        guard sqlite3_column_type(self, index) != SQLITE_NULL else { return nil }
        return yavenDate(at: index)
    }
}
