//
//  GranolaCliClient.swift
//  leanring-buddy
//
//  Calls the Granola companion CLI to fetch the most recent meeting note.
//
//  Prerequisites (user must do once in Granola):
//    Settings → Labs → enable "Companion CLI"
//
//  CLI binary: /Applications/Granola.app/Contents/Resources/bin/granola
//

import Foundation

enum GranolaCliClient {

    static let binaryPath = "/Applications/Granola.app/Contents/Resources/bin/granola"

    enum GranolaError: LocalizedError {
        case appNotInstalled
        case appNotRunning
        case labsNotEnabled
        case noNotesFound
        case parseFailed(String)

        var errorDescription: String? {
            switch self {
            case .appNotInstalled:
                return "Granola is not installed."
            case .appNotRunning:
                return "Granola is not running. Open the app and try again."
            case .labsNotEnabled:
                return "Enable the Companion CLI in Granola → Settings → Labs, then try again."
            case .noNotesFound:
                return "No recent meetings found in Granola."
            case .parseFailed(let msg):
                return "Could not read Granola response: \(msg)"
            }
        }
    }

    /// Returns the transcript or notes markdown from the most recent Granola meeting.
    static func fetchLatestTranscript() async throws -> String {
        guard FileManager.default.fileExists(atPath: binaryPath) else {
            throw GranolaError.appNotInstalled
        }

        // Step 1: list the most recent note.
        let listJSON = try await run(args: ["notes", "list", "--limit", "1"])

        guard let listData = listJSON.data(using: .utf8),
              let listObj  = try? JSONSerialization.jsonObject(with: listData) as? [String: Any]
        else {
            throw GranolaError.parseFailed("Invalid list response")
        }

        // Handle known error codes from the CLI.
        if let error = listObj["error"] as? [String: Any],
           let code = error["code"] as? String {
            switch code {
            case "APP_NOT_RUNNING": throw GranolaError.appNotRunning
            case "LABS_NOT_ENABLED", "FEATURE_NOT_ENABLED": throw GranolaError.labsNotEnabled
            default: throw GranolaError.parseFailed(error["message"] as? String ?? code)
            }
        }

        guard let notes = listObj["notes"] as? [[String: Any]],
              let firstNote = notes.first,
              let noteId = firstNote["id"] as? String
        else {
            throw GranolaError.noNotesFound
        }

        // Step 2: fetch full note content.
        let noteJSON = try await run(args: ["notes", "get", "--id", noteId])

        guard let noteData = noteJSON.data(using: .utf8),
              let noteObj  = try? JSONSerialization.jsonObject(with: noteData) as? [String: Any],
              let noteList = noteObj["notes"] as? [[String: Any]],
              let note     = noteList.first
        else {
            throw GranolaError.parseFailed("Invalid note response")
        }

        // Prefer transcript, then markdown notes, then plain summary.
        let content = (note["notes_markdown"] as? String)
                   ?? (note["summary_markdown"] as? String)
                   ?? (note["summary_text"]     as? String)
                   ?? ""

        let title = note["title"] as? String ?? "Untitled Meeting"

        guard !content.isEmpty else {
            // Try fetching the transcript separately.
            return try await fetchTranscript(noteId: noteId, title: title)
        }

        return "# \(title)\n\n\(content)"
    }

    private static func fetchTranscript(noteId: String, title: String) async throws -> String {
        let json = try await run(args: ["notes", "transcript", "get", "--id", noteId])

        guard let data = json.data(using: .utf8),
              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw GranolaError.parseFailed("Invalid transcript response")
        }

        if let error = obj["error"] as? [String: Any],
           let code  = error["code"] as? String {
            throw GranolaError.parseFailed(error["message"] as? String ?? code)
        }

        // Transcript is an array of chunks: [{speaker, text, startTime}]
        let chunks  = obj["transcript"] as? [[String: Any]] ?? []
        let text    = chunks.compactMap { chunk -> String? in
            guard let t = chunk["text"] as? String, !t.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            let speaker = chunk["speaker"] as? String ?? "Speaker"
            return "\(speaker): \(t)"
        }.joined(separator: "\n")

        guard !text.isEmpty else { throw GranolaError.noNotesFound }
        return "# \(title)\n\n\(text)"
    }

    // MARK: - Process runner

    private static func run(args: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = args

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError  = Pipe() // silence stderr

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: GranolaError.appNotInstalled)
                return
            }

            process.waitUntilExit()

            let data   = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            continuation.resume(returning: output)
        }
    }
}
