//
//  YavenThreadModels.swift
//  leanring-buddy
//

import Foundation

enum YavenThreadKind: String, Codable, CaseIterable {
    case chat
    case research
    case automation
    case crm
    case cleanup

    var displayTitle: String {
        switch self {
        case .chat: return "Chat"
        case .research: return "Research"
        case .automation: return "Automation"
        case .crm: return "CRM"
        case .cleanup: return "Cleanup"
        }
    }
}

enum YavenThreadStatus: String, Codable, CaseIterable {
    case queued
    case running
    case approvalRequired
    case completed
    case failed
    case cancelled

    var displayTitle: String {
        switch self {
        case .queued: return "Queued"
        case .running: return "Running"
        case .approvalRequired: return "Needs approval"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

struct YavenThreadSummary: Identifiable, Codable, Equatable {
    let id: UUID
    var kind: YavenThreadKind
    var status: YavenThreadStatus
    var title: String
    var source: String?
    var createdAt: Date
    var updatedAt: Date
    var lastPreview: String
    var requiresAttention: Bool
}

struct YavenThreadMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let threadID: UUID
    let role: YavenChatRole
    var text: String
    let createdAt: Date
}

struct YavenCheckpoint: Identifiable, Codable, Equatable {
    let id: UUID
    let threadID: UUID
    let stepIndex: Int
    let status: YavenThreadStatus
    let stateJSON: String
    let createdAt: Date
}

enum YavenApprovalKind: String, Codable {
    case operatorPlan
    case crmSkill
    case mailCleanup
}

enum YavenApprovalStatus: String, Codable {
    case pending
    case approved
    case rejected
    case executed
}

struct YavenApprovalRequest: Identifiable, Codable, Equatable {
    let id: UUID
    let threadID: UUID
    let kind: YavenApprovalKind
    var title: String
    var summary: String
    var payloadJSON: String
    var status: YavenApprovalStatus
    let createdAt: Date
    var resolvedAt: Date?
}

struct YavenActivityEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    let appName: String
    let bundleIdentifier: String?
    let windowTitle: String?
}

struct YavenSkillExecutionRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let threadID: UUID
    let skillName: String
    let inputJSON: String
    var outputJSON: String?
    var succeeded: Bool?
    let createdAt: Date
    var completedAt: Date?
}
