//
//  MailAppleScriptRunner.swift
//  leanring-buddy
//

import AppKit
import Foundation

enum MailAppleScriptError: LocalizedError {
    case mailNotRunning
    case automationPermissionDenied
    case scriptFailed(String)
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .mailNotRunning:
            return "Mail.app is not available. Open Mail and try again."
        case .automationPermissionDenied:
            return "Mail automation permission is required. Open System Settings > Privacy & Security > Automation and allow Yaven to control Mail."
        case .scriptFailed(let detail):
            return "Mail automation failed: \(detail)"
        case .invalidJSON:
            return "Mail returned data Yaven could not read."
        }
    }
}

enum MailAppleScriptRunner {
    private static let batchSize = 25

    static func listRecentEmails(limit: Int = 200) throws -> [RecentEmail] {
        let script = """
        tell application "Mail"
            if not running then return "[]"
            set inboxMailbox to inbox
            set totalCount to count of messages of inboxMailbox
            set fetchCount to \(limit)
            if totalCount < fetchCount then set fetchCount to totalCount
            if fetchCount is 0 then return "[]"
            set recentMessages to messages 1 thru fetchCount of inboxMailbox
            set outputLines to {}
            repeat with msg in recentMessages
                try
                    set msgID to id of msg as string
                    set msgSender to sender of msg as string
                    set msgSubject to subject of msg as string
                    set msgDate to date received of msg as string
                    set msgSnippet to ""
                    try
                        set msgSnippet to text 1 thru 180 of content of msg
                    end try
                    set end of outputLines to msgID & tab & msgSender & tab & msgSubject & tab & msgDate & tab & msgSnippet
                end try
            end repeat
            return outputLines as string
        end tell
        """

        let raw = try run(script)
        if raw.trimmingCharacters(in: .whitespacesAndNewlines) == "[]" {
            return []
        }

        return parseTSVLines(raw)
    }

    static func archiveMessageIDs(_ messageIDs: [String]) throws -> Int {
        try moveMessageIDs(messageIDs, toMailboxNamed: "All Mail", createIfMissing: false, archiveStyle: true)
    }

    static func moveMessageIDs(
        _ messageIDs: [String],
        toMailboxNamed folderName: String,
        createIfMissing: Bool
    ) throws -> Int {
        try moveMessageIDs(
            messageIDs,
            toMailboxNamed: folderName,
            createIfMissing: createIfMissing,
            archiveStyle: false
        )
    }

    static func createMailboxIfMissing(named name: String) throws {
        let escaped = escapeAppleScriptString(name)
        let script = """
        tell application "Mail"
            if not running then error "Mail is not running"
            set targetName to "\(escaped)"
            repeat with acct in accounts
                try
                    set existingMailbox to mailbox targetName of acct
                    return "exists"
                end try
            end repeat
            make new mailbox with properties {name:targetName}
            return "created"
        end tell
        """
        _ = try run(script)
    }

    static func inboxMessageCount() throws -> Int {
        let script = """
        tell application "Mail"
            if not running then return "0"
            return (count of messages of inbox) as string
        end tell
        """
        let raw = try run(script)
        return Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    static func emails(forMessageIDs messageIDs: [String]) throws -> [RecentEmail] {
        guard !messageIDs.isEmpty else { return [] }

        var results: [RecentEmail] = []
        for batch in messageIDs.chunked(into: batchSize) {
            let idList = batch.map { "\"\(escapeAppleScriptString($0))\"" }.joined(separator: ", ")
            let script = """
            tell application "Mail"
                set outputLines to {}
                set idList to {\(idList)}
                repeat with idText in idList
                    try
                        set msg to first message of inbox whose id is (idText as integer)
                        set msgSnippet to ""
                        try
                            set msgSnippet to text 1 thru 180 of content of msg
                        end try
                        set end of outputLines to (id of msg as string) & tab & (sender of msg as string) & tab & (subject of msg as string) & tab & (date received of msg as string) & tab & msgSnippet
                    end try
                end repeat
                return outputLines as string
            end tell
            """
            results.append(contentsOf: parseTSVLines(try run(script)))
        }
        return results
    }

    private static func moveMessageIDs(
        _ messageIDs: [String],
        toMailboxNamed folderName: String,
        createIfMissing: Bool,
        archiveStyle: Bool
    ) throws -> Int {
        guard !messageIDs.isEmpty else { return 0 }

        if createIfMissing {
            try createMailboxIfMissing(named: folderName)
        }

        var movedCount = 0
        let escapedFolder = escapeAppleScriptString(folderName)

        for batch in messageIDs.chunked(into: batchSize) {
            let idList = batch.map { "\"\(escapeAppleScriptString($0))\"" }.joined(separator: ", ")
            let script: String
            if archiveStyle {
                script = """
                tell application "Mail"
                    set movedCount to 0
                    set idList to {\(idList)}
                    repeat with idText in idList
                        try
                            set msg to first message of inbox whose id is (idText as integer)
                            try
                                archive msg
                            on error
                                move msg to mailbox "All Mail"
                            end try
                            set movedCount to movedCount + 1
                        end try
                    end repeat
                    return movedCount as string
                end tell
                """
            } else {
                script = """
                tell application "Mail"
                    set movedCount to 0
                    set idList to {\(idList)}
                    set targetMailbox to missing value
                    repeat with acct in accounts
                        try
                            set targetMailbox to mailbox "\(escapedFolder)" of acct
                            exit repeat
                        end try
                    end repeat
                    if targetMailbox is missing value then error "Mailbox not found"
                    repeat with idText in idList
                        try
                            set msg to first message of inbox whose id is (idText as integer)
                            move msg to targetMailbox
                            set movedCount to movedCount + 1
                        end try
                    end repeat
                    return movedCount as string
                end tell
                """
            }

            let raw = try run(script)
            movedCount += Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }

        return movedCount
    }

    private static func run(_ scriptText: String) throws -> String {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: scriptText) else {
            throw MailAppleScriptError.scriptFailed("Could not compile AppleScript.")
        }

        let output = script.executeAndReturnError(&error)
        if let error {
            let message = (error[NSAppleScript.errorMessage] as? String) ?? "Unknown AppleScript error"
            if message.localizedCaseInsensitiveContains("not running") {
                throw MailAppleScriptError.mailNotRunning
            }
            if message.localizedCaseInsensitiveContains("not authorized") ||
                message.localizedCaseInsensitiveContains("not permitted") ||
                message.localizedCaseInsensitiveContains("not allowed") {
                throw MailAppleScriptError.automationPermissionDenied
            }
            throw MailAppleScriptError.scriptFailed(message)
        }

        return output.stringValue ?? ""
    }

    private static func parseTSVLines(_ raw: String) -> [RecentEmail] {
        let lines = raw
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)

        return lines.compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false)
            guard parts.count >= 4 else { return nil }
            let snippet = parts.count > 4 ? String(parts[4]) : ""
            return RecentEmail(
                id: String(parts[0]),
                sender: String(parts[1]),
                subject: String(parts[2]),
                date: String(parts[3]),
                snippet: snippet.replacingOccurrences(of: "\r", with: " ")
            )
        }
    }

    private static func escapeAppleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        var chunks: [[Element]] = []
        var index = startIndex
        while index < endIndex {
            let end = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            chunks.append(Array(self[index..<end]))
            index = end
        }
        return chunks
    }
}
