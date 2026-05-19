//
//  YavenThreadStore.swift
//  leanring-buddy
//

import Foundation
import SQLite3

final class YavenThreadStore {
    static let shared = try! YavenThreadStore()

    private let database: YavenSQLiteDatabase
    private let encoder = JSONEncoder()

    init(databaseURL: URL = YavenStorage.databaseURL) throws {
        database = try YavenSQLiteDatabase(url: databaseURL)
        encoder.dateEncodingStrategy = .iso8601
        try migrate()
    }

    func createThread(
        kind: YavenThreadKind,
        title: String,
        status: YavenThreadStatus = .running,
        source: String? = nil,
        now: Date = Date()
    ) throws -> YavenThreadSummary {
        let thread = YavenThreadSummary(
            id: UUID(),
            kind: kind,
            status: status,
            title: title,
            source: source,
            createdAt: now,
            updatedAt: now,
            lastPreview: "",
            requiresAttention: status == .approvalRequired
        )
        try upsertThread(thread)
        return thread
    }

    func upsertThread(_ thread: YavenThreadSummary) throws {
        try database.run(
            """
            INSERT INTO threads (
                id, kind, status, title, source, created_at, updated_at,
                last_preview, requires_attention
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                kind = excluded.kind,
                status = excluded.status,
                title = excluded.title,
                source = excluded.source,
                updated_at = excluded.updated_at,
                last_preview = excluded.last_preview,
                requires_attention = excluded.requires_attention
            """,
            bindings: [
                .text(thread.id.uuidString),
                .text(thread.kind.rawValue),
                .text(thread.status.rawValue),
                .text(thread.title),
                optionalText(thread.source),
                .real(thread.createdAt.timeIntervalSince1970),
                .real(thread.updatedAt.timeIntervalSince1970),
                .text(thread.lastPreview),
                .integer(thread.requiresAttention ? 1 : 0)
            ]
        )
    }

