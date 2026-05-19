//
//  LogCallController.swift
//  leanring-buddy
//
//  @MainActor ObservableObject that drives the full Log Call pipeline:
//  input selection → extraction → CRM search → approval → execution → done.
//
//  The controller is owned by YavenPanelView and lives as long as the panel.
//  Resetting it returns to the idle/input phase.
//

import Combine
import Foundation
import SwiftUI

// MARK: - Phase

enum LogCallPhase {
    case idle                                   // chip visible, no workflow active
    case collectingInput                        // text editor shown
    case extracting                             // spinner — Claude parsing
    case awaitingApproval([WorkflowAction])     // approval cards
    case executing                              // running approved actions
    case done(SalesCallData, [WorkflowAction])  // success summary
    case failed(String)                         // error message
}

// MARK: - Controller

@MainActor
final class LogCallController: ObservableObject {

    // MARK: Published state

    @Published private(set) var phase: LogCallPhase = .idle
    @Published var pastedContent: String = ""
    @Published var selectedToolKeys: Set<String> = []

    // MARK: Private

    private let engine = LogCallExtractionEngine()
    private var extractedData: SalesCallData?
    private var runningTask: Task<Void, Never>?

    #if DEBUG
    private let workerBaseURL = "http://localhost:8787"
    #else
    private let workerBaseURL = "https://yaven-proxy.nickprice2000.workers.dev"
    #endif

    private var entityId: String { OnboardingManager.savedEntityId ?? "" }
    private static let supportedToolKeys: Set<String> = ["HUBSPOT", "GMAIL"]

    init() {
        selectedToolKeys = Self.defaultSelectedToolKeys()
    }

    // MARK: - Entry points

    func startWithPastedNotes() {
        refreshToolSelectionFromConnections()
        pastedContent = ""
        phase = .collectingInput
    }

    func startWithDemo() {
        refreshToolSelectionFromConnections()
        pastedContent = LogCallExtractionEngine.demoTranscript
        phase = .collectingInput
    }

