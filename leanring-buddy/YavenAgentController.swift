//
//  YavenAgentController.swift
//  leanring-buddy
//

import AppKit
import Combine
import Foundation

@MainActor
final class YavenAgentController: ObservableObject {
    private enum Constants {
        static let workerChatURL = "http://localhost:8787/chat"
        static let fixedPanelHeight: CGFloat = 420
        static let conversationHistoryLimit = 8
        static let persistedChatMessagesKey = "com.yaven.chatMessages"
        static let persistedChatMessagesLimit = 30
        static let legacyDefaultsSuiteNames = [
            "com.humansongs.clicky",
            "com.yourcompany.leanring-buddy"
        ]
    }

    @Published private(set) var state: YavenAgentState = .idle {
        didSet { updatePreferredPanelHeight() }
    }
    @Published private(set) var responseText = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var currentPlan: YavenActionPlan?
    @Published private(set) var executionResult: YavenExecutionResult?
    @Published private(set) var preferredPanelHeight = Constants.fixedPanelHeight
    @Published private(set) var chatMessages: [YavenChatMessage] = []
    @Published private(set) var threads: [YavenThreadSummary] = []
    @Published private(set) var selectedThreadID: UUID?
    @Published private(set) var selectedApproval: YavenApprovalRequest?
    @Published var isActivityInboxVisible = false
    @Published var proactiveSuggestions: [YavenProactiveSuggestion] = []
    @Published var isScanningSuggestions = false

    private let store: YavenThreadStore
    private let taskRunner: YavenTaskRunner
    private let notificationManager = YavenNotificationManager()
    private lazy var proactiveScanController = YavenProactiveScanController(agentController: self)
    private lazy var claudeAPI = ClaudeAPI(proxyURL: Constants.workerChatURL)
    private let skillRegistry = YavenSkillRegistry.shared
    private let gateway = YavenGateway()
    private var taskRunnerCancellable: AnyCancellable?
    private var lastContextByThreadID: [UUID: YavenComputerContext] = [:]
    private var isPanelVisible = false

