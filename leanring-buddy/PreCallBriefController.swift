//
//  PreCallBriefController.swift
//  leanring-buddy
//
//  Generates a 3-bullet pre-call brief from whatever context is available
//  (HubSpot notes, Granola history, user profile) and surfaces it as a
//  floating post-it window.
//

import Combine
import Foundation

@MainActor
final class PreCallBriefController: ObservableObject {

    static let shared = PreCallBriefController()

    #if DEBUG
    private let workerBaseURL = "http://localhost:8787"
    #else
    private let workerBaseURL = "https://yaven-proxy.nickprice2000.workers.dev"
    #endif

    @Published var lastBrief: PreCallBrief?
    @Published var isGenerating: Bool = false

    private var briefWindow: PreCallBriefWindow?
    private var activeBriefEventID: String?

    private init() {}

    // MARK: - Entry Point

    func generateBrief(for event: CalendarEvent) {
        guard activeBriefEventID != event.id else { return }
        activeBriefEventID = event.id
        isGenerating = true

        Task {
            let brief = await fetchBrief(for: event)
            isGenerating = false
            showBrief(brief, event: event)
        }
    }

    /// Generates a brief for a dummy upcoming call — useful for testing without a real calendar event.
    func testNow() {
        let testEvent = CalendarEvent(
            id: "test-\(Date().timeIntervalSince1970)",
            title: "Test Call",
            startDate: Date().addingTimeInterval(5 * 60),
            endDate: Date().addingTimeInterval(35 * 60),
            attendeeEmails: ["prospect@example.com"],
            meetLink: nil
        )
        activeBriefEventID = nil
        generateBrief(for: testEvent)
    }

    // MARK: - Generation

    private func fetchBrief(for event: CalendarEvent) async -> PreCallBrief {
        let prospectEmail = event.attendeeEmails.first ?? ""
        let prospectName = displayName(from: prospectEmail)
        let userRole = YavenUserContext.shared.role

        // Future: fetch HubSpot contact notes + Granola past meetings here.
        // For now we use the calendar event + user role to generate a useful brief.
        let context = buildContext(event: event, prospectEmail: prospectEmail, userRole: userRole)

        if let claudeBrief = try? await callClaude(context: context, event: event) {
            return claudeBrief
        }

        return PreCallBrief(
            prospectName: prospectName,
            company: company(from: prospectEmail),
            minutesUntilCall: Int(event.startDate.timeIntervalSinceNow / 60),
            rapport: "Review recent activity before the call.",
            painPoint: "Understand their current workflow challenges.",
            likelyObjection: "Be ready to address timing or budget concerns.",
            eventTitle: event.title
        )
    }

    private func buildContext(event: CalendarEvent, prospectEmail: String, userRole: String) -> String {
        var parts: [String] = []
        parts.append("Meeting title: \(event.title)")
        parts.append("Attendee email: \(prospectEmail)")
        let mins = Int(event.startDate.timeIntervalSinceNow / 60)
        parts.append("Starts in: \(mins) minutes")
        if !userRole.isEmpty { parts.append("User's role: \(userRole)") }
        let profile = YavenStorage.readProfileText() ?? ""
        if !profile.isEmpty { parts.append("User context:\n\(profile)") }
        return parts.joined(separator: "\n")
    }

    private func callClaude(context: String, event: CalendarEvent) async throws -> PreCallBrief {
        guard let url = URL(string: "\(workerBaseURL)/chat") else { throw URLError(.badURL) }

        let prospectEmail = event.attendeeEmails.first ?? ""
        let system = """
        You are Yaven, a pre-call research assistant. Generate a concise 3-bullet pre-call brief.
        Return ONLY valid JSON, no markdown, no commentary.

        JSON schema:
        {
          "prospectName": "first name or full name",
          "company": "company name inferred from email domain or meeting title",
          "rapport": "one sentence: something specific to reference to build connection",
          "painPoint": "one sentence: the most likely pain to lead with",
          "likelyObjection": "one sentence: most probable pushback and how to address it"
        }
        """

        let userMessage = "Generate a pre-call brief using this context:\n\(context)"
        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 400,
            "system": system,
            "messages": [["role": "user", "content": userMessage]],
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = json?["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String,
              let jsonData = text.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else { throw URLError(.cannotParseResponse) }

        return PreCallBrief(
            prospectName: parsed["prospectName"] as? String ?? displayName(from: prospectEmail),
            company: parsed["company"] as? String ?? company(from: prospectEmail),
            minutesUntilCall: Int(event.startDate.timeIntervalSinceNow / 60),
            rapport: parsed["rapport"] as? String ?? "",
            painPoint: parsed["painPoint"] as? String ?? "",
            likelyObjection: parsed["likelyObjection"] as? String ?? "",
            eventTitle: event.title
        )
    }

    // MARK: - Display

    private func showBrief(_ brief: PreCallBrief, event: CalendarEvent) {
        lastBrief = brief
        briefWindow?.close()
        let window = PreCallBriefWindow(brief: brief)
        window.show()
        briefWindow = window

        // Auto-dismiss 10 minutes after call start.
        let delay = max(event.startDate.timeIntervalSinceNow + 10 * 60, 30)
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            await MainActor.run { self.briefWindow?.close() }
        }
    }

    func dismissBrief() {
        briefWindow?.close()
        briefWindow = nil
        activeBriefEventID = nil
    }

    // MARK: - Helpers

    private func displayName(from email: String) -> String {
        let local = email.components(separatedBy: "@").first ?? email
        return local.split(separator: ".").map { $0.capitalized }.joined(separator: " ")
    }

    private func company(from email: String) -> String {
        guard let domain = email.components(separatedBy: "@").last else { return "" }
        let parts = domain.components(separatedBy: ".")
        return parts.dropLast().last?.capitalized ?? domain
    }
}

// MARK: - Model

struct PreCallBrief {
    let prospectName: String
    let company: String
    let minutesUntilCall: Int
    let rapport: String
    let painPoint: String
    let likelyObjection: String
    let eventTitle: String
}