    func startFromScreen() {
        refreshToolSelectionFromConnections()
        guard !selectedToolKeys.isEmpty else {
            phase = .failed("Choose at least one destination tool before logging the call.")
            return
        }
        phase = .extracting
        runningTask = Task { [weak self] in
            guard let self else { return }
            do {
                let captures = try await CompanionScreenCaptureUtility.captureAllScreensAsJPEG()
                let context = YavenComputerContextProvider.makeContext(from: captures)
                let data = try await self.engine.extractFromScreen(captures: captures, context: context)
                self.extractedData = data
                let actions = self.buildActions(from: data)
                if Task.isCancelled { return }
                self.phase = .awaitingApproval(actions)
            } catch {
                if !Task.isCancelled {
                    self.phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    func submitContent() {
        let content = pastedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        guard !selectedToolKeys.isEmpty else {
            phase = .failed("Choose at least one destination tool before logging the call.")
            return
        }
        runPipeline(rawContent: content)
    }

    func cancel() {
        runningTask?.cancel()
        runningTask = nil
        phase = .idle
        pastedContent = ""
        extractedData = nil
    }

    func setTool(_ composioKey: String, enabled: Bool) {
        let key = composioKey.uppercased()
        if enabled {
            selectedToolKeys.insert(key)
        } else {
            selectedToolKeys.remove(key)
        }
    }

    func refreshToolSelectionFromConnections() {
        let connectedSupportedKeys = Self.defaultSelectedToolKeys()
        if selectedToolKeys.isEmpty {
            selectedToolKeys = connectedSupportedKeys
        } else {
            selectedToolKeys = selectedToolKeys.intersection(Self.supportedToolKeys)
        }
    }

    // MARK: - Approval

    /// Called with the set of action IDs the user has approved.
    /// Actions not in `approvedIDs` are marked skipped.
    func executeApproved(approvedIDs: Set<String>) {
        guard case .awaitingApproval(var actions) = phase else { return }

        for index in actions.indices {
            actions[index].status = approvedIDs.contains(actions[index].id) ? .approved : .skipped
        }

        let approvedActions = actions.filter { $0.status == .approved }
        guard !approvedActions.isEmpty else {
            phase = .done(extractedData ?? dummyData(), actions)
            return
        }

        phase = .executing
        runningTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.executeActions(approvedActions, allActions: actions)
            self.phase = result
        }
    }

    // MARK: - Pipeline

    private func runPipeline(rawContent: String) {
        phase = .extracting
        runningTask = Task { [weak self] in
            guard let self else { return }
            do {
                let data = try await self.engine.extract(from: rawContent)
                self.extractedData = data
                let actions = self.buildActions(from: data)
                if Task.isCancelled { return }
                self.phase = .awaitingApproval(actions)
            } catch {
                if !Task.isCancelled {
                    self.phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Build actions

    private func buildActions(from data: SalesCallData) -> [WorkflowAction] {
        var actions: [WorkflowAction] = []

        // 1. HubSpot call engagement note
        if selectedToolKeys.contains("HUBSPOT") {
            let notePayload: [String: Any] = [
                "contactEmail": data.contactEmail as Any,
                "companyName": data.companyName as Any,
                "note": data.callSummary,
                "keyPoints": data.keyPoints,
                "callDate": data.callDate
            ]
            actions.append(WorkflowAction(
                id: UUID().uuidString,
                type: .hubspotCallNote,
                title: "Log call note in HubSpot",
                description: "Creates an engagement on \(data.contactName ?? "the contact") with the call summary and key points.",
                composioTool: "HUBSPOT_CREATE_ENGAGEMENT",
                payloadJSON: encodeJSON(notePayload),
                status: .pending
            ))
        }

        // 2. HubSpot deal stage update (only if extraction found a stage)
        if selectedToolKeys.contains("HUBSPOT"), let stage = data.dealStage {
            let stagePayload: [String: Any] = [
                "companyName": data.companyName as Any,
                "dealName": data.dealName as Any,
                "newStage": stage
            ]
            actions.append(WorkflowAction(
                id: UUID().uuidString,
                type: .hubspotStatusUpdate,
                title: "Update deal stage",
                description: "Moves the deal to \"\(humanReadableStage(stage))\".",
                composioTool: "HUBSPOT_UPDATE_DEAL",
                payloadJSON: encodeJSON(stagePayload),
                status: .pending
            ))
        }

        // 3. HubSpot follow-up task (if next steps exist)
        if selectedToolKeys.contains("HUBSPOT"), !data.nextSteps.isEmpty {
            let taskPayload: [String: Any] = [
                "contactEmail": data.contactEmail as Any,
                "subject": "Follow-up: \(data.contactName ?? data.companyName ?? "call")",
                "notes": data.nextSteps.joined(separator: "\n"),
                "dueDate": nextBusinessDay(from: data.callDate)
            ]
            actions.append(WorkflowAction(
                id: UUID().uuidString,
                type: .hubspotFollowUpTask,
                title: "Create follow-up task in HubSpot",
                description: "\(data.nextSteps.count) next step(s) added as a CRM task.",
                composioTool: "HUBSPOT_CREATE_TASK",
                payloadJSON: encodeJSON(taskPayload),
                status: .pending
            ))
        }

        // 4. Gmail draft (only if extraction produced a follow-up)
        if selectedToolKeys.contains("GMAIL"), let subject = data.followUpSubject, let body = data.followUpBody {
            let draftPayload: [String: Any] = [
                "recipient_email": data.contactEmail as Any,
                "subject": subject,
                "body": body
            ]
            actions.append(WorkflowAction(
                id: UUID().uuidString,
                type: .gmailDraft,
                title: "Draft follow-up email",
                description: "Creates a Gmail draft to \(data.contactName ?? "the contact") — never sent automatically.",
                composioTool: "GMAIL_CREATE_DRAFT_EMAIL",
                payloadJSON: encodeJSON(draftPayload),
                status: .pending
            ))
        }

        return actions
    }

    // MARK: - Execute approved actions

    private func executeActions(
        _ approved: [WorkflowAction],
        allActions: [WorkflowAction]
    ) async -> LogCallPhase {
        var updatedAll = allActions
        var anyFailed = false

        for action in approved {
            guard WorkflowAllowlist.isPermitted(action.composioTool ?? "") else {
                updateStatus(.failed, for: action.id, in: &updatedAll,
                             error: "Blocked: \(action.composioTool ?? "unknown") is not on the allow-list.")
                anyFailed = true
                continue
            }

            if Task.isCancelled { break }
            updateStatus(.executing, for: action.id, in: &updatedAll)

            do {
                try await callComposio(action: action)
                updateStatus(.succeeded, for: action.id, in: &updatedAll)
            } catch {
                updateStatus(.failed, for: action.id, in: &updatedAll, error: error.localizedDescription)
                anyFailed = true
            }
        }

        _ = anyFailed  // surfaced per-action — overall phase is still done
        return .done(extractedData ?? dummyData(), updatedAll)
    }

    private func updateStatus(
        _ status: WorkflowActionStatus,
        for id: String,
        in actions: inout [WorkflowAction],
        error: String? = nil
    ) {
        if let idx = actions.firstIndex(where: { $0.id == id }) {
            actions[idx].status = status
            actions[idx].errorMessage = error
        }
    }

    // MARK: - Composio call

    private func callComposio(action: WorkflowAction) async throws {
        guard let tool = action.composioTool else { return }
        guard !entityId.isEmpty else { throw ComposioError.notSignedIn }

        let workerURL = URL(string: "\(workerBaseURL)/execute")!
        var request = URLRequest(url: workerURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "actionSlug": tool,
            "entityId": entityId,
            "arguments": decodedPayload(for: action)
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw ComposioError.callFailed("\(tool): \(detail)")
        }
    }

    // MARK: - Helpers

    private func encodeJSON(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: .sortedKeys),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    private func decodedPayload(for action: WorkflowAction) -> [String: Any] {
        guard let data = action.payloadJSON.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return payload
    }

    private static func defaultSelectedToolKeys() -> Set<String> {
        OnboardingManager.connectedToolKeys.intersection(supportedToolKeys)
    }

    private func humanReadableStage(_ stage: String) -> String {
        let map: [String: String] = [
            "appointmentscheduled": "Appointment Scheduled",
            "qualifiedtobuy": "Qualified to Buy",
            "presentationscheduled": "Presentation Scheduled",
            "decisionmakerboughtin": "Decision Maker Bought-In",
            "contractsent": "Contract Sent",
            "closedwon": "Closed Won",
            "closedlost": "Closed Lost"
        ]
        return map[stage] ?? stage
    }

    /// Returns the ISO date string for the next business day after `dateString`.
    private func nextBusinessDay(from dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let base = formatter.date(from: dateString) ?? Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")

        var candidate = calendar.date(byAdding: .day, value: 1, to: base) ?? base
        while calendar.isDateInWeekend(candidate) {
            candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        }
        return formatter.string(from: candidate)
    }

    private func dummyData() -> SalesCallData {
        SalesCallData(
            contactName: nil, contactEmail: nil, companyName: nil, dealName: nil,
            callSummary: "", keyPoints: [], nextSteps: [], dealStage: nil,
            sentiment: .neutral, callDate: "", followUpSubject: nil, followUpBody: nil
        )
    }
}

// MARK: - Errors

enum ComposioError: LocalizedError {
    case notSignedIn
    case callFailed(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Sign in before running connected-tool actions."
        case .callFailed(let tool): return "\(tool) returned an error. Check that the tool is connected in Composio."
        }
    }
}