    init(
        store: YavenThreadStore? = nil,
        taskRunner: YavenTaskRunner? = nil
    ) {
        let resolvedStore = store ?? .shared
        self.store = resolvedStore
        self.taskRunner = taskRunner ?? YavenTaskRunner(store: resolvedStore)
        migrateLegacyChatMessagesIfNeeded()
        refreshThreads()
        selectThread(threads.first?.id)
        updatePreferredPanelHeight()

        taskRunnerCancellable = self.taskRunner.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.refreshThreads()
            }
        }
    }

    var isWorking: Bool {
        !taskRunner.activeThreads.isEmpty ||
        state == .thinking ||
        state == .answering ||
        state == .planning ||
        state == .executing
    }

    var needsApprovalThreads: [YavenThreadSummary] {
        threads.filter { $0.status == .approvalRequired }
    }

    var runningThreads: [YavenThreadSummary] {
        threads.filter { $0.status == .running || $0.status == .queued }
    }

    var recentThreads: [YavenThreadSummary] {
        threads.filter { thread in
            thread.status != .approvalRequired &&
            thread.status != .running &&
            thread.status != .queued
        }
    }

    func setPanelVisible(_ isPanelVisible: Bool) {
        self.isPanelVisible = isPanelVisible
        if isPanelVisible {
            proactiveScanController.scanIfStale()
        }
    }

    func submit(_ command: String) {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else { return }

        if selectedApproval != nil, gateway.isApprovalCommand(trimmedCommand) {
            approveCurrentPlan()
            return
        }

        if selectedApproval != nil, gateway.isCancelCommand(trimmedCommand) {
            cancelCurrentPlan()
            return
        }

        startThread(for: trimmedCommand)
    }

    func selectThread(_ threadID: UUID?) {
        selectedThreadID = threadID
        refreshSelectedThreadState()
        isActivityInboxVisible = threadID == nil
    }

    func showActivityInbox() {
        isActivityInboxVisible = true
        selectedThreadID = nil
        refreshSelectedThreadState()
    }

    func approveCurrentPlan() {
        guard let selectedApproval else { return }

        do {
            var approval = selectedApproval
            approval.status = .approved
            approval.resolvedAt = Date()
            try store.saveApproval(approval)
            try store.updateThread(
                id: approval.threadID,
                status: .running,
                lastPreview: "Approved. Running now.",
                requiresAttention: false
            )

            selectThread(approval.threadID)
            switch approval.kind {
            case .operatorPlan:
                let payload = try decodeOperatorApprovalPayload(from: approval)
                taskRunner.approve(approval.threadID) { [weak self] threadID in
                    await self?.execute(plan: payload.plan, context: payload.context, threadID: threadID)
                }
            case .crmSkill:
                let plan = try decodeCRMApprovalPayload(from: approval)
                taskRunner.approve(approval.threadID) { [weak self] threadID in
                    await self?.executeCRMPlan(plan, threadID: threadID)
                }
            case .mailCleanup:
                let plan = try decodeMailCleanupApprovalPayload(from: approval)
                taskRunner.approve(approval.threadID) { [weak self] threadID in
                    await self?.executeMailCleanupPlan(plan, threadID: threadID)
                }
            }
        } catch {
            presentError(error.localizedDescription, threadID: selectedApproval.threadID)
        }
    }

    func cancelCurrentPlan() {
        guard let selectedApproval else { return }
        do {
            var approval = selectedApproval
            approval.status = .rejected
            approval.resolvedAt = Date()
            try store.saveApproval(approval)
            try store.updateThread(
                id: approval.threadID,
                status: .cancelled,
                lastPreview: "Plan cancelled.",
                requiresAttention: false
            )
            executionResult = .failure("Plan cancelled.")
            state = .idle
            refreshThreads()
            refreshSelectedThreadState()
        } catch {
            presentError(error.localizedDescription, threadID: selectedApproval.threadID)
        }
    }

    func requestScreenRecordingPermission() {
        WindowPositionManager.requestScreenRecordingPermission()
    }

    func requestAccessibilityPermission() {
        WindowPositionManager.requestAccessibilityPermission()
    }

    func cancelAndReset() {
        // Panel dismissal no longer cancels background threads.
        responseText = ""
        errorMessage = nil
        executionResult = nil
        state = .idle
    }

    func clearChatMemory() {
        responseText = ""
        errorMessage = nil
        currentPlan = nil
        executionResult = nil
        selectedApproval = nil
        selectedThreadID = nil
        chatMessages = []
        isActivityInboxVisible = false
        state = .idle
        updatePreferredPanelHeight()
    }

    func cancelSelectedThread() {
        guard let selectedThreadID else { return }
        taskRunner.cancel(selectedThreadID)
        refreshThreads()
        refreshSelectedThreadState()
    }

    private func startThread(for command: String) {
        do {
            let route = gateway.route(command: command)
            let thread = try store.createThread(
                kind: route.threadKind,
                title: route.title,
                status: .running,
                source: "gateway.\(route.intent.rawValue)"
            )
            selectedThreadID = thread.id
            isActivityInboxVisible = false
            responseText = ""
            errorMessage = nil
            currentPlan = nil
            executionResult = nil

            _ = try store.appendMessage(
                threadID: thread.id,
                role: .user,
                text: command
            )
            refreshThreads()
            refreshSelectedThreadState()

            taskRunner.startExistingThread(thread.id) { [weak self] threadID in
                await self?.handleSubmit(command, route: route, threadID: threadID)
            }
        } catch {
            presentError(error.localizedDescription, threadID: selectedThreadID)
        }
    }

    private func handleSubmit(_ command: String, route: YavenGatewayRoute, threadID: UUID) async {
        if let blockedMessage = gateway.blockedSensitiveActionMessage(for: command) {
            presentError(blockedMessage, threadID: threadID)
            return
        }

        if route.intent == .directOpen, let openTarget = route.openTarget {
            runDirectOpenCommand(openTarget, threadID: threadID)
            return
        }

        do {
            if route.intent == .mailCleanup {
                try await generateMailCleanupPlan(command: command, threadID: threadID)
                return
            }

            if route.intent == .research {
                try await streamResearch(command: command, threadID: threadID)
                return
            }

            try store.appendCheckpoint(
                threadID: threadID,
                stepIndex: 1,
                status: .running,
                state: ["phase": "capturing_context"]
            )
            let (captures, context) = try await captureComputerContext(threadID: threadID)
            lastContextByThreadID[threadID] = context

            switch route.intent {
            case .crmUpdate:
                try await generateCRMPlan(
                    command: command,
                    context: context,
                    threadID: threadID
                )
            case .operatorPlan:
                try await generatePlan(
                    command: command,
                    captures: captures,
                    context: context,
                    threadID: threadID
                )
            case .chat:
                try await streamAnswer(
                    command: command,
                    captures: captures,
                    context: context,
                    threadID: threadID
                )
            case .directOpen, .mailCleanup, .research:
                return
            }
        } catch is CancellationError {
            markThreadCancelled(threadID)
        } catch {
            presentError(error.localizedDescription, threadID: threadID)
        }
    }

    private func captureComputerContext(
        threadID: UUID
    ) async throws -> ([CompanionScreenCapture], YavenComputerContext) {
        state = .thinking

        guard WindowPositionManager.hasScreenRecordingPermission() else {
            WindowPositionManager.requestScreenRecordingPermission()
            throw NSError(domain: "YavenAgentController", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Screen Recording permission is required so Yaven can see your current context."
            ])
        }

        let captures = try await CompanionScreenCaptureUtility.captureAllScreensAsJPEG()
        let context = YavenComputerContextProvider.makeContext(from: captures)
        try store.appendCheckpoint(
            threadID: threadID,
            stepIndex: 2,
            status: .running,
            state: context
        )
        return (captures, context)
    }

    private func streamResearch(command: String, threadID: UUID) async throws {
        state = .answering
        let assistantMessage = try store.appendMessage(threadID: threadID, role: .assistant, text: "")
        refreshSelectedThreadState()

        let (fullResponse, _) = try await claudeAPI.sendResearchStreaming(
            conversationHistory: conversationHistory(for: threadID),
            userPrompt: command,
            onTextChunk: { [weak self] accumulatedResponse in
                guard let self else { return }
                self.responseText = accumulatedResponse
                self.updateAssistantMessage(
                    assistantMessage,
                    text: accumulatedResponse,
                    threadID: threadID,
                    shouldUpdateThreadPreview: false
                )
            }
        )

        guard !Task.isCancelled else { return }
        responseText = fullResponse
        updateAssistantMessage(
            assistantMessage,
            text: fullResponse,
            threadID: threadID,
            shouldUpdateThreadPreview: true
        )

        // Save a formatted HTML artifact to the Desktop and open it
        let artifactMessage: String
        if let filename = saveResearchArtifact(title: command, markdownContent: fullResponse) {
            artifactMessage = "Artifact saved to Desktop as \"\(filename)\"."
        } else {
            artifactMessage = "Research complete."
        }

        try store.appendCheckpoint(
            threadID: threadID,
            stepIndex: 3,
            status: .completed,
            state: ["phase": "research_complete"]
        )
        try store.updateThread(
            id: threadID,
            status: .completed,
            lastPreview: fullResponse,
            requiresAttention: false
        )
        _ = try store.appendMessage(threadID: threadID, role: .assistant, text: artifactMessage)
        state = .done
        refreshThreads()
        refreshSelectedThreadState()

        if !isPanelVisible {
            await notificationManager.send(
                title: "Yaven research complete",
                body: artifactMessage,
                threadID: threadID
            )
        }
    }

    @discardableResult
    private func saveResearchArtifact(title: String, markdownContent: String) -> String? {
        let sanitizedTitle = String(title.prefix(50))
            .replacingOccurrences(of: #"[^a-zA-Z0-9 \-]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm"
        let timestamp = formatter.string(from: Date())
        let displayTimestamp = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
        let filename = "Yaven - \(sanitizedTitle.isEmpty ? "Research" : sanitizedTitle) - \(timestamp).html"

        let html = makeArtifactHTML(title: title, content: markdownContent, timestamp: displayTimestamp)

        guard let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else {
            return nil
        }
        let fileURL = desktopURL.appendingPathComponent(filename)
        do {
            try html.write(to: fileURL, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(fileURL)
            return filename
        } catch {
            print("YavenAgentController: could not save research artifact: \(error)")
            return nil
        }
    }

    private func makeArtifactHTML(title: String, content: String, timestamp: String) -> String {
        let htmlBody = markdownToHTML(content)
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Yaven — \(escapeHTML(title))</title>
        <style>
        :root {
          --bg: #1a1208; --surface: #241a0e;
          --border: rgba(245,192,96,0.15); --text: #f0e6d0;
          --muted: #a89070; --accent: #f5c060; --code-bg: rgba(245,192,96,0.08);
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { background: var(--bg); color: var(--text); font-family: -apple-system,"Helvetica Neue",sans-serif; font-size: 15px; line-height: 1.75; padding: 48px 24px; }
        .container { max-width: 740px; margin: 0 auto; }
        .header { border-bottom: 1px solid var(--border); padding-bottom: 20px; margin-bottom: 32px; }
        .label { font-size: 11px; letter-spacing: 0.12em; text-transform: uppercase; color: var(--accent); margin-bottom: 8px; }
        h1.title { font-size: 26px; font-weight: 600; letter-spacing: -0.02em; }
        .meta { font-size: 12px; color: var(--muted); margin-top: 6px; }
        .content h1,.content h2,.content h3 { color: var(--accent); margin-top: 28px; margin-bottom: 10px; letter-spacing: -0.02em; }
        .content h1 { font-size: 22px; } .content h2 { font-size: 19px; } .content h3 { font-size: 16px; font-weight: 600; }
        .content p { margin-bottom: 14px; }
        .content ul,.content ol { margin: 10px 0 14px 22px; }
        .content li { margin-bottom: 6px; }
        .content strong { color: var(--accent); font-weight: 600; }
        .content em { font-style: italic; }
        .content code { background: var(--code-bg); border: 1px solid var(--border); border-radius: 4px; padding: 1px 6px; font-family: "SF Mono",Menlo,monospace; font-size: 13px; color: var(--accent); }
        .content pre { background: var(--code-bg); border: 1px solid var(--border); border-radius: 8px; padding: 16px; overflow-x: auto; margin: 14px 0; }
        .content pre code { background: none; border: none; padding: 0; }
        .content blockquote { border-left: 3px solid var(--accent); padding-left: 16px; color: var(--muted); margin: 14px 0; }
        .content a { color: var(--accent); }
        .content hr { border: none; border-top: 1px solid var(--border); margin: 24px 0; }
        .footer { margin-top: 48px; padding-top: 20px; border-top: 1px solid var(--border); font-size: 12px; color: var(--muted); }
        </style>
        </head>
        <body>
        <div class="container">
          <div class="header">
            <div class="label">Yaven Research</div>
            <h1 class="title">\(escapeHTML(title))</h1>
            <div class="meta">Generated \(escapeHTML(timestamp))</div>
          </div>
          <div class="content">\(htmlBody)</div>
          <div class="footer">Generated by Yaven · Saved to Desktop</div>
        </div>
        </body>
        </html>
        """
    }

    private func markdownToHTML(_ markdown: String) -> String {
        var html = ""
        let lines = markdown.components(separatedBy: "\n")
        var inCodeBlock = false
        var codeBlockLines: [String] = []
        var inUnorderedList = false
        var inOrderedList = false

        func closeLists() {
            if inUnorderedList { html += "</ul>\n"; inUnorderedList = false }
            if inOrderedList { html += "</ol>\n"; inOrderedList = false }
        }

        for line in lines {
            if line.hasPrefix("```") {
                if inCodeBlock {
                    html += "<pre><code>\(escapeHTML(codeBlockLines.joined(separator: "\n")))</code></pre>\n"
                    codeBlockLines = []
                    inCodeBlock = false
                } else {
                    closeLists()
                    inCodeBlock = true
                }
                continue
            }
            if inCodeBlock { codeBlockLines.append(line); continue }

            if line.hasPrefix("### ") {
                closeLists()
                html += "<h3>\(inlineMarkdown(String(line.dropFirst(4))))</h3>\n"
            } else if line.hasPrefix("## ") {
                closeLists()
                html += "<h2>\(inlineMarkdown(String(line.dropFirst(3))))</h2>\n"
            } else if line.hasPrefix("# ") {
                closeLists()
                html += "<h1>\(inlineMarkdown(String(line.dropFirst(2))))</h1>\n"
            } else if line == "---" || line == "***" || line == "___" {
                closeLists()
                html += "<hr>\n"
            } else if line.hasPrefix("> ") {
                closeLists()
                html += "<blockquote><p>\(inlineMarkdown(String(line.dropFirst(2))))</p></blockquote>\n"
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                if inOrderedList { html += "</ol>\n"; inOrderedList = false }
                if !inUnorderedList { html += "<ul>\n"; inUnorderedList = true }
                html += "<li>\(inlineMarkdown(String(line.dropFirst(2))))</li>\n"
            } else if let content = orderedListItem(from: line) {
                if inUnorderedList { html += "</ul>\n"; inUnorderedList = false }
                if !inOrderedList { html += "<ol>\n"; inOrderedList = true }
                html += "<li>\(inlineMarkdown(content))</li>\n"
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                closeLists()
                html += "\n"
            } else {
                closeLists()
                html += "<p>\(inlineMarkdown(line))</p>\n"
            }
        }

        closeLists()
        if inCodeBlock {
            html += "<pre><code>\(escapeHTML(codeBlockLines.joined(separator: "\n")))</code></pre>\n"
        }
        return html
    }

    private func orderedListItem(from line: String) -> String? {
        guard let dotIndex = line.firstIndex(of: ".") else { return nil }
        let numberPart = line[..<dotIndex]
        guard !numberPart.isEmpty, numberPart.allSatisfy({ $0.isNumber }) else { return nil }
        let afterDot = line[line.index(after: dotIndex)...]
        guard afterDot.hasPrefix(" ") else { return nil }
        return String(afterDot.dropFirst())
    }

    private func inlineMarkdown(_ text: String) -> String {
        var result = escapeHTML(text)
        // Bold before italic to avoid consuming the markers
        result = result.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
        result = result.replacingOccurrences(of: #"__(.+?)__"#, with: "<strong>$1</strong>", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\*(.+?)\*"#, with: "<em>$1</em>", options: .regularExpression)
        result = result.replacingOccurrences(of: #"_(.+?)_"#, with: "<em>$1</em>", options: .regularExpression)
        result = result.replacingOccurrences(of: #"`(.+?)`"#, with: "<code>$1</code>", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\[(.+?)\]\((.+?)\)"#, with: "<a href=\"$2\" target=\"_blank\">$1</a>", options: .regularExpression)
        return result
    }

    private func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func streamAnswer(
        command: String,
        captures: [CompanionScreenCapture],
        context: YavenComputerContext,
        threadID: UUID
    ) async throws {
        state = .answering
        let assistantMessage = try store.appendMessage(threadID: threadID, role: .assistant, text: "")
        refreshSelectedThreadState()

        let (fullResponse, _) = try await claudeAPI.sendTextWithScreenshotsStreaming(
            screenCaptures: captures,
            computerContext: context,
            conversationHistory: conversationHistory(for: threadID),
            userPrompt: command,
            onTextChunk: { [weak self] accumulatedResponse in
                guard let self else { return }
                self.responseText = accumulatedResponse
                self.updateAssistantMessage(
                    assistantMessage,
                    text: accumulatedResponse,
                    threadID: threadID,
                    shouldUpdateThreadPreview: false
                )
            }
        )

        guard !Task.isCancelled else { return }
        responseText = fullResponse
        updateAssistantMessage(
            assistantMessage,
            text: fullResponse,
            threadID: threadID,
            shouldUpdateThreadPreview: true
        )
        try store.appendCheckpoint(
            threadID: threadID,
            stepIndex: 3,
            status: .completed,
            state: ["phase": "answered"]
        )
        try store.updateThread(
            id: threadID,
            status: .completed,
            lastPreview: fullResponse,
            requiresAttention: false
        )
        state = .idle
        refreshThreads()
        refreshSelectedThreadState()
    }

    private func generatePlan(
        command: String,
        captures: [CompanionScreenCapture],
        context: YavenComputerContext,
        threadID: UUID
    ) async throws {
        state = .planning

        let plan = try await claudeAPI.generateOperatorPlan(
            screenCaptures: captures,
            computerContext: context,
            conversationHistory: conversationHistory(for: threadID),
            userPrompt: command
        )

        try gateway.validate(plan: plan, context: context)
        guard !Task.isCancelled else { return }

        if gateway.shouldExecuteWithoutApproval(plan: plan, command: command) {
            let autoExecuteMessage = "I'll do that now: \(plan.goal)"
            _ = try store.appendMessage(
                threadID: threadID,
                role: .assistant,
                text: autoExecuteMessage
            )
            refreshSelectedThreadState()
            await execute(plan: plan, context: context, threadID: threadID)
            return
        }

        let approval = try makeOperatorApproval(
            threadID: threadID,
            plan: plan,
            context: context
        )
        try store.saveApproval(approval)
        try store.appendCheckpoint(
            threadID: threadID,
            stepIndex: 4,
            status: .approvalRequired,
            state: approval
        )
        try store.updateThread(
            id: threadID,
            status: .approvalRequired,
            lastPreview: plan.summary,
            requiresAttention: true
        )

        _ = try store.appendMessage(
            threadID: threadID,
            role: .assistant,
            text: "I prepared an approval plan: \(plan.goal)"
        )
        currentPlan = plan
        state = .approvalRequired
        refreshThreads()
        refreshSelectedThreadState()

        if !isPanelVisible {
            await notificationManager.send(
                title: "Yaven needs approval",
                body: plan.goal,
                threadID: threadID
            )
        }
    }

    private func generateCRMPlan(
        command: String,
        context: YavenComputerContext,
        threadID: UUID
    ) async throws {
        state = .planning

        let response = try await claudeAPI.sendTextRequest(
            systemPrompt: Self.crmPlanSystemPrompt,
            userPrompt: """
            Current computer context:
            \(context.promptSummary)

            User request:
            \(command)
            """
        )
        let plan = try decodeCRMPlan(from: response)
        guard !plan.actions.isEmpty else {
            throw validationError("Claude returned a CRM plan with no proposed updates.")
        }

        let approval = try makeCRMApproval(threadID: threadID, plan: plan)
        try store.saveApproval(approval)
        try store.appendCheckpoint(
            threadID: threadID,
            stepIndex: 4,
            status: .approvalRequired,
            state: approval
        )
        try store.updateThread(
            id: threadID,
            status: .approvalRequired,
            lastPreview: plan.summary,
            requiresAttention: true
        )

        _ = try store.appendMessage(
            threadID: threadID,
            role: .assistant,
            text: "I prepared HubSpot updates for approval: \(plan.goal)"
        )
        state = .approvalRequired
        refreshThreads()
        refreshSelectedThreadState()

        if !isPanelVisible {
            await notificationManager.send(
                title: "HubSpot updates need approval",
                body: plan.goal,
                threadID: threadID
            )
        }
    }

    private func generateMailCleanupPlan(command: String, threadID: UUID) async throws {
        state = .planning
        try store.appendCheckpoint(
            threadID: threadID,
            stepIndex: 1,
            status: .running,
            state: ["phase": "reading_mail"]
        )

        _ = try store.appendMessage(
            threadID: threadID,
            role: .assistant,
            text: "I'll scan your recent Mail inbox messages and show you a cleanup plan before changing anything."
        )
        refreshSelectedThreadState()

        let emailsJSON = try skillRegistry.run(name: "list_recent_emails", input: [:])
        let emails = try JSONDecoder().decode([RecentEmail].self, from: emailsJSON.data(using: .utf8) ?? Data())
        guard !emails.isEmpty else {
            finishThread(threadID, message: "I could not find recent messages in Apple Mail. Open Mail, make sure your inbox is loaded, then ask me again.")
            return
        }

        let planResponse = try await claudeAPI.sendTextRequest(
            systemPrompt: Self.cleanupSystemPrompt,
            userPrompt: Self.cleanupUserPrompt(emails: emails)
        )

        _ = try skillRegistry.run(name: "propose_cleanup_plan", input: [:])

        let cleanupPlan = try YavenCleanupPlanParser.decodePlan(
            from: planResponse,
            totalReviewed: min(emails.count, 200)
        )
        let approvalPlan = YavenMailCleanupApprovalPlan(
            cleanupPlan: cleanupPlan,
            emails: emails
        )
        let approval = try makeMailCleanupApproval(threadID: threadID, plan: approvalPlan)

        try store.saveApproval(approval)
        try store.appendCheckpoint(
            threadID: threadID,
            stepIndex: 2,
            status: .approvalRequired,
            state: approval
        )
        try store.updateThread(
            id: threadID,
            status: .approvalRequired,
            lastPreview: approval.summary,
            requiresAttention: true
        )

        _ = try store.appendMessage(
            threadID: threadID,
            role: .assistant,
            text: "I found \(emails.count) recent emails and prepared a cleanup plan for approval."
        )
        state = .approvalRequired
        refreshThreads()
        refreshSelectedThreadState()

        if !isPanelVisible {
            await notificationManager.send(
                title: "Mail cleanup needs approval",
                body: approval.title,
                threadID: threadID
            )
        }
    }

    private func execute(
        plan: YavenActionPlan,
        context: YavenComputerContext,
        threadID: UUID
    ) async {
        state = .executing
        executionResult = nil

        let runExecution: @MainActor () async -> YavenExecutionResult = { [notificationManager] in
            let executor = YavenAutomationExecutor(
                context: context,
                notificationManager: notificationManager
            )
            return await executor.execute(plan)
        }

        let result: YavenExecutionResult
        if plan.usesDesktopControl {
            result = await taskRunner.runUIAction(threadID: threadID, operation: runExecution)
        } else {
            result = await runExecution()
        }

        guard !Task.isCancelled else { return }
        executionResult = result

        if result.succeeded, let followUpPrompt = plan.followUpPrompt, !followUpPrompt.isEmpty {
            do {
                let (captures, newContext) = try await captureComputerContext(threadID: threadID)
                lastContextByThreadID[threadID] = newContext
                try await streamAnswer(
                    command: followUpPrompt,
                    captures: captures,
                    context: newContext,
                    threadID: threadID
                )
                await notificationManager.send(
                    title: "Yaven finished",
                    body: "The approved action and follow-up are done.",
                    threadID: threadID
                )
            } catch {
                presentError(error.localizedDescription, threadID: threadID)
            }
            return
        }

        if result.succeeded {
            finishThread(threadID, message: result.message)
            await notificationManager.send(
                title: "Yaven finished",
                body: result.message,
                threadID: threadID
            )
        } else {
            presentError(result.message, threadID: threadID)
            await notificationManager.send(
                title: "Yaven failed",
                body: result.message,
                threadID: threadID
            )
        }
    }

    private func executeCRMPlan(_ plan: HubSpotCRMUpdatePlan, threadID: UUID) async {
        state = .executing
        var completedSummaries: [String] = []

        for action in plan.actions {
            do {
                let inputJSON = try jsonString(from: action.input)
                let record = YavenSkillExecutionRecord(
                    id: UUID(),
                    threadID: threadID,
                    skillName: action.skillName,
                    inputJSON: inputJSON,
                    outputJSON: nil,
                    succeeded: nil,
                    createdAt: Date(),
                    completedAt: nil
                )
                try store.saveSkillExecution(record)
                let output = try YavenSkillRegistry.shared.run(
                    name: action.skillName,
                    input: action.input
                )
                var completedRecord = record
                completedRecord.outputJSON = output
                completedRecord.succeeded = true
                completedRecord.completedAt = Date()
                try store.saveSkillExecution(completedRecord)
                completedSummaries.append(action.summary)
            } catch {
                presentError(error.localizedDescription, threadID: threadID)
                return
            }
        }

        let message = completedSummaries.isEmpty
            ? "HubSpot updates completed."
            : "HubSpot updates completed: \(completedSummaries.joined(separator: "; "))"
        finishThread(threadID, message: message)
        await notificationManager.send(
            title: "HubSpot updated",
            body: message,
            threadID: threadID
        )
    }

    private func executeMailCleanupPlan(_ plan: YavenMailCleanupApprovalPlan, threadID: UUID) async {
        state = .executing
        var archivedCount = 0
        var filedCount = 0
        var surfacedItems: [String] = []

        for batch in plan.batches {
            guard !batch.messageIds.isEmpty else { continue }

            do {
                switch batch.action {
                case .archive:
                    let result = try skillRegistry.run(
                        name: "archive_emails_bulk",
                        input: ["message_ids": batch.messageIds]
                    )
                    archivedCount += batch.messageIds.count
                    try recordSkillExecution(
                        threadID: threadID,
                        skillName: "archive_emails_bulk",
                        input: ["message_ids": batch.messageIds],
                        output: result
                    )

                case .moveToFolder:
                    let folderName = batch.folderName ?? "Receipts"
                    _ = try skillRegistry.run(
                        name: "create_mailbox_if_missing",
                        input: ["name": folderName]
                    )
                    let result = try skillRegistry.run(
                        name: "move_emails_to_folder",
                        input: ["message_ids": batch.messageIds, "folder_name": folderName]
                    )
                    filedCount += batch.messageIds.count
                    try recordSkillExecution(
                        threadID: threadID,
                        skillName: "move_emails_to_folder",
                        input: ["message_ids": batch.messageIds, "folder_name": folderName],
                        output: result
                    )

                case .surface:
                    let emailsByID = plan.emailsByID
                    let labels = batch.messageIds.prefix(5).compactMap { id -> String? in
                        guard let email = emailsByID[id] else { return nil }
                        return "\(email.sender): \(email.subject)"
                    }
                    surfacedItems.append(contentsOf: labels)

                case .leaveAlone:
                    continue
                }
            } catch {
                presentError(error.localizedDescription, threadID: threadID)
                return
            }
        }

        var parts = ["Mail cleanup complete."]
        if archivedCount > 0 {
            parts.append("Archived \(archivedCount).")
        }
        if filedCount > 0 {
            parts.append("Filed \(filedCount).")
        }
        if !surfacedItems.isEmpty {
            parts.append("Needs your review: \(surfacedItems.joined(separator: "; ")).")
        }
        let message = parts.joined(separator: " ")
        finishThread(threadID, message: message)
        await notificationManager.send(
            title: "Mail cleanup finished",
            body: message,
            threadID: threadID
        )
    }

    private func recordSkillExecution(
        threadID: UUID,
        skillName: String,
        input: [String: Any],
        output: String
    ) throws {
        let inputData = try JSONSerialization.data(withJSONObject: input, options: [.sortedKeys])
        let inputJSON = String(data: inputData, encoding: .utf8) ?? "{}"
        let record = YavenSkillExecutionRecord(
            id: UUID(),
            threadID: threadID,
            skillName: skillName,
            inputJSON: inputJSON,
            outputJSON: output,
            succeeded: true,
            createdAt: Date(),
            completedAt: Date()
        )
        try store.saveSkillExecution(record)
    }

    private func validationError(_ message: String) -> NSError {
        NSError(domain: "YavenActionPlanValidation", code: 1, userInfo: [
            NSLocalizedDescriptionKey: message
        ])
    }

    private func runDirectOpenCommand(_ openTarget: YavenOpenTarget, threadID: UUID) {
        state = .executing

        switch openTarget {
        case .url(let url, let displayName):
            NSWorkspace.shared.open(url)
            finishDirectCommand(
                threadID: threadID,
                assistantMessage: "Opened \(displayName)."
            )

        case .application(let appName):
            runDirectOpenAppCommand(threadID: threadID, appName: appName)
        }
    }

    private func runDirectOpenAppCommand(threadID: UUID, appName: String) {
        if let runningApplication = YavenOpenCommandResolver.runningApplication(matching: appName) {
            if #available(macOS 14, *) {
                runningApplication.activate()
            } else {
                runningApplication.activate(options: [.activateIgnoringOtherApps])
            }
            finishDirectCommand(
                threadID: threadID,
                assistantMessage: "Opened \(runningApplication.localizedName ?? appName)."
            )
            return
        }

        guard let displayName = YavenOpenCommandResolver.launch(appName: appName) else {
            state = .idle
            presentError("Could not find the requested app to open.", threadID: threadID)
            return
        }

        finishDirectCommand(threadID: threadID, assistantMessage: "Opened \(displayName).")
    }

    private func finishDirectCommand(threadID: UUID, assistantMessage: String) {
        finishThread(threadID, message: assistantMessage)
    }

    private func finishThread(_ threadID: UUID, message: String) {
        do {
            executionResult = .success(message)
            _ = try store.appendMessage(threadID: threadID, role: .assistant, text: message)
            try store.appendCheckpoint(
                threadID: threadID,
                stepIndex: 5,
                status: .completed,
                state: ["phase": "completed"]
            )
            try store.updateThread(
                id: threadID,
                status: .completed,
                lastPreview: message,
                requiresAttention: false
            )
            state = .done
            refreshThreads()
            refreshSelectedThreadState()
        } catch {
            presentError(error.localizedDescription, threadID: threadID)
        }
    }

    private func markThreadCancelled(_ threadID: UUID) {
        do {
            try store.updateThread(
                id: threadID,
                status: .cancelled,
                lastPreview: "Cancelled.",
                requiresAttention: false
            )
            state = .idle
            refreshThreads()
        } catch {
            presentError(error.localizedDescription, threadID: threadID)
        }
    }

    private func presentError(_ message: String, threadID: UUID?) {
        errorMessage = message
        if let threadID {
            do {
                _ = try store.appendMessage(threadID: threadID, role: .assistant, text: message)
                try store.updateThread(
                    id: threadID,
                    status: .failed,
                    lastPreview: message,
                    requiresAttention: false
                )
            } catch {
                print("YavenAgentController: could not persist error: \(error)")
            }
        }
        state = .error
        refreshThreads()
        refreshSelectedThreadState()
    }

    private func updateAssistantMessage(
        _ message: YavenThreadMessage,
        text: String,
        threadID: UUID,
        shouldUpdateThreadPreview: Bool
    ) {
        do {
            var updatedMessage = message
            updatedMessage.text = text
            try store.upsertMessage(updatedMessage)
            if shouldUpdateThreadPreview {
                try store.updateThread(id: threadID, lastPreview: text)
            }
            refreshSelectedThreadState()
        } catch {
            print("YavenAgentController: could not update assistant message: \(error)")
        }
    }

    private func refreshThreads() {
        do {
            threads = try store.recentThreads(limit: 40)
        } catch {
            print("YavenAgentController: could not refresh threads: \(error)")
        }
    }

    private func refreshSelectedThreadState() {
        guard let selectedThreadID else {
            chatMessages = []
            selectedApproval = nil
            currentPlan = nil
            return
        }

        do {
            let persistedMessages = try store.messages(threadID: selectedThreadID)
            chatMessages = persistedMessages.map {
                YavenChatMessage(
                    id: $0.id,
                    role: $0.role,
                    text: $0.text,
                    createdAt: $0.createdAt
                )
            }
            selectedApproval = try store.pendingApproval(threadID: selectedThreadID)
            if selectedApproval?.kind == .operatorPlan, let approval = selectedApproval {
                currentPlan = try decodeOperatorApprovalPayload(from: approval).plan
            } else {
                currentPlan = nil
            }
        } catch {
            print("YavenAgentController: could not refresh selected thread: \(error)")
        }
        updatePreferredPanelHeight()
    }

    private func conversationHistory(for threadID: UUID) -> [(userPlaceholder: String, assistantResponse: String)] {
        let persistedMessages = (try? store.messages(threadID: threadID)) ?? []
        var rebuiltHistory: [(userPlaceholder: String, assistantResponse: String)] = []
        var pendingUserMessage: String?

        for message in persistedMessages {
            switch message.role {
            case .user:
                pendingUserMessage = message.text
            case .assistant:
                if let pendingUserText = pendingUserMessage {
                    rebuiltHistory.append((userPlaceholder: pendingUserText, assistantResponse: message.text))
                    pendingUserMessage = nil
                }
            }
        }

        if rebuiltHistory.count > Constants.conversationHistoryLimit {
            return Array(rebuiltHistory.suffix(Constants.conversationHistoryLimit))
        }
        return rebuiltHistory
    }

    private func makeOperatorApproval(
        threadID: UUID,
        plan: YavenActionPlan,
        context: YavenComputerContext
    ) throws -> YavenApprovalRequest {
        let payload = StoredOperatorApprovalPayload(plan: plan, context: context)
        let data = try JSONEncoder().encode(payload)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return YavenApprovalRequest(
            id: UUID(),
            threadID: threadID,
            kind: .operatorPlan,
            title: plan.goal,
            summary: plan.summary,
            payloadJSON: json,
            status: .pending,
            createdAt: Date(),
            resolvedAt: nil
        )
    }

    private func makeCRMApproval(
        threadID: UUID,
        plan: HubSpotCRMUpdatePlan
    ) throws -> YavenApprovalRequest {
        let json = try jsonString(from: plan)
        return YavenApprovalRequest(
            id: UUID(),
            threadID: threadID,
            kind: .crmSkill,
            title: plan.goal,
            summary: plan.summary,
            payloadJSON: json,
            status: .pending,
            createdAt: Date(),
            resolvedAt: nil
        )
    }

    private func makeMailCleanupApproval(
        threadID: UUID,
        plan: YavenMailCleanupApprovalPlan
    ) throws -> YavenApprovalRequest {
        let json = try jsonString(from: plan)
        let summary = plan.batches
            .map { "\($0.actionTitle) \($0.messageIds.count) \($0.category.displayTitle)" }
            .joined(separator: "; ")
        return YavenApprovalRequest(
            id: UUID(),
            threadID: threadID,
            kind: .mailCleanup,
            title: "Clean up \(plan.totalReviewed) recent Mail messages",
            summary: summary.isEmpty ? plan.summary : summary,
            payloadJSON: json,
            status: .pending,
            createdAt: Date(),
            resolvedAt: nil
        )
    }

    private func decodeOperatorApprovalPayload(
        from approval: YavenApprovalRequest
    ) throws -> StoredOperatorApprovalPayload {
        guard let data = approval.payloadJSON.data(using: .utf8) else {
            throw validationError("Approval payload is not valid UTF-8.")
        }
        return try JSONDecoder().decode(StoredOperatorApprovalPayload.self, from: data)
    }

    private func decodeCRMApprovalPayload(
        from approval: YavenApprovalRequest
    ) throws -> HubSpotCRMUpdatePlan {
        guard let data = approval.payloadJSON.data(using: .utf8) else {
            throw validationError("CRM approval payload is not valid UTF-8.")
        }
        return try JSONDecoder().decode(HubSpotCRMUpdatePlan.self, from: data)
    }

    private func decodeMailCleanupApprovalPayload(
        from approval: YavenApprovalRequest
    ) throws -> YavenMailCleanupApprovalPlan {
        guard let data = approval.payloadJSON.data(using: .utf8) else {
            throw validationError("Mail cleanup approval payload is not valid UTF-8.")
        }
        return try JSONDecoder().decode(YavenMailCleanupApprovalPlan.self, from: data)
    }

    private func decodeCRMPlan(from responseText: String) throws -> HubSpotCRMUpdatePlan {
        let jsonText = try extractJSONObject(from: responseText)
        guard let data = jsonText.data(using: .utf8) else {
            throw validationError("CRM plan is not valid UTF-8.")
        }
        return try JSONDecoder().decode(HubSpotCRMUpdatePlan.self, from: data)
    }

    private func extractJSONObject(from responseText: String) throws -> String {
        if let fencedRange = responseText.range(of: #"```(?:json)?\s*(\{[\s\S]*?\})\s*```"#, options: .regularExpression) {
            var fenced = String(responseText[fencedRange])
            fenced = fenced.replacingOccurrences(of: #"^```(?:json)?\s*"#, with: "", options: .regularExpression)
            fenced = fenced.replacingOccurrences(of: #"\s*```$"#, with: "", options: .regularExpression)
            return fenced
        }

        guard let firstBrace = responseText.firstIndex(of: "{"),
              let lastBrace = responseText.lastIndex(of: "}") else {
            throw validationError("Claude did not return a JSON CRM plan.")
        }

        return String(responseText[firstBrace...lastBrace])
    }

    private func jsonString<T: Encodable>(from value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func updatePreferredPanelHeight() {
        preferredPanelHeight = Constants.fixedPanelHeight
    }

    private func migrateLegacyChatMessagesIfNeeded() {
        let standardData = UserDefaults.standard.data(forKey: Constants.persistedChatMessagesKey)
        let legacyData = Constants.legacyDefaultsSuiteNames.compactMap { suiteName in
            UserDefaults(suiteName: suiteName)?.data(forKey: Constants.persistedChatMessagesKey)
        }.first

        guard let data = standardData ?? legacyData,
              let decodedMessages = try? JSONDecoder().decode([YavenChatMessage].self, from: data) else {
            return
        }

        do {
            _ = try store.migrateLegacyChatIfNeeded(messages: Array(decodedMessages.suffix(Constants.persistedChatMessagesLimit)))
            UserDefaults.standard.removeObject(forKey: Constants.persistedChatMessagesKey)
            UserDefaults.standard.synchronize()
        } catch {
            print("YavenAgentController: legacy chat migration failed: \(error)")
        }
    }

    private static let cleanupSystemPrompt = """
    You are Yaven, helping the user clean up their Apple Mail inbox. You have a list of their last 200 emails.

    Categorize each email into exactly one of these five categories:
    - newsletters: regular sends from newsletters, content publications, news roundups
    - promotions: marketing emails, sales pitches, discount offers, "limited time" emails
    - needs_reply: emails from real humans that contain a question, request, or expectation of a reply that hasn't happened yet
    - receipts: order confirmations, invoices, payment receipts, shipping notifications, account verifications
    - personal_work: real correspondence with colleagues, friends, or family that doesn't need an immediate reply

    Be conservative on "needs_reply" — only flag something if it's genuinely waiting on the user. When in doubt, put it in personal_work.

    Return only strict JSON. Do not use markdown. Do not include commentary outside JSON.

    JSON schema:
    {
      "categories": [
        {
          "category": "newsletters|promotions|needs_reply|receipts|personal_work",
          "message_ids": ["id1", "id2"],
          "summary": "47 newsletters from 12 senders"
        }
      ]
    }

    Every input email id must appear in exactly one category.
    """

    private static func cleanupUserPrompt(emails: [RecentEmail]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let emailJSON = (try? String(data: encoder.encode(emails), encoding: .utf8)) ?? "[]"
        return "Categorize these emails:\n\(emailJSON)"
    }

    private static let crmPlanSystemPrompt = """
    You are Yaven's HubSpot CRM planner. Convert the user's sales context into a short approval-first HubSpot update plan.

    Return only strict JSON. Do not use markdown. Do not include commentary outside JSON.

    Allowed write skills:
    - hubspot_create_note: input body, associatedObjectID, associatedObjectType
    - hubspot_create_task: input title, body, associatedObjectID, associatedObjectType
    - hubspot_update_deal_stage: input dealID, stageID
    - hubspot_log_email: input subject, body, associatedObjectID, associatedObjectType

    Only propose writes the user can review safely. If a required HubSpot record id or deal stage id is missing, set the action summary to say exactly what is missing and do not invent ids.

    JSON schema:
    {
      "goal": "short user-visible goal",
      "summary": "brief explanation of the proposed CRM changes",
      "actions": [
        {
          "skill_name": "hubspot_create_note|hubspot_create_task|hubspot_update_deal_stage|hubspot_log_email",
          "summary": "human-readable exact change",
          "input": {
            "body": "note or email body",
            "associatedObjectID": "HubSpot id if known",
            "associatedObjectType": "contacts|companies|deals if known"
          }
        }
      ]
    }
    """
}

private struct StoredOperatorApprovalPayload: Codable {
    let plan: YavenActionPlan
    let context: YavenComputerContext
}

private extension YavenActionPlan {
    var usesDesktopControl: Bool {
        steps.contains { step in
            switch step.type {
            case .activateApp, .keyboardShortcut, .click, .typeText, .pasteText:
                return true
            case .wait, .notify:
                return false
            }
        }
    }
}
