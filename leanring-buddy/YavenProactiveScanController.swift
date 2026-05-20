//
//  YavenProactiveScanController.swift
//  leanring-buddy
//
//  Fetches recent emails and upcoming calendar events, then asks Claude
//  to identify the most important actions right now — grouped by confidence.
//
//  Runs at most once every 30 minutes. Called by YavenAgentController
//  when the panel becomes visible.
//

import Foundation

@MainActor
final class YavenProactiveScanController {

    private enum Constants {
        static let scanInterval: TimeInterval   = 30 * 60  // 30 min
        static let emailFetchLimit              = 20
        static let calendarLookAheadSeconds: TimeInterval = 24 * 60 * 60
        #if DEBUG
        static let workerBaseURL = "http://localhost:8787"
        #else
        static let workerBaseURL = "https://yaven-proxy.nickprice2000.workers.dev"
        #endif
    }

    private weak var agentController: YavenAgentController?
    private var lastScanDate: Date?
    private lazy var claudeAPI = ClaudeAPI(proxyURL: "\(Constants.workerBaseURL)/chat")

    init(agentController: YavenAgentController) {
        self.agentController = agentController
    }

    // MARK: - Public trigger

    /// Runs a scan only if the last one was more than 30 minutes ago.
    func scanIfStale() {
        if let last = lastScanDate, Date().timeIntervalSince(last) < Constants.scanInterval {
            return
        }
        Task { await scan() }
    }

    // MARK: - Scan

    private func scan() async {
        let entityId = YavenUserContext.shared.entityId
        guard !entityId.isEmpty else { return }

        agentController?.isScanningSuggestions = true
        defer { agentController?.isScanningSuggestions = false }

        // Fetch emails and calendar in parallel.
        async let emails = fetchEmails(entityId: entityId)
        async let events = fetchCalendarEvents(entityId: entityId)
        let (emailList, eventList) = await (emails, events)

        guard !emailList.isEmpty || !eventList.isEmpty else { return }

        guard let suggestions = await generateSuggestions(emails: emailList, events: eventList),
              !suggestions.isEmpty else { return }

        agentController?.proactiveSuggestions = suggestions
        lastScanDate = Date()
    }

    // MARK: - Data fetching

    private func fetchEmails(entityId: String) async -> [RecentEmail] {
        let client = GmailComposioClient(entityId: entityId)
        return (try? await client.listRecentEmails(limit: Constants.emailFetchLimit)) ?? []
    }

    private func fetchCalendarEvents(entityId: String) async -> [CalendarEvent] {
        let client = GoogleCalendarClient(entityId: entityId)
        let now = Date()
        let end = now.addingTimeInterval(Constants.calendarLookAheadSeconds)
        return (try? await client.listEvents(from: now, to: end)) ?? []
    }

    // MARK: - Claude classification

    private func generateSuggestions(
        emails: [RecentEmail],
        events: [CalendarEvent]
    ) async -> [YavenProactiveSuggestion]? {
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        let emailLines = emails.prefix(15).map { "- \($0.subject) from \($0.sender)" }.joined(separator: "\n")
        let eventLines = events.prefix(10).map { e in
            "- \(e.title) at \(timeFormatter.string(from: e.startDate))" +
            (e.attendeeEmails.isEmpty ? "" : " (\(e.attendeeEmails.count) attendees)")
        }.joined(separator: "\n")

        let userPrompt = """
        Recent inbox:
        \(emailLines.isEmpty ? "(no recent emails)" : emailLines)

        Upcoming calendar (next 24 h):
        \(eventLines.isEmpty ? "(no upcoming events)" : eventLines)

        User role: \(YavenUserContext.shared.role)
        """

        guard let responseText = try? await claudeAPI.sendTextRequest(
            systemPrompt: Self.systemPrompt,
            userPrompt: userPrompt,
            maxTokens: 1024
        ) else { return nil }

        return parseSuggestions(from: responseText)
    }

    private func parseSuggestions(from text: String) -> [YavenProactiveSuggestion]? {
        guard let range = text.range(of: #"\[[\s\S]*\]"#, options: .regularExpression) else { return nil }
        let jsonText = String(text[range])
        guard let data = jsonText.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
        else { return nil }

        return array.compactMap { item -> YavenProactiveSuggestion? in
            guard let title = item["title"], !title.isEmpty,
                  let raw = item["confidence"] else { return nil }
            let confidence: YavenProactiveSuggestion.Confidence
            switch raw {
            case "high":         confidence = .high
            case "needs_review": confidence = .needsReview
            default:             confidence = .low
            }
            return YavenProactiveSuggestion(title: title, confidence: confidence)
        }
    }

    // MARK: - System prompt

    private static let systemPrompt = """
    You are Yaven's proactive action detector. Given the user's recent emails and upcoming \
    calendar events, identify the most important concrete actions they should take right now.

    Rules:
    - Be specific: use names, companies, and topics from the actual data
    - 5–8 items maximum
    - Confidence levels:
        "high"         — clear action needed (meeting tomorrow, email needing a reply)
        "needs_review" — likely action but verify (possible follow-up, probable next step)
        "low"          — worth a look, uncertain (vague lead, ambiguous thread)

    Return ONLY a JSON array with no other text:
    [{"title": "Prep for Acme call at 2 pm", "confidence": "high"}, ...]
    """
}
