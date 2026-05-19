//
//  LogCallExtractionEngine.swift
//  leanring-buddy
//
//  Sends raw call content to the Worker /chat endpoint via SSE streaming,
//  collects the structured JSON response, and decodes it as SalesCallData.
//
//  The system prompt asks Claude to reply with a single JSON object that
//  matches SalesCallData exactly. Markdown fences are stripped before decode.
//

import Foundation

final class LogCallExtractionEngine {

    private let workerURL = URL(string: "http://localhost:8787/chat")!
    private let model = "claude-sonnet-4-6"

    // MARK: - System prompt

    private static let systemPrompt = """
    You are a sales call analyst. Extract structured data from the call content the user provides.

    Reply with ONLY a single valid JSON object — no markdown fences, no explanation, no extra text.

    The JSON must conform exactly to this schema:
    {
      "contactName": string | null,
      "contactEmail": string | null,
      "companyName": string | null,
      "dealName": string | null,
      "callSummary": string,
      "keyPoints": [string],
      "nextSteps": [string],
      "dealStage": string | null,
      "sentiment": "positive" | "neutral" | "negative",
      "callDate": "YYYY-MM-DD",
      "followUpSubject": string | null,
      "followUpBody": string | null
    }

    Rules:
    - callSummary must be 1–3 sentences.
    - keyPoints: up to 5 bullet points of the most important discussion items.
    - nextSteps: concrete action items agreed on during the call.
    - dealStage: one of "appointmentscheduled", "qualifiedtobuy", "presentationscheduled",
      "decisionmakerboughtin", "contractsent", "closedwon", "closedlost", or null.
    - followUpBody: plain-text draft body only — no HTML, no salutation needed.
    - callDate: today's date if not mentioned in the content.
    - If a field cannot be determined, use null (never omit the key).
    """

    // MARK: - Demo transcript

    static let demoTranscript = """
    Sales Call Notes — Acme Corp · 2026-05-18

    Participants: Sarah Chen (Acme, VP of Ops), me (Yaven BDR)

    Quick 25-min intro call. Sarah found us through the Y Combinator newsletter. Acme is a
    150-person logistics company currently using Salesforce but struggling with data entry
    overhead — their reps spend ~2 hrs/day on manual logging.

    Key discussion points:
    - Sarah liked the "auto-log from screen" demo clip I sent. Said it would eliminate their
      biggest pain point.
    - Budget is not yet approved — she needs to present a business case to her CFO, James Park.
    - Currently evaluating two other tools (she didn't name them).
    - Pilot timeline: ideally starting in July if procurement moves fast.
    - Data residency is a concern — needs confirmation that data stays in the US.

    Next steps:
    - Send Acme a one-pager on data residency / SOC 2 status by Friday.
    - Schedule a 45-min technical demo with Sarah + their head of engineering next week.
    - Follow up with James Park directly after Sarah's internal presentation (ETA: end of May).

    Feeling: positive. Sarah was engaged and asked detailed questions.
    Email: sarah.chen@acmecorp.io
    """

    // MARK: - Extract

    /// Sends `rawContent` to Claude and returns a decoded `SalesCallData`.
    /// Throws if the network call fails or the response is not valid JSON.
    func extract(from rawContent: String) async throws -> SalesCallData {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "stream": true,
            "system": Self.systemPrompt,
            "messages": [
                ["role": "user", "content": rawContent]
            ]
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: workerURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = 60

        let rawJSON = try await streamSSEResponse(request: request)
        return try decodeExtraction(rawJSON)
    }

    /// Reads visible call context from the user's current screen.
    func extractFromScreen(
        captures: [CompanionScreenCapture],
        context: YavenComputerContext
    ) async throws -> SalesCallData {
        let api = ClaudeAPI(proxyURL: workerURL.absoluteString, model: model)
        let result = try await api.analyzeImage(
            images: labeledImages(from: captures),
            systemPrompt: Self.systemPrompt,
            userPrompt: """
            Current computer context:
            \(context.promptSummary)

            Read the visible sales-call context from these screenshots. Look for call notes, a transcript, a LinkedIn profile, and any open CRM record. Extract the call logging data from what is visible.
            """,
            maxTokens: 1024
        )
        return try decodeExtraction(result.text)
    }

    private func labeledImages(from captures: [CompanionScreenCapture]) -> [(data: Data, label: String)] {
        captures.enumerated().map { index, capture in
            let dimensions = "screenshot pixels: \(capture.screenshotWidthInPixels)x\(capture.screenshotHeightInPixels), display points: \(capture.displayWidthInPoints)x\(capture.displayHeightInPoints)"
            return (
                data: capture.imageData,
                label: "\(capture.label). \(dimensions). Use screenIndex \(index) for this image."
            )
        }
    }

    // MARK: - SSE streaming

    private func streamSSEResponse(request: URLRequest) async throws -> String {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ExtractionError.httpError
        }

        var collectedText = ""

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }

            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String,
                  type == "content_block_delta",
                  let delta = json["delta"] as? [String: Any],
                  let text = delta["text"] as? String else {
                continue
            }

            collectedText += text
        }

        return collectedText
    }

    // MARK: - Decode

    private func decodeExtraction(_ raw: String) throws -> SalesCallData {
        // Strip optional markdown fences Claude might prepend/append.
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            if let jsonStart = cleaned.firstIndex(of: "{") {
                cleaned = String(cleaned[jsonStart...])
            }
            if let fence = cleaned.range(of: "\n```", options: .backwards) {
                cleaned = String(cleaned[..<fence.lowerBound])
            }
        }

        guard let data = cleaned.data(using: .utf8) else {
            throw ExtractionError.invalidJSON
        }

        let decoder = JSONDecoder()
        return try decoder.decode(SalesCallData.self, from: data)
    }
}

// MARK: - Errors

enum ExtractionError: LocalizedError {
    case httpError
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .httpError:   return "Worker returned an error. Is the local worker running?"
        case .invalidJSON: return "Claude returned an unexpected format — could not parse call data."
        }
    }
}
