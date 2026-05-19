//
//  YavenCleanupModels.swift
//  leanring-buddy
//

import Foundation

enum YavenCategory: String, CaseIterable, Codable {
    case newsletters
    case promotions
    case needsReply = "needs_reply"
    case receipts
    case personalWork = "personal_work"

    var displayEmoji: String {
        switch self {
        case .newsletters: return "📰"
        case .promotions: return "🏷️"
        case .needsReply: return "✉️"
        case .receipts: return "🧾"
        case .personalWork: return "🗂️"
        }
    }

    var displayTitle: String {
        switch self {
        case .newsletters: return "newsletters"
        case .promotions: return "promotions and sales pitches"
        case .needsReply: return "emails that look like they need you"
        case .receipts: return "receipts and confirmations"
        case .personalWork: return "personal and work emails"
        }
    }
}

enum CleanupAction: Equatable {
    case archive
    case moveToFolder(String)
    case surface
    case leaveAlone
}

struct CategorizedBatch: Identifiable, Equatable {
    let id = UUID()
    let category: YavenCategory
    let messageIds: [String]
    let summary: String
    let defaultAction: CleanupAction
    var excludedMessageIds: Set<String> = []

    var effectiveMessageIds: [String] {
        messageIds.filter { !excludedMessageIds.contains($0) }
    }
}

struct CleanupPlan: Equatable {
    let batches: [CategorizedBatch]
    let totalReviewed: Int
}

struct RecentEmail: Codable, Equatable, Identifiable {
    let id: String
    let sender: String
    let subject: String
    let date: String
    let snippet: String
}

struct NeedsReplyItem: Identifiable, Equatable {
    let id: String
    let sender: String
    let subject: String
    let actionDescription: String
}

enum OnboardingArrivalState: Equatable {
    case fadingOutOnboarding
    case waitingInDarkness
    case bloomingOrb
    case settled
    case panelOpen
    case yesPath
    case laterPath
}

enum YavenCleanupPhase: Equatable {
    case idle
    case scanning(lines: [String], visibleLineCount: Int)
    case awaitingApproval(CleanupPlan, emailsByID: [String: RecentEmail])
    case executing(lines: [String])
    case done(
        archivedCount: Int,
        filedReceiptCount: Int,
        inboxCount: Int,
        needsReplyItems: [NeedsReplyItem]
    )
    case skipped
    case error(String)
}

enum YavenFirstRunPanelMode: Equatable {
    case hidden
    case firstMessage
    case cleanup
}
