//
//  MeetingExtractionEngine.swift
//  leanring-buddy
//
//  Sends a meeting transcript to Claude via the Worker /chat endpoint and
//  parses the structured JSON response into a MeetingExtraction.
//
//  Uses a non-streaming Anthropic Messages API call (stream omitted → false
//  by default). The Worker proxies the body as-is, so the response is a
//  standard Anthropic Messages API JSON envelope.
//

import Foundation

struct MeetingExtractionEngine {

    #if DEBUG
    private static let workerBaseURL = "http://localhost:8787"
    #else
    private static let workerBaseURL = "https://yaven-proxy.nickprice2000.workers.dev"
    #endif

    // MARK: - System prompt

    private static let systemPrompt = """
    You are a precise meeting extraction engine for a founder productivity tool.
    Extract structured data from meeting notes, a transcript, or screenshots of visible meeting notes and return ONLY a valid JSON object.
    No markdown fences, no explanation, no trailing text — just the JSON object.

    Required schema (all fields required, arrays may be empty):
    {
      "meetingTitle": "short descriptive title (≤ 60 chars)",
      "summary": "2-3 sentence executive summary",
      "attendees": ["Full Name (Role / Company)"],
      "decisions": ["concrete decision made during the meeting"],
      "keyTakeaways": ["key insight or strategic conclusion"],
      "actionItems": [
        { "owner": "Person Name", "task": "specific task description", "deadline": "human-readable string or null" }
      ],
      "openQuestions": ["unresolved question that needs follow-up"],
      "followUpNeeded": true,
      "followUpRecipient": "Primary external person to follow up with — first and last name, or null"
    }

    Rules:
    - deadline must be a plain-English string like "EOD Wednesday" or "next week", or null.
    - followUpRecipient is a name only (not an email address).
    - Return only the JSON object, starting with { and ending with }.
    """

    // MARK: - Public API

    /// Extracts structured meeting data from raw transcript text.
    static func extract(transcript: String) async throws -> MeetingExtraction {
        let url = URL(string: "\(workerBaseURL)/chat")!

        let body: [String: Any] = [
            "model": "claude-sonnet-4-6",
            "max_tokens": 1500,
            "system": systemPrompt,
            "messages": [
                [
                    "role": "user",
                    "content": "Extract meeting data from this transcript:\n\n\(transcript)"
                ]
            ]
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: req)

        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw MeetingPipelineError.extractionFailed("Worker HTTP \(statusCode)")
        }

        return try parseAnthropicResponse(data)
    }

    /// Extracts structured meeting data from the current screen context.
    static func extractFromScreen(
        captures: [CompanionScreenCapture],
        context: YavenComputerContext
    ) async throws -> MeetingExtraction {
        let api = ClaudeAPI(proxyURL: "\(workerBaseURL)/chat", model: "claude-sonnet-4-6")
        let result = try await api.analyzeImage(
            images: labeledImages(from: captures),
            systemPrompt: systemPrompt,
            userPrompt: """
            Current computer context:
            \(context.promptSummary)

            Read the visible meeting notes, transcript, or meeting-related page from these screenshots. Prefer Granola notes if visible. Extract the meeting data from what is on screen.
            """,
            maxTokens: 1500
        )
        return try parseExtractionJSON(result.text)
    }

    private static func labeledImages(from captures: [CompanionScreenCapture]) -> [(data: Data, label: String)] {
        captures.enumerated().map { index, capture in
            let dimensions = "screenshot pixels: \(capture.screenshotWidthInPixels)x\(capture.screenshotHeightInPixels), display points: \(capture.displayWidthInPoints)x\(capture.displayHeightInPoints)"
            return (
                data: capture.imageData,
                label: "\(capture.label). \(dimensions). Use screenIndex \(index) for this image."
            )
        }
    }

    // MARK: - Response parsing

    private static func parseAnthropicResponse(_ data: Data) throws -> MeetingExtraction {
        // Anthropic Messages API response shape:
        // { "content": [{ "type": "text", "text": "..." }], ... }
        guard
            let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content  = (envelope["content"] as? [[String: Any]])?.first(where: { $0["type"] as? String == "text" }),
            let rawText  = content["text"] as? String
        else {
            throw MeetingPipelineError.extractionFailed("Unexpected Claude response envelope")
        }

        return try parseExtractionJSON(rawText)
    }

    private static func parseExtractionJSON(_ raw: String) throws -> MeetingExtraction {
        // Strip accidental markdown fences that Claude occasionally adds.
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```",     with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            let jsonData = cleaned.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else {
            throw MeetingPipelineError.extractionFailed("Claude did not return valid JSON")
        }

        let rawItems = json["actionItems"] as? [[String: Any]] ?? []
        let actionItems = rawItems.map { item in
            MeetingActionItem(
                owner:    item["owner"]    as? String ?? "Team",
                task:     item["task"]     as? String ?? "",
                deadline: item["deadline"] as? String
            )
        }.filter { !$0.task.isEmpty }

        return MeetingExtraction(
            meetingTitle:      json["meetingTitle"]      as? String  ?? "Untitled Meeting",
            summary:           json["summary"]           as? String  ?? "",
            attendees:         json["attendees"]         as? [String] ?? [],
            decisions:         json["decisions"]         as? [String] ?? [],
            keyTakeaways:      json["keyTakeaways"]      as? [String] ?? [],
            actionItems:       actionItems,
            openQuestions:     json["openQuestions"]     as? [String] ?? [],
            followUpNeeded:    json["followUpNeeded"]    as? Bool    ?? false,
            followUpRecipient: json["followUpRecipient"] as? String
        )
    }
}
