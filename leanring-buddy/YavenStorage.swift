//
//  YavenStorage.swift
//  leanring-buddy
//
//  Static I/O primitives for Yaven's two memory files. No business logic,
//  no Claude calls, no mutable state. All callers are on the main actor
//  so concurrent writes are not possible.
//
//  ~/Library/Application Support/Yaven/signals.jsonl  — append-only signal log
//  ~/Library/Application Support/Yaven/user-profile.json — current profile prose
//

import Foundation

enum YavenStorage {

    // MARK: - Paths

    static let directoryURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Yaven", isDirectory: true)
    }()

    static let signalsLogURL: URL = directoryURL.appendingPathComponent("signals.jsonl")
    static let profileURL: URL = directoryURL.appendingPathComponent("user-profile.json")
    static let databaseURL: URL = directoryURL.appendingPathComponent("yaven.sqlite")

    // MARK: - Directory

    private static func ensureDirectoryExists() {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    // MARK: - Signals

    static func appendSignal(_ signal: Signal) {
        ensureDirectoryExists()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(signal),
              let line = String(data: data, encoding: .utf8),
              let lineData = (line + "\n").data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: signalsLogURL.path) {
            guard let handle = try? FileHandle(forWritingTo: signalsLogURL) else { return }
            handle.seekToEndOfFile()
            handle.write(lineData)
            try? handle.close()
        } else {
            try? lineData.write(to: signalsLogURL, options: .atomic)
        }
    }

    /// Returns up to `limit` most-recent signals in chronological order.
    static func readRecentSignals(limit: Int = 50) -> [Signal] {
        guard let raw = try? String(contentsOf: signalsLogURL, encoding: .utf8) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return raw
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .suffix(limit)
            .compactMap { line -> Signal? in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(Signal.self, from: data)
            }
    }

    // MARK: - Profile

    static func readProfileText() -> String? {
        try? String(contentsOf: profileURL, encoding: .utf8)
    }

    static func writeProfileText(_ text: String) {
        ensureDirectoryExists()
        try? text.write(to: profileURL, atomically: true, encoding: .utf8)
    }
}
