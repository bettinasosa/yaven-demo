//
//  YavenMailCleanupApproval.swift
//  leanring-buddy
//

import Foundation

enum YavenMailCleanupAction: String, Codable, Equatable {
    case archive
    case moveToFolder
    case surface
    case leaveAlone
}

struct YavenMailCleanupApprovalPlan: Codable, Equatable {
    let totalReviewed: Int
    let emails: [RecentEmail]
    let batches: [YavenMailCleanupBatch]

    var summary: String {
        batches.map(\.summary).joined(separator: "; ")
    }

    var emailsByID: [String: RecentEmail] {
        Dictionary(uniqueKeysWithValues: emails.map { ($0.id, $0) })
    }
}

struct YavenMailCleanupBatch: Codable, Identifiable, Equatable {
    let id: UUID
    let category: YavenCategory
    let messageIds: [String]
    let summary: String
    let action: YavenMailCleanupAction
    let folderName: String?

    init(
        id: UUID = UUID(),
        category: YavenCategory,
        messageIds: [String],
        summary: String,
        action: YavenMailCleanupAction,
        folderName: String?
    ) {
        self.id = id
        self.category = category
        self.messageIds = messageIds
        self.summary = summary
        self.action = action
        self.folderName = folderName
    }

    var actionTitle: String {
        switch action {
        case .archive:
            return "Archive"
        case .moveToFolder:
            return "Move to \(folderName ?? "folder")"
        case .surface:
            return "Surface"
        case .leaveAlone:
            return "Leave alone"
        }
    }
}

extension YavenMailCleanupApprovalPlan {
    init(cleanupPlan: CleanupPlan, emails: [RecentEmail]) {
        self.totalReviewed = cleanupPlan.totalReviewed
        self.emails = emails
        self.batches = cleanupPlan.batches.map { batch in
            let action: YavenMailCleanupAction
            let folderName: String?
            switch batch.defaultAction {
            case .archive:
                action = .archive
                folderName = nil
            case .moveToFolder(let targetFolderName):
                action = .moveToFolder
                folderName = targetFolderName
            case .surface:
                action = .surface
                folderName = nil
            case .leaveAlone:
                action = .leaveAlone
                folderName = nil
            }

            return YavenMailCleanupBatch(
                category: batch.category,
                messageIds: batch.messageIds,
                summary: batch.summary,
                action: action,
                folderName: folderName
            )
        }
    }
}
