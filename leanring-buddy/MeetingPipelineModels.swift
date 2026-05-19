//
//  MeetingPipelineModels.swift
//  leanring-buddy
//
//  All value types for the Founder Meeting-to-Action Pipeline.
//

import Foundation

// MARK: - Input source

enum MeetingInputSource {
    case granola
    case pasted(String)
    case demo
}

// MARK: - Structured extraction (Claude output)

struct MeetingExtraction {
    let meetingTitle: String
    let summary: String
    let attendees: [String]
    let decisions: [String]
    let keyTakeaways: [String]
    let actionItems: [MeetingActionItem]
    let openQuestions: [String]
    let followUpNeeded: Bool
    let followUpRecipient: String?          // name, not email
}

struct MeetingActionItem: Identifiable {
    let id = UUID()
    let owner: String
    let task: String
    let deadline: String?                   // human-readable, e.g. "EOD Thursday"
}

// MARK: - Proposed action

struct MeetingProposedAction: Identifiable {
    let id: UUID
    let kind: MeetingActionKind
    let title: String
    let detail: String
    var status: MeetingActionStatus

    init(kind: MeetingActionKind, title: String, detail: String) {
        self.id     = UUID()
        self.kind   = kind
        self.title  = title
        self.detail = detail
        self.status = .pending
    }
}

enum MeetingActionKind {
    case notionSummary(title: String, markdown: String)
    case hubspotNote(searchQuery: String, noteBody: String)
    case gmailDraft(to: String, subject: String, body: String)
    case calendarReminder(title: String, notes: String, daysFromNow: Int)

    var requiredTool: ComposioRequiredTool {
        switch self {
        case .notionSummary:
            return .init(name: "Notion", composioKey: "NOTION", icon: "doc.text.fill")
        case .hubspotNote:
            return .init(name: "HubSpot", composioKey: "HUBSPOT", icon: "person.fill")
        case .gmailDraft:
            return .init(name: "Gmail", composioKey: "GMAIL", icon: "envelope.fill")
        case .calendarReminder:
            return .init(name: "Google Calendar", composioKey: "GOOGLECALENDAR", icon: "calendar")
        }
    }

    var systemIcon: String {
        switch self {
        case .notionSummary:    return "doc.text.fill"
        case .hubspotNote:      return "person.fill"
        case .gmailDraft:       return "envelope.fill"
        case .calendarReminder: return "calendar"
        }
    }
}

enum MeetingActionStatus: Equatable {
    case pending
    case approved
    case rejected
    case executing
    case completed
    case failed(String)

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .rejected: return true
        default: return false
        }
    }

    var label: String {
        switch self {
        case .pending:         return "Pending"
        case .approved:        return "Approved"
        case .rejected:        return "Skipped"
        case .executing:       return "Running…"
        case .completed:       return "Done"
        case .failed(let msg): return "Failed: \(msg)"
        }
    }
}

// MARK: - Pipeline phase (state machine)

enum MeetingPipelinePhase {
    case idle
    case sourceSelection
    case capturingScreen
    case fetchingTranscript
    case extracting
    case awaitingApproval(MeetingExtraction, [MeetingProposedAction])
    case executing(MeetingExtraction, [MeetingProposedAction])
    case done(MeetingExtraction, [MeetingProposedAction])
    case error(String)

    /// Stable string token for onChange comparisons.
    var key: String {
        switch self {
        case .idle:               return "idle"
        case .sourceSelection:    return "source"
        case .capturingScreen:    return "capturing-screen"
        case .fetchingTranscript: return "fetching"
        case .extracting:         return "extracting"
        case .awaitingApproval:   return "approval"
        case .executing:          return "executing"
        case .done:               return "done"
        case .error:              return "error"
        }
    }
}

// MARK: - Errors

enum MeetingPipelineError: LocalizedError {
    case extractionFailed(String)
    case composioFailed(String)

    var errorDescription: String? {
        switch self {
        case .extractionFailed(let msg): return "Extraction failed: \(msg)"
        case .composioFailed(let slug):  return "\(slug) action failed"
        }
    }
}
