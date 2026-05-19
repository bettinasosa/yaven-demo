//
//  YavenWorkflowModels.swift
//  leanring-buddy
//
//  Core data models for the Yaven workflow engine.
//  All types are Codable for SQLite/disk persistence.
//

import Foundation

// MARK: - Workflow identity

enum WorkflowID: String {
    case salesCallLogger = "sales-call-logger"
    case preCallBrief    = "pre-call-brief"
}

// MARK: - Workflow run lifecycle

enum WorkflowRunStatus: String, Codable {
    case collectingInput   // waiting for the user to supply content
    case extracting        // Claude is parsing the raw content
    case searchingCRM      // looking up HubSpot contact / deal
    case awaitingApproval  // proposed actions shown; waiting for user
    case executing         // running approved Composio actions
    case done
    case failed
}

// MARK: - Input

enum WorkflowInputSource: String, Codable {
    case pastedNotes   // user typed / pasted call notes into the text field
    case transcript    // full call transcript (pasted or from Granola)
    case screen        // screen context captured on submit
    case granola       // Granola meeting note (future integration)
    case demo          // built-in demo transcript for testing
}

struct WorkflowInput: Codable {
    let source: WorkflowInputSource
    let rawContent: String
}

// MARK: - Extracted sales-call data

enum CallSentiment: String, Codable {
    case positive
    case neutral
    case negative
}

/// Schema-validated output from the Claude extraction pass.
/// Must be kept in sync with the JSON schema in LogCallExtractionEngine.
struct SalesCallData: Codable {
    let contactName: String?
    let contactEmail: String?
    let companyName: String?
    let dealName: String?
    let callSummary: String
    let keyPoints: [String]
    let nextSteps: [String]
    let dealStage: String?      // one of the HubSpot pipeline stages or null
    let sentiment: CallSentiment
    let callDate: String        // ISO 8601 date string
    let followUpSubject: String?
    let followUpBody: String?   // draft body — never auto-sent
}

// MARK: - Proposed actions

enum WorkflowActionType: String, Codable {
    case hubspotCallNote      // create engagement note on a contact / deal
    case hubspotStatusUpdate  // move the deal to a new pipeline stage
    case hubspotFollowUpTask  // create a CRM task on the contact / deal
    case gmailDraft           // create a Gmail draft — NEVER send automatically
    case calendarReminder     // create a Calendar event as a reminder
    case notionUpdate         // update a Notion page (optional)

    var requiredTool: ComposioRequiredTool? {
        switch self {
        case .hubspotCallNote, .hubspotStatusUpdate, .hubspotFollowUpTask:
            return .init(name: "HubSpot", composioKey: "HUBSPOT", icon: "person.fill")
        case .gmailDraft:
            return .init(name: "Gmail", composioKey: "GMAIL", icon: "envelope.fill")
        case .calendarReminder:
            return .init(name: "Google Calendar", composioKey: "GOOGLECALENDAR", icon: "calendar")
        case .notionUpdate:
            return .init(name: "Notion", composioKey: "NOTION", icon: "doc.text.fill")
        }
    }
}

enum WorkflowActionStatus: String, Codable {
    case pending     // shown in approval card, not yet approved or skipped
    case approved    // user approved — will execute
    case skipped     // user unchecked / skipped — will not execute
    case executing   // currently running
    case succeeded
    case failed
}

struct WorkflowAction: Identifiable, Codable {
    let id: String
    let type: WorkflowActionType
    let title: String
    let description: String
    /// Composio action key. nil for actions with no Composio call.
    let composioTool: String?
    /// JSON-encoded payload for the Composio call. Always schema-validated before use.
    let payloadJSON: String
    var status: WorkflowActionStatus
    var errorMessage: String?
}

// MARK: - Allowlist

/// Hard allowlist for Composio tools this workflow may invoke.
/// Any tool not in `allowed` is unconditionally blocked before network I/O.
enum WorkflowAllowlist {
    static let allowed: Set<String> = [
        "HUBSPOT_CREATE_ENGAGEMENT",
        "HUBSPOT_CREATE_NOTE_ENGAGEMENT",
        "HUBSPOT_UPDATE_DEAL",
        "HUBSPOT_CREATE_TASK",
        "GMAIL_CREATE_DRAFT",
        "GMAIL_CREATE_DRAFT_EMAIL",
        "GOOGLECALENDAR_CREATE_EVENT",
    ]

    /// Tools that are explicitly blocked regardless of any other logic.
    static let blocked: Set<String> = [
        "GMAIL_SEND_EMAIL",
        "GMAIL_REPLY_TO_THREAD",
        "GMAIL_FORWARD_EMAIL",
    ]

    static func isPermitted(_ tool: String) -> Bool {
        !blocked.contains(tool) && allowed.contains(tool)
    }
}

// MARK: - Workflow run

struct WorkflowRun: Identifiable, Codable {
    let id: UUID
    let workflowID: String
    var status: WorkflowRunStatus
    let input: WorkflowInput
    var extractedData: SalesCallData?
    var hubspotContactID: String?
    var hubspotDealID: String?
    var proposedActions: [WorkflowAction]
    var executionLog: [String]
    let createdAt: Date
    var completedAt: Date?
    var errorMessage: String?

    init(workflowID: String, input: WorkflowInput) {
        self.id = UUID()
        self.workflowID = workflowID
        self.status = .collectingInput
        self.input = input
        self.proposedActions = []
        self.executionLog = []
        self.createdAt = Date()
    }
}
