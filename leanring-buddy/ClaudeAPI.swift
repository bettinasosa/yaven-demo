//
//  ClaudeAPI.swift
//  Claude API Implementation with streaming support
//

import Foundation

/// Claude API helper with streaming for progressive text display.
class ClaudeAPI {
    private static let tlsWarmupLock = NSLock()
    private static var hasStartedTLSWarmup = false

    private let apiURL: URL
    var model: String
    private let session: URLSession

    init(proxyURL: String, model: String = "claude-sonnet-4-6") {
        self.apiURL = URL(string: proxyURL)!
        self.model = model

        // Use .default instead of .ephemeral so TLS session tickets are cached.
        // Ephemeral sessions do a full TLS handshake on every request, which causes
        // transient -1200 (errSSLPeerHandshakeFail) errors with large image payloads.
        // Disable URL/cookie caching to avoid storing responses or credentials on disk.
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        config.urlCache = nil
        config.httpCookieStorage = nil
        self.session = URLSession(configuration: config)

        // Fire a lightweight HEAD request in the background to pre-establish the TLS
        // connection. This caches the TLS session ticket so the first real API call
        // (which carries a large image payload) doesn't need a cold TLS handshake.
        warmUpTLSConnectionIfNeeded()
    }

    private func makeAPIRequest() -> URLRequest {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    func sendTextWithScreenshotsStreaming(
        screenCaptures: [CompanionScreenCapture],
        computerContext: YavenComputerContext,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)] = [],
        userPrompt: String,
        onTextChunk: @MainActor @Sendable (String) -> Void
    ) async throws -> (text: String, duration: TimeInterval) {
        try await analyzeImageStreaming(
            images: labeledImages(from: screenCaptures),
            systemPrompt: Self.screenAwareChatSystemPrompt,
            conversationHistory: conversationHistory,
            userPrompt: """
            Current computer context:
            \(computerContext.promptSummary)

            User request:
            \(userPrompt)
            """,
            onTextChunk: onTextChunk
        )
    }

    func sendTextRequest(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int = 4096
    ) async throws -> String {
        let (responseText, _) = try await analyzeText(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            maxTokens: maxTokens
        )
        return responseText
    }

    func generateOperatorPlan(
        screenCaptures: [CompanionScreenCapture],
        computerContext: YavenComputerContext,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)] = [],
        userPrompt: String
    ) async throws -> YavenActionPlan {
        let (responseText, _) = try await analyzeImage(
            images: labeledImages(from: screenCaptures),
            systemPrompt: Self.operatorPlanSystemPrompt,
            conversationHistory: conversationHistory,
            userPrompt: """
            Current computer context:
            \(computerContext.promptSummary)

            User request:
            \(userPrompt)
            """,
            maxTokens: 2048
        )

        return try YavenActionPlanParser.decodePlan(from: responseText)
    }

    private func labeledImages(from screenCaptures: [CompanionScreenCapture]) -> [(data: Data, label: String)] {
        screenCaptures.enumerated().map { index, screenCapture in
            let coordinateGuidance = "Use screenIndex \(index) for this image. Click coordinates must be screenshot pixels with origin at the top-left of this image."
            let dimensions = "screenshot pixels: \(screenCapture.screenshotWidthInPixels)x\(screenCapture.screenshotHeightInPixels), display points: \(screenCapture.displayWidthInPoints)x\(screenCapture.displayHeightInPoints)"
            return (
                data: screenCapture.imageData,
                label: "\(screenCapture.label). \(dimensions). \(coordinateGuidance)"
            )
        }
    }

    func sendResearchStreaming(
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)] = [],
        userPrompt: String,
        onTextChunk: @MainActor @Sendable (String) -> Void
    ) async throws -> (text: String, duration: TimeInterval) {
        try await analyzeImageStreaming(
            images: [],
            systemPrompt: Self.researchSystemPrompt,
            conversationHistory: conversationHistory,
            userPrompt: userPrompt,
            onTextChunk: onTextChunk
        )
    }

    private static let screenAwareChatSystemPrompt = """
    You are Yaven, a calm macOS assistant. The user asks questions in a compact floating panel.

    Answer directly and concisely — panel space is limited. Use **bold** for key terms. Use numbered lists only for sequential steps. Keep paragraphs short. Use the screenshots, current app, and conversation history when relevant.

    If the user is asking a question or wants advice, answer it. If an action request reaches this chat path, explain what you would need to do and tell the user you can set up an approval plan if they confirm. Do not claim you have clicked, typed, sent, deleted, or changed anything unless an approved plan has been executed.
    """

    private static let researchSystemPrompt = """
    You are Yaven's research assistant. The user wants a thorough, well-structured response that will be saved as a formatted HTML document on their Desktop for later reference.

    Produce comprehensive, clearly organised content:
    - Use ## and ### headers to create logical sections
    - Use **bold** for key terms and important points
    - Use numbered lists for ranked items or sequential steps
    - Use bullet lists for parallel items
    - Use > blockquotes to highlight key quotes or insights
    - Use `code` for technical terms, commands, or identifiers

    Write as if producing a useful reference document — aim for depth and completeness, not a quick summary.
    """

    private static let operatorPlanSystemPrompt = """
    You are Yaven's macOS operator planner. When the user asks Yaven to do, open, switch, click, write, draft, edit, organize, or otherwise change something, produce the concrete approval plan needed to do it. Return only strict JSON. Do not use markdown. Do not include commentary outside JSON.

    You may propose these step types only:
    - activateApp: requires appName or bundleIdentifier
    - keyboardShortcut: requires key and optional modifiers such as command, option, control, shift
    - click: requires screenIndex, x, y. x/y are screenshot pixel coordinates using the target screenshot's top-left origin.
    - typeText: requires text. Use only for non-sensitive text.
    - pasteText: requires text. Prefer this for drafts and longer text.
    - wait: requires milliseconds
    - notify: requires message

    Never plan entering passwords, passcodes, security codes, payment details, or system security prompts. Never plan sending, deleting, purchasing, or scheduling without clearly showing the proposed draft/content and exact steps for approval. If the user asks to summarize after switching tabs or changing context, include a followUpPrompt that Yaven should run after execution.

    JSON schema:
    {
      "goal": "short user-visible goal",
      "targetAppName": "optional app name or null",
      "targetWindowTitle": "optional window title or null",
      "risk": "low|medium|high",
      "draftText": "optional draft text or null",
      "summary": "brief explanation of what will happen after approval",
      "followUpPrompt": "optional prompt to run after executing the steps or null",
      "steps": [
        {
          "type": "activateApp|keyboardShortcut|click|typeText|pasteText|wait|notify",
          "description": "human-readable step",
          "appName": "optional",
          "bundleIdentifier": "optional",
          "key": "optional",
          "modifiers": ["optional"],
          "screenIndex": 0,
          "x": 0,
          "y": 0,
          "text": "optional",
          "milliseconds": 300,
          "message": "optional"
        }
      ]
    }
    """

    /// Detects the MIME type of image data by inspecting the first bytes.
    /// Screen captures from ScreenCaptureKit are JPEG, but pasted images from the
    /// clipboard are PNG. The API rejects requests where the declared media_type
    /// doesn't match the actual image format.
    private func detectImageMediaType(for imageData: Data) -> String {
        // PNG files start with the 8-byte signature: 89 50 4E 47 0D 0A 1A 0A
        if imageData.count >= 4 {
            let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
            let firstFourBytes = [UInt8](imageData.prefix(4))
            if firstFourBytes == pngSignature {
                return "image/png"
            }
        }
        // Default to JPEG — screen captures use JPEG compression
        return "image/jpeg"
    }

    /// Sends a no-op HEAD request to the API host to establish and cache a TLS session.
    /// Failures are silently ignored — this is purely an optimization.
    private func warmUpTLSConnectionIfNeeded() {
        Self.tlsWarmupLock.lock()
        let shouldStartTLSWarmup = !Self.hasStartedTLSWarmup
        if shouldStartTLSWarmup {
            Self.hasStartedTLSWarmup = true
        }
        Self.tlsWarmupLock.unlock()

        guard shouldStartTLSWarmup else { return }

        guard var warmupURLComponents = URLComponents(url: apiURL, resolvingAgainstBaseURL: false) else {
            return
        }

        // The TLS session ticket is host-scoped, so warming the root host is enough.
        // Hitting the host instead of `/v1/messages` avoids extra endpoint-specific noise.
        warmupURLComponents.path = "/"
        warmupURLComponents.query = nil
        warmupURLComponents.fragment = nil

        guard let warmupURL = warmupURLComponents.url else {
            return
        }

        var warmupRequest = URLRequest(url: warmupURL)
        warmupRequest.httpMethod = "HEAD"
        warmupRequest.timeoutInterval = 10
        session.dataTask(with: warmupRequest) { _, _, _ in
            // Response doesn't matter — the TLS handshake is the goal
        }.resume()
    }

    /// Send a vision request to Claude with streaming.
    /// Calls `onTextChunk` on the main actor each time new text arrives so the UI updates progressively.
    /// Returns the full accumulated text and total duration when the stream completes.
    func analyzeImageStreaming(
        images: [(data: Data, label: String)],
        systemPrompt: String,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)] = [],
        userPrompt: String,
        onTextChunk: @MainActor @Sendable (String) -> Void
    ) async throws -> (text: String, duration: TimeInterval) {
        let startTime = Date()

        var request = makeAPIRequest()

        // Build messages array
        var messages: [[String: Any]] = []

        for (userPlaceholder, assistantResponse) in conversationHistory {
            messages.append(["role": "user", "content": userPlaceholder])
            messages.append(["role": "assistant", "content": assistantResponse])
        }

        // Build current message with all labeled images + prompt
        var contentBlocks: [[String: Any]] = []
        for image in images {
            contentBlocks.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": detectImageMediaType(for: image.data),
                    "data": image.data.base64EncodedString()
                ]
            ])
            contentBlocks.append([
                "type": "text",
                "text": image.label
            ])
        }
        contentBlocks.append([
            "type": "text",
            "text": userPrompt
        ])
        messages.append(["role": "user", "content": contentBlocks])

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "stream": true,
            "system": systemPrompt,
            "messages": messages
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = bodyData
        let payloadMB = Double(bodyData.count) / 1_048_576.0
        print("🌐 Claude streaming request: \(String(format: "%.1f", payloadMB))MB, \(images.count) image(s)")

        // Use bytes streaming for SSE (Server-Sent Events)
        let (byteStream, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "ClaudeAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"]
            )
        }

        // If non-2xx status, read the full body as error text
        guard (200...299).contains(httpResponse.statusCode) else {
            var errorBodyChunks: [String] = []
            for try await line in byteStream.lines {
                errorBodyChunks.append(line)
            }
            let errorBody = errorBodyChunks.joined(separator: "\n")
            throw NSError(
                domain: "ClaudeAPI",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "API Error (\(httpResponse.statusCode)): \(errorBody)"]
            )
        }

        // Parse SSE stream — each event is "data: {json}\n\n"
        var accumulatedResponseText = ""

        for try await line in byteStream.lines {
            // SSE lines look like: "data: {...}"
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6)) // Drop "data: " prefix

            // End of stream marker
            guard jsonString != "[DONE]" else { break }

            guard let jsonData = jsonString.data(using: .utf8),
                  let eventPayload = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let eventType = eventPayload["type"] as? String else {
                continue
            }

            // We care about content_block_delta events that contain text chunks
            if eventType == "content_block_delta",
               let delta = eventPayload["delta"] as? [String: Any],
               let deltaType = delta["type"] as? String,
               deltaType == "text_delta",
               let textChunk = delta["text"] as? String {
                accumulatedResponseText += textChunk
                // Send the accumulated text so far to the UI for progressive rendering
                let currentAccumulatedText = accumulatedResponseText
                await MainActor.run { onTextChunk(currentAccumulatedText) }
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        return (text: accumulatedResponseText, duration: duration)
    }

    func analyzeText(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int = 4096
    ) async throws -> (text: String, duration: TimeInterval) {
        let startTime = Date()

        var request = makeAPIRequest()
        let messages: [[String: Any]] = [
            ["role": "user", "content": userPrompt]
        ]

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": systemPrompt,
            "messages": messages
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = bodyData

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let responseString = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(
                domain: "ClaudeAPI",
                code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                userInfo: [NSLocalizedDescriptionKey: "API Error: \(responseString)"]
            )
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = json?["content"] as? [[String: Any]],
              let textBlock = content.first(where: { ($0["type"] as? String) == "text" }),
              let text = textBlock["text"] as? String else {
            throw NSError(
                domain: "ClaudeAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid response format"]
            )
        }

        let duration = Date().timeIntervalSince(startTime)
        return (text: text, duration: duration)
    }

    /// Non-streaming fallback for validation requests where we don't need progressive display.
    func analyzeImage(
        images: [(data: Data, label: String)],
        systemPrompt: String,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)] = [],
        userPrompt: String,
        maxTokens: Int = 256
    ) async throws -> (text: String, duration: TimeInterval) {
        let startTime = Date()

        var request = makeAPIRequest()

        var messages: [[String: Any]] = []
        for (userPlaceholder, assistantResponse) in conversationHistory {
            messages.append(["role": "user", "content": userPlaceholder])
            messages.append(["role": "assistant", "content": assistantResponse])
        }

        // Build current message with all labeled images + prompt
        var contentBlocks: [[String: Any]] = []
        for image in images {
            contentBlocks.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": detectImageMediaType(for: image.data),
                    "data": image.data.base64EncodedString()
                ]
            ])
            contentBlocks.append([
                "type": "text",
                "text": image.label
            ])
        }
        contentBlocks.append([
            "type": "text",
            "text": userPrompt
        ])
        messages.append(["role": "user", "content": contentBlocks])

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": systemPrompt,
            "messages": messages
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = bodyData
        let payloadMB = Double(bodyData.count) / 1_048_576.0
        print("🌐 Claude request: \(String(format: "%.1f", payloadMB))MB, \(images.count) image(s)")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let responseString = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(
                domain: "ClaudeAPI",
                code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                userInfo: [NSLocalizedDescriptionKey: "API Error: \(responseString)"]
            )
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = json?["content"] as? [[String: Any]],
              let textBlock = content.first(where: { ($0["type"] as? String) == "text" }),
              let text = textBlock["text"] as? String else {
            throw NSError(
                domain: "ClaudeAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid response format"]
            )
        }

        let duration = Date().timeIntervalSince(startTime)
        return (text: text, duration: duration)
    }
}
