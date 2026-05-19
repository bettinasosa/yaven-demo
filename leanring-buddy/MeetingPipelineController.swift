//
//  MeetingPipelineController.swift
//  leanring-buddy
//
//  @MainActor state machine for the Founder Meeting-to-Action Pipeline.
//
//  Phase flow:
//    idle → sourceSelection → (fetchingTranscript | extracting)
//         → awaitingApproval → executing → done
//
//  Hard rules (from spec):
//  - No external write without explicit per-action approval.
//  - Gmail draft allowed; Gmail send blocked (never called).
//  - Notion, HubSpot, Calendar writes only after approval.
//  - Each action is independently failable; failures are surfaced, not fatal.
//

import Combine
import Foundation

@MainActor
final class MeetingPipelineController: ObservableObject {

    @Published private(set) var phase: MeetingPipelinePhase = .idle

    #if DEBUG
    private let workerBaseURL = "http://localhost:8787"
    #else
    private let workerBaseURL = "https://yaven-proxy.nickprice2000.workers.dev"
    #endif

    private var entityId: String { OnboardingManager.savedEntityId ?? "" }
    private var currentTask: Task<Void, Never>?

    // MARK: - Navigation

    func beginSourceSelection() {
        guard case .idle = phase else { return }
        phase = .sourceSelection
    }

    func reset() {
        currentTask?.cancel()
        phase = .idle
    }

    // MARK: - Source selection

    func selectDemo() {
        runExtraction(source: .demo)
    }

    func selectPasted(_ text: String) {
        runExtraction(source: .pasted(text))
    }

    func selectGranola() {
        currentTask?.cancel()
        currentTask = Task { [weak self] in await self?.fetchFromGranola() }
    }

    func selectScreen() {
        currentTask?.cancel()
        currentTask = Task { [weak self] in await self?.fetchFromScreen() }
    }

    // MARK: - Approval management

    func setActionStatus(_ id: UUID, _ status: MeetingActionStatus) {
        guard case .awaitingApproval(let extraction, var actions) = phase else { return }
        if let i = actions.firstIndex(where: { $0.id == id }) {
            actions[i].status = status
        }
        phase = .awaitingApproval(extraction, actions)
    }

    func approveAll(availableActionIDs: Set<UUID>? = nil) {
        guard case .awaitingApproval(let extraction, var actions) = phase else { return }
        for i in actions.indices where actions[i].status == .pending {
            if let availableActionIDs, !availableActionIDs.contains(actions[i].id) { continue }
            actions[i].status = .approved
        }
        phase = .awaitingApproval(extraction, actions)
    }

    func executeApproved() {
        guard case .awaitingApproval(let extraction, let actions) = phase else { return }
        guard actions.contains(where: { $0.status == .approved }) else { return }
        currentTask?.cancel()
        currentTask = Task { [weak self] in
            await self?.runActions(extraction: extraction, actions: actions)
        }
    }

    // MARK: - Computed helpers

    var approvedCount: Int {
        guard case .awaitingApproval(_, let actions) = phase else { return 0 }
        return actions.filter { $0.status == .approved }.count
    }

    // MARK: - Private: extraction

    private func runExtraction(source: MeetingInputSource) {
        currentTask?.cancel()
        currentTask = Task { [weak self] in
            await self?.extract(source: source)
        }
    }

