//
//  MailSkills.swift
//  leanring-buddy
//

import Foundation

enum MailSkills {
    static func makeAll() -> [YavenSkill] {
        [
            listRecentEmails,
            archiveEmailsBulk,
            moveEmailsToFolder,
            createMailboxIfMissing,
            proposeCleanupPlan
        ]
    }

    static let listRecentEmails = YavenSkill(
        name: "list_recent_emails",
        kind: .read
    ) { _ in
        let emails = try MailAppleScriptRunner.listRecentEmails(limit: 200)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(emails)
        guard let json = String(data: data, encoding: .utf8) else {
            throw MailAppleScriptError.invalidJSON
        }
        return json
    }

    static let archiveEmailsBulk = YavenSkill(
        name: "archive_emails_bulk",
        kind: .write(requiresApproval: true)
    ) { input in
        let messageIDs = try Self.stringArray(from: input["message_ids"])
        let moved = try MailAppleScriptRunner.archiveMessageIDs(messageIDs)
        return "Archived \(moved) email(s)."
    }

    static let moveEmailsToFolder = YavenSkill(
        name: "move_emails_to_folder",
        kind: .write(requiresApproval: true)
    ) { input in
        let messageIDs = try Self.stringArray(from: input["message_ids"])
        let folderName = try Self.requiredString(from: input["folder_name"], key: "folder_name")
        let moved = try MailAppleScriptRunner.moveMessageIDs(
            messageIDs,
            toMailboxNamed: folderName,
            createIfMissing: true
        )
        return "Moved \(moved) email(s) to \(folderName)."
    }

    static let createMailboxIfMissing = YavenSkill(
        name: "create_mailbox_if_missing",
        kind: .write(requiresApproval: false)
    ) { input in
        let name = try Self.requiredString(from: input["name"], key: "name")
        try MailAppleScriptRunner.createMailboxIfMissing(named: name)
        return "Mailbox \(name) is ready."
    }

    static let proposeCleanupPlan = YavenSkill(
        name: "propose_cleanup_plan",
        kind: .structuredOutput
    ) { _ in
        "plan presented to user, awaiting approval."
    }

    private static func stringArray(from value: Any?) throws -> [String] {
        if let strings = value as? [String] {
            return strings
        }
        if let anyArray = value as? [Any] {
            return anyArray.compactMap { $0 as? String }
        }
        throw NSError(domain: "MailSkills", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "message_ids must be an array of strings."
        ])
    }

    private static func requiredString(from value: Any?, key: String) throws -> String {
        guard let string = value as? String, !string.isEmpty else {
            throw NSError(domain: "MailSkills", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "\(key) is required."
            ])
        }
        return string
    }
}