    func updateThread(
        id: UUID,
        status: YavenThreadStatus? = nil,
        title: String? = nil,
        lastPreview: String? = nil,
        requiresAttention: Bool? = nil,
        now: Date = Date()
    ) throws {
        guard var thread = try thread(id: id) else { return }
        if let status {
            thread.status = status
        }
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            thread.title = title
        }
        if let lastPreview {
            thread.lastPreview = lastPreview
        }
        if let requiresAttention {
            thread.requiresAttention = requiresAttention
        } else if let status {
            thread.requiresAttention = status == .approvalRequired
        }
        thread.updatedAt = now
        try upsertThread(thread)
    }

    func thread(id: UUID) throws -> YavenThreadSummary? {
        try database.query(
            """
            SELECT id, kind, status, title, source, created_at, updated_at,
                   last_preview, requires_attention
            FROM threads WHERE id = ?
            """,
            bindings: [.text(id.uuidString)],
            map: mapThread
        ).first
    }

    func recentThreads(limit: Int = 30) throws -> [YavenThreadSummary] {
        try database.query(
            """
            SELECT id, kind, status, title, source, created_at, updated_at,
                   last_preview, requires_attention
            FROM threads
            ORDER BY updated_at DESC
            LIMIT ?
            """,
            bindings: [.integer(Int64(limit))],
            map: mapThread
        )
    }

    func appendMessage(
        threadID: UUID,
        role: YavenChatRole,
        text: String,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) throws -> YavenThreadMessage {
        let message = YavenThreadMessage(
            id: id,
            threadID: threadID,
            role: role,
            text: text,
            createdAt: createdAt
        )
        try upsertMessage(message)
        try updateThread(
            id: threadID,
            lastPreview: text,
            now: createdAt
        )
        return message
    }

    func upsertMessage(_ message: YavenThreadMessage) throws {
        try database.run(
            """
            INSERT INTO thread_messages (id, thread_id, role, text, created_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                text = excluded.text
            """,
            bindings: [
                .text(message.id.uuidString),
                .text(message.threadID.uuidString),
                .text(message.role.rawValue),
                .text(message.text),
                .real(message.createdAt.timeIntervalSince1970)
            ]
        )
    }

    func messages(threadID: UUID) throws -> [YavenThreadMessage] {
        try database.query(
            """
            SELECT id, thread_id, role, text, created_at
            FROM thread_messages
            WHERE thread_id = ?
            ORDER BY created_at ASC, rowid ASC
            """,
            bindings: [.text(threadID.uuidString)]
        ) { statement in
            YavenThreadMessage(
                id: UUID(uuidString: statement.yavenText(at: 0)) ?? UUID(),
                threadID: UUID(uuidString: statement.yavenText(at: 1)) ?? threadID,
                role: YavenChatRole(rawValue: statement.yavenText(at: 2)) ?? .assistant,
                text: statement.yavenText(at: 3),
                createdAt: statement.yavenDate(at: 4)
            )
        }
    }

    func appendCheckpoint<T: Encodable>(
        threadID: UUID,
        stepIndex: Int,
        status: YavenThreadStatus,
        state: T,
        now: Date = Date()
    ) throws {
        let data = try encoder.encode(state)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        let checkpoint = YavenCheckpoint(
            id: UUID(),
            threadID: threadID,
            stepIndex: stepIndex,
            status: status,
            stateJSON: json,
            createdAt: now
        )
        try insertCheckpoint(checkpoint)
    }

    func latestCheckpoint(threadID: UUID) throws -> YavenCheckpoint? {
        try database.query(
            """
            SELECT id, thread_id, step_index, status, state_json, created_at
            FROM checkpoints
            WHERE thread_id = ?
            ORDER BY step_index DESC, created_at DESC
            LIMIT 1
            """,
            bindings: [.text(threadID.uuidString)],
            map: mapCheckpoint
        ).first
    }

    func saveApproval(_ approval: YavenApprovalRequest) throws {
        try database.run(
            """
            INSERT INTO approvals (
                id, thread_id, kind, title, summary, payload_json, status,
                created_at, resolved_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                summary = excluded.summary,
                payload_json = excluded.payload_json,
                status = excluded.status,
                resolved_at = excluded.resolved_at
            """,
            bindings: [
                .text(approval.id.uuidString),
                .text(approval.threadID.uuidString),
                .text(approval.kind.rawValue),
                .text(approval.title),
                .text(approval.summary),
                .text(approval.payloadJSON),
                .text(approval.status.rawValue),
                .real(approval.createdAt.timeIntervalSince1970),
                optionalDate(approval.resolvedAt)
            ]
        )
    }

    func pendingApproval(threadID: UUID) throws -> YavenApprovalRequest? {
        try database.query(
            """
            SELECT id, thread_id, kind, title, summary, payload_json, status,
                   created_at, resolved_at
            FROM approvals
            WHERE thread_id = ? AND status = ?
            ORDER BY created_at DESC
            LIMIT 1
            """,
            bindings: [.text(threadID.uuidString), .text(YavenApprovalStatus.pending.rawValue)],
            map: mapApproval
        ).first
    }

    func approval(id: UUID) throws -> YavenApprovalRequest? {
        try database.query(
            """
            SELECT id, thread_id, kind, title, summary, payload_json, status,
                   created_at, resolved_at
            FROM approvals WHERE id = ?
            """,
            bindings: [.text(id.uuidString)],
            map: mapApproval
        ).first
    }

    func appendActivityEvent(_ event: YavenActivityEvent) throws {
        try database.run(
            """
            INSERT INTO activity_events (
                id, started_at, ended_at, app_name, bundle_identifier, window_title
            ) VALUES (?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(event.id.uuidString),
                .real(event.startedAt.timeIntervalSince1970),
                optionalDate(event.endedAt),
                .text(event.appName),
                optionalText(event.bundleIdentifier),
                optionalText(event.windowTitle)
            ]
        )
    }

    func activityEvents(limit: Int = 50) throws -> [YavenActivityEvent] {
        try database.query(
            """
            SELECT id, started_at, ended_at, app_name, bundle_identifier, window_title
            FROM activity_events
            ORDER BY started_at DESC
            LIMIT ?
            """,
            bindings: [.integer(Int64(limit))]
        ) { statement in
            YavenActivityEvent(
                id: UUID(uuidString: statement.yavenText(at: 0)) ?? UUID(),
                startedAt: statement.yavenDate(at: 1),
                endedAt: statement.yavenOptionalDate(at: 2),
                appName: statement.yavenText(at: 3),
                bundleIdentifier: statement.yavenOptionalText(at: 4),
                windowTitle: statement.yavenOptionalText(at: 5)
            )
        }
    }

    func saveSkillExecution(_ record: YavenSkillExecutionRecord) throws {
        try database.run(
            """
            INSERT INTO skill_execution_records (
                id, thread_id, skill_name, input_json, output_json, succeeded,
                created_at, completed_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                output_json = excluded.output_json,
                succeeded = excluded.succeeded,
                completed_at = excluded.completed_at
            """,
            bindings: [
                .text(record.id.uuidString),
                .text(record.threadID.uuidString),
                .text(record.skillName),
                .text(record.inputJSON),
                optionalText(record.outputJSON),
                record.succeeded.map { .integer($0 ? 1 : 0) } ?? .null,
                .real(record.createdAt.timeIntervalSince1970),
                optionalDate(record.completedAt)
            ]
        )
    }

    func migrateLegacyChatIfNeeded(messages: [YavenChatMessage]) throws -> UUID? {
        guard !messages.isEmpty else { return nil }
        let existingLegacyCount = try database.scalarInt(
            "SELECT COUNT(*) FROM threads WHERE source = ?",
            bindings: [.text("legacy_user_defaults_chat")]
        )
        guard existingLegacyCount == 0 else { return nil }

        let firstDate = messages.first?.createdAt ?? Date()
        let thread = try createThread(
            kind: .chat,
            title: "Previous conversation",
            status: .completed,
            source: "legacy_user_defaults_chat",
            now: firstDate
        )
        for message in messages {
            _ = try appendMessage(
                threadID: thread.id,
                role: message.role,
                text: message.text,
                id: message.id,
                createdAt: message.createdAt
            )
        }
        try updateThread(
            id: thread.id,
            status: .completed,
            lastPreview: messages.last?.text ?? "",
            requiresAttention: false,
            now: messages.last?.createdAt ?? Date()
        )
        return thread.id
    }

    private func migrate() throws {
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS threads (
                id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                status TEXT NOT NULL,
                title TEXT NOT NULL,
                source TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                last_preview TEXT NOT NULL DEFAULT '',
                requires_attention INTEGER NOT NULL DEFAULT 0
            );

            CREATE TABLE IF NOT EXISTS thread_messages (
                id TEXT PRIMARY KEY,
                thread_id TEXT NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
                role TEXT NOT NULL,
                text TEXT NOT NULL,
                created_at REAL NOT NULL
            );

            CREATE TABLE IF NOT EXISTS checkpoints (
                id TEXT PRIMARY KEY,
                thread_id TEXT NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
                step_index INTEGER NOT NULL,
                status TEXT NOT NULL,
                state_json TEXT NOT NULL,
                created_at REAL NOT NULL
            );

            CREATE TABLE IF NOT EXISTS approvals (
                id TEXT PRIMARY KEY,
                thread_id TEXT NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
                kind TEXT NOT NULL,
                title TEXT NOT NULL,
                summary TEXT NOT NULL,
                payload_json TEXT NOT NULL,
                status TEXT NOT NULL,
                created_at REAL NOT NULL,
                resolved_at REAL
            );

            CREATE TABLE IF NOT EXISTS activity_events (
                id TEXT PRIMARY KEY,
                started_at REAL NOT NULL,
                ended_at REAL,
                app_name TEXT NOT NULL,
                bundle_identifier TEXT,
                window_title TEXT
            );

            CREATE TABLE IF NOT EXISTS skill_execution_records (
                id TEXT PRIMARY KEY,
                thread_id TEXT NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
                skill_name TEXT NOT NULL,
                input_json TEXT NOT NULL,
                output_json TEXT,
                succeeded INTEGER,
                created_at REAL NOT NULL,
                completed_at REAL
            );

            CREATE INDEX IF NOT EXISTS idx_threads_updated_at
            ON threads(updated_at DESC);

            CREATE INDEX IF NOT EXISTS idx_messages_thread
            ON thread_messages(thread_id, created_at);

            CREATE INDEX IF NOT EXISTS idx_checkpoints_thread
            ON checkpoints(thread_id, step_index);
            """
        )
    }

    private func insertCheckpoint(_ checkpoint: YavenCheckpoint) throws {
        try database.run(
            """
            INSERT INTO checkpoints (
                id, thread_id, step_index, status, state_json, created_at
            ) VALUES (?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(checkpoint.id.uuidString),
                .text(checkpoint.threadID.uuidString),
                .integer(Int64(checkpoint.stepIndex)),
                .text(checkpoint.status.rawValue),
                .text(checkpoint.stateJSON),
                .real(checkpoint.createdAt.timeIntervalSince1970)
            ]
        )
    }

    private func mapThread(_ statement: OpaquePointer) -> YavenThreadSummary {
        YavenThreadSummary(
            id: UUID(uuidString: statement.yavenText(at: 0)) ?? UUID(),
            kind: YavenThreadKind(rawValue: statement.yavenText(at: 1)) ?? .chat,
            status: YavenThreadStatus(rawValue: statement.yavenText(at: 2)) ?? .failed,
            title: statement.yavenText(at: 3),
            source: statement.yavenOptionalText(at: 4),
            createdAt: statement.yavenDate(at: 5),
            updatedAt: statement.yavenDate(at: 6),
            lastPreview: statement.yavenText(at: 7),
            requiresAttention: sqlite3_column_int64(statement, 8) == 1
        )
    }

    private func mapCheckpoint(_ statement: OpaquePointer) -> YavenCheckpoint {
        YavenCheckpoint(
            id: UUID(uuidString: statement.yavenText(at: 0)) ?? UUID(),
            threadID: UUID(uuidString: statement.yavenText(at: 1)) ?? UUID(),
            stepIndex: Int(sqlite3_column_int64(statement, 2)),
            status: YavenThreadStatus(rawValue: statement.yavenText(at: 3)) ?? .failed,
            stateJSON: statement.yavenText(at: 4),
            createdAt: statement.yavenDate(at: 5)
        )
    }

    private func mapApproval(_ statement: OpaquePointer) -> YavenApprovalRequest {
        YavenApprovalRequest(
            id: UUID(uuidString: statement.yavenText(at: 0)) ?? UUID(),
            threadID: UUID(uuidString: statement.yavenText(at: 1)) ?? UUID(),
            kind: YavenApprovalKind(rawValue: statement.yavenText(at: 2)) ?? .operatorPlan,
            title: statement.yavenText(at: 3),
            summary: statement.yavenText(at: 4),
            payloadJSON: statement.yavenText(at: 5),
            status: YavenApprovalStatus(rawValue: statement.yavenText(at: 6)) ?? .pending,
            createdAt: statement.yavenDate(at: 7),
            resolvedAt: statement.yavenOptionalDate(at: 8)
        )
    }

    private func optionalText(_ value: String?) -> YavenSQLiteValue {
        value.map(YavenSQLiteValue.text) ?? .null
    }

    private func optionalDate(_ value: Date?) -> YavenSQLiteValue {
        value.map { .real($0.timeIntervalSince1970) } ?? .null
    }
}