    private func extract(source: MeetingInputSource) async {
        phase = .extracting
        let transcript: String
        switch source {
        case .demo:             transcript = MeetingDemoData.transcript
        case .pasted(let text): transcript = text
        case .granola:          fatalError("granola should go through fetchFromGranola()")
        }
        do {
            let extraction = try await MeetingExtractionEngine.extract(transcript: transcript)
            let actions = generateProposedActions(from: extraction)
            phase = .awaitingApproval(extraction, actions)
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    // MARK: - Private: Granola fetch

    private func fetchFromGranola() async {
        phase = .fetchingTranscript
        do {
            let transcript = try await GranolaCliClient.fetchLatestTranscript()
            await extract(source: .pasted(transcript))
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    private func fetchFromScreen() async {
        phase = .capturingScreen
        do {
            let captures = try await CompanionScreenCaptureUtility.captureAllScreensAsJPEG()
            let context = YavenComputerContextProvider.makeContext(from: captures)
            phase = .extracting
            let extraction = try await MeetingExtractionEngine.extractFromScreen(
                captures: captures,
                context: context
            )
            let actions = generateProposedActions(from: extraction)
            phase = .awaitingApproval(extraction, actions)
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    // MARK: - Private: action generation

    private func generateProposedActions(from extraction: MeetingExtraction) -> [MeetingProposedAction] {
        var actions: [MeetingProposedAction] = []

        // Notion meeting page — always proposed.
        actions.append(MeetingProposedAction(
            kind: .notionSummary(
                title: extraction.meetingTitle,
                markdown: buildNotionMarkdown(from: extraction)
            ),
            title: "Add meeting page to Notion",
            detail: "Creates a new page with summary, decisions, and action items."
        ))

        // HubSpot note — when a specific follow-up recipient is identified.
        if let recipient = extraction.followUpRecipient, !recipient.isEmpty {
            actions.append(MeetingProposedAction(
                kind: .hubspotNote(
                    searchQuery: recipient,
                    noteBody: buildHubSpotNote(from: extraction)
                ),
                title: "HubSpot note — \(recipient)",
                detail: "Adds meeting summary as a note to \(recipient)'s contact record."
            ))
        }

        // Gmail draft — only when follow-up is flagged. Send is never called.
        if extraction.followUpNeeded, let recipient = extraction.followUpRecipient {
            actions.append(MeetingProposedAction(
                kind: .gmailDraft(
                    to: recipient,
                    subject: "Follow-up: \(extraction.meetingTitle)",
                    body: buildFollowUpEmail(from: extraction)
                ),
                title: "Draft follow-up email",
                detail: "Creates a Gmail draft to \(recipient). Will NOT send automatically."
            ))
        }

        // Calendar reminder — when any action item has a deadline.
        if extraction.actionItems.contains(where: { $0.deadline != nil }) {
            let deadlineItems = extraction.actionItems.filter { $0.deadline != nil }
            let notes = deadlineItems.map { "• \($0.task) (\($0.deadline!))" }.joined(separator: "\n")
            actions.append(MeetingProposedAction(
                kind: .calendarReminder(
                    title: "Follow up: \(extraction.meetingTitle)",
                    notes: notes,
                    daysFromNow: 2
                ),
                title: "Calendar reminder in 2 days",
                detail: "Reminder to follow up on \(deadlineItems.count) time-bound action item\(deadlineItems.count == 1 ? "" : "s")."
            ))
        }

        return actions
    }

    // MARK: - Content builders

    private func buildNotionMarkdown(from e: MeetingExtraction) -> String {
        var md = "# \(e.meetingTitle)\n\n"
        md += "## Summary\n\(e.summary)\n\n"
        if !e.attendees.isEmpty {
            md += "## Attendees\n" + e.attendees.map { "- \($0)" }.joined(separator: "\n") + "\n\n"
        }
        if !e.decisions.isEmpty {
            md += "## Decisions\n" + e.decisions.map { "- \($0)" }.joined(separator: "\n") + "\n\n"
        }
        if !e.keyTakeaways.isEmpty {
            md += "## Key Takeaways\n" + e.keyTakeaways.map { "- \($0)" }.joined(separator: "\n") + "\n\n"
        }
        if !e.actionItems.isEmpty {
            md += "## Action Items\n"
            for item in e.actionItems {
                let dl = item.deadline.map { " _(by \($0))_" } ?? ""
                md += "- [ ] **\(item.owner):** \(item.task)\(dl)\n"
            }
            md += "\n"
        }
        if !e.openQuestions.isEmpty {
            md += "## Open Questions\n" + e.openQuestions.map { "- \($0)" }.joined(separator: "\n") + "\n"
        }
        return md
    }

    private func buildHubSpotNote(from e: MeetingExtraction) -> String {
        var note = "**\(e.meetingTitle)**\n\n\(e.summary)"
        if !e.decisions.isEmpty {
            note += "\n\n**Decisions:**\n" + e.decisions.map { "• \($0)" }.joined(separator: "\n")
        }
        if !e.actionItems.isEmpty {
            note += "\n\n**Next steps:**\n" + e.actionItems.map { "• \($0.owner): \($0.task)" }.joined(separator: "\n")
        }
        return note
    }

    private func buildFollowUpEmail(from e: MeetingExtraction) -> String {
        let firstName = e.followUpRecipient?.components(separatedBy: " ").first ?? "there"
        var body = "Hi \(firstName),\n\nGreat speaking with you — here's a quick recap of our conversation about \(e.meetingTitle.lowercased()).\n\n"
        body += e.summary + "\n\n"
        if !e.decisions.isEmpty {
            body += "**Key decisions:**\n" + e.decisions.map { "• \($0)" }.joined(separator: "\n") + "\n\n"
        }
        let ourActions = e.actionItems.filter { item in
            let lower = item.owner.lowercased()
            return lower.contains("bettina") || lower.contains("nick") || lower.contains("we") || lower.contains("our")
        }
        if !ourActions.isEmpty {
            body += "**On our end:**\n" + ourActions.map { "• \($0.task)" }.joined(separator: "\n") + "\n\n"
        }
        body += "Looking forward to the next steps.\n\nBest,\nBettina"
        return body
    }

    // MARK: - Private: execution

    private func runActions(extraction: MeetingExtraction, actions: [MeetingProposedAction]) async {
        var mutable = actions
        phase = .executing(extraction, mutable)

        for i in mutable.indices {
            guard mutable[i].status == .approved else { continue }
            mutable[i].status = .executing
            phase = .executing(extraction, mutable)

            do {
                try await executeAction(mutable[i])
                mutable[i].status = .completed
            } catch {
                mutable[i].status = .failed(error.localizedDescription)
            }
            phase = .executing(extraction, mutable)
        }

        phase = .done(extraction, mutable)
    }

    private func executeAction(_ action: MeetingProposedAction) async throws {
        switch action.kind {

        case .notionSummary(let title, let markdown):
            _ = try await composioExecute(
                actionSlug: "NOTION_CREATE_PAGE",
                arguments: ["title": title, "content": markdown]
            )

        case .hubspotNote(let searchQuery, let noteBody):
            // Search for the contact, then add a note.
            let searchData = try await composioExecute(
                actionSlug: "HUBSPOT_SEARCH_CONTACTS",
                arguments: ["query": searchQuery, "limit": 1]
            )
            var noteArgs: [String: Any] = ["note_body": noteBody]
            if let contactId = firstContactId(from: searchData) {
                noteArgs["contact_id"] = contactId
            }
            _ = try await composioExecute(actionSlug: "HUBSPOT_CREATE_NOTE_ENGAGEMENT", arguments: noteArgs)

        case .gmailDraft(let to, let subject, let body):
            // Creates a draft only — send is intentionally never called.
            _ = try await composioExecute(
                actionSlug: "GMAIL_CREATE_DRAFT_EMAIL",
                arguments: ["recipient_email": to, "subject": subject, "body": body]
            )

        case .calendarReminder(let title, let notes, let daysFromNow):
            let startDate = ISO8601DateFormatter().string(
                from: Calendar.current.date(byAdding: .day, value: daysFromNow, to: Date()) ?? Date()
            )
            _ = try await composioExecute(
                actionSlug: "GOOGLECALENDAR_CREATE_EVENT",
                arguments: ["summary": title, "description": notes, "start": startDate, "duration_minutes": 30]
            )
        }
    }

    private func firstContactId(from data: Data) -> String? {
        guard
            let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let payload = (json["data"] as? [String: Any]) ?? (json["response_data"] as? [String: Any]),
            let results = payload["results"] as? [[String: Any]],
            let id      = results.first?["id"] as? String
        else { return nil }
        return id
    }

    // MARK: - Private: Composio HTTP helper

    private func composioExecute(actionSlug: String, arguments: [String: Any]) async throws -> Data {
        guard let url = URL(string: "\(workerBaseURL)/execute") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "actionSlug": actionSlug,
            "entityId":   entityId,
            "arguments":  arguments,
        ])
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw MeetingPipelineError.composioFailed("\(actionSlug): \(detail)")
        }
        return data
    }
}
