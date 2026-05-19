//
//  YavenWidgetBar.swift
//  leanring-buddy
//
//  Horizontal widget bar — boring.notch style.
//
//  Default (compact): 4 cards side-by-side at 160 px tall.
//  Click any card → that widget expands to fill the panel at a taller height.
//  Back chevron returns to the compact row.
//
//  Heights (content only, pill height added by shell):
//    compact        160 px
//    chat           420 px
//    automations    360 px
//    notifications  200 px
//    logCall        360 px
//

import Combine
import SwiftUI

// MARK: - Focus state

enum WidgetFocus: Equatable {
    case none
    case chat
    case automations
    case notifications
    case logCall
    case meeting
}

// MARK: - Main bar

struct YavenWidgetBar: View {

    @ObservedObject var agentController: YavenAgentController
    @ObservedObject var cleanupController: YavenCleanupController
    @ObservedObject var focusCoordinator: YavenPanelFocusCoordinator
    let firstRunPanelMode: YavenFirstRunPanelMode
    let onPreferredHeightChange: (CGFloat) -> Void
    let onFirstRunYes: () -> Void
    let onFirstRunLater: () -> Void
    let onCleanupSkip: () -> Void
    let onCleanupContinue: () -> Void
    let onDraftReply: (NeedsReplyItem) -> Void

    @StateObject private var logCallController = LogCallController()
    @ObservedObject private var activityObserver = YavenActivityObserver.shared
    @ObservedObject private var preCallBriefController = PreCallBriefController.shared

    @State private var widgetFocus: WidgetFocus = .none
    @State private var automationDrillIn: AutomationItem? = nil
    @State private var showingChatHistory = false
    @State private var command: String = ""
    @FocusState private var isCommandFocused: Bool

    private static let compactHeight: CGFloat        = 200
    private static let chatHeight: CGFloat           = 420
    private static let automationsHeight: CGFloat    = 380
    private static let notificationsHeight: CGFloat  = 220
    private static let logCallHeight: CGFloat        = 380
    private static let meetingHeight: CGFloat        = 460

    private enum Motion {
        static let focus = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.84, blendDuration: 0)
        static let reveal = Animation.easeOut(duration: 0.20)
    }

    var body: some View {
        Group {
            if firstRunPanelMode != .hidden {
                firstRunOverlay
            } else if widgetFocus == .none {
                compactRow
                    .transition(focusTransition)
            } else {
                expandedView
                    .transition(focusTransition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Motion.focus, value: widgetFocus)
        .onAppear { onPreferredHeightChange(Self.compactHeight) }
        .onChange(of: widgetFocus) { _, focus in
            // Meeting widget drives its own height via onPreferredHeightChange callbacks.
            if focus != .meeting {
                onPreferredHeightChange(height(for: focus))
            }
            if focus != .chat { showingChatHistory = false }
            if focus != .logCall { automationDrillIn = nil }
        }
        // When the shell requests focus (hotkey / notification tap), jump to chat.
        .onChange(of: focusCoordinator.focusRequestID) { _, _ in
            setWidgetFocus(.chat)
            showingChatHistory = false
            DispatchQueue.main.async { isCommandFocused = true }
        }
    }

    private var focusTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.98, anchor: .top)
                .combined(with: .opacity)
                .animation(Motion.reveal),
            removal: .opacity.animation(.easeIn(duration: 0.10))
        )
    }

    private func setWidgetFocus(_ focus: WidgetFocus) {
        withAnimation(Motion.focus) {
            widgetFocus = focus
        }
    }

    private func height(for focus: WidgetFocus) -> CGFloat {
        switch focus {
        case .none:          return Self.compactHeight
        case .chat:          return Self.chatHeight
        case .automations:   return Self.automationsHeight
        case .notifications: return Self.notificationsHeight
        case .logCall:       return Self.logCallHeight
        case .meeting:       return Self.meetingHeight
        }
    }

    // MARK: - Compact row

    private var compactRow: some View {
        HStack(alignment: .top, spacing: 10) {
            ActivityCompactCard(agentController: agentController) {
                setWidgetFocus(.automations)
            }

            AutomationsCompactCard(
                logCallController: logCallController,
                briefController: preCallBriefController
            ) {
                setWidgetFocus(.logCall)
                automationDrillIn = nil
            }

            ChatCompactCard(agentController: agentController) {
                setWidgetFocus(.chat)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 18)
        .padding(.bottom, 38)   // clears the notch's 24 px bottom corner radius
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Expanded wrapper

    private var expandedView: some View {
        VStack(spacing: 0) {
            expandedHeader
            Divider().opacity(0.12)
            expandedContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var expandedHeader: some View {
        HStack(spacing: 0) {
            Button {
                if widgetFocus == .logCall, automationDrillIn != nil {
                    withAnimation(Motion.focus) { automationDrillIn = nil }
                    onPreferredHeightChange(Self.logCallHeight)
                } else {
                    setWidgetFocus(.none)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text(expandedTitle)
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.55))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerCursor()

            Spacer()

            if widgetFocus == .chat {
                HStack(spacing: 12) {
                    // History: toggle past chat threads.
                    Button {
                        showingChatHistory.toggle()
                    } label: {
                        Image(systemName: showingChatHistory ? "bubble.left.fill" : "clock.arrow.circlepath")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(showingChatHistory ? 0.55 : 0.35))
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()

                    // New chat — only when there are active messages.
                    if !agentController.chatMessages.isEmpty && !showingChatHistory {
                        Button {
                            command = ""
                            agentController.clearChatMemory()
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.35))
                        }
                        .buttonStyle(.plain)
                        .pointerCursor()
                    }
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 10)
    }

    private var expandedTitle: String {
        switch widgetFocus {
        case .chat:          return "Chat"
        case .automations:   return "Activity"
        case .notifications: return "Notifications"
        case .logCall:       return automationDrillIn?.displayName ?? "Automations"
        case .meeting:       return "Process Meeting"
        case .none:          return ""
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        switch widgetFocus {
        case .chat:
            chatExpandedView
        case .automations:
            automationsExpandedView
        case .notifications:
            notificationsExpandedView
        case .logCall:
            automationsExpandedView2
        case .meeting:
            MeetingExpandedView { newHeight in
                onPreferredHeightChange(newHeight + 44) // +44 for the expanded header
            }
        case .none:
            EmptyView()
        }
    }

    // MARK: - Chat expanded

    private var chatExpandedView: some View {
        VStack(spacing: 0) {
            if showingChatHistory {
                chatHistoryList
            } else {
                chatMessagesArea
                chatInputBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chatMessagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if agentController.chatMessages.isEmpty
                            && agentController.state == .idle
                            && agentController.currentPlan == nil
                            && agentController.executionResult == nil
                            && agentController.errorMessage == nil {
                            emptyChat
                        }

                        chatStatusLine

                        ForEach(agentController.chatMessages) { msg in
                            chatBubble(msg)
                        }

                        if let plan = agentController.currentPlan {
                            chatApprovalCard(plan)
                        }

                        if let result = agentController.executionResult {
                            chatResultCard(result)
                        }

                        if let error = agentController.errorMessage {
                            chatErrorCard(error)
                        }

                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 10)
                    .padding(.bottom, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: agentController.chatMessages.count) { _, _ in scrollTo(proxy) }
                .onChange(of: agentController.chatMessages.last?.text ?? "") { _, _ in scrollTo(proxy) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Chat history list

    private var chatHistoryList: some View {
        let chatThreads = agentController.recentThreads.filter { $0.kind == .chat }
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if chatThreads.isEmpty {
                    Text("No past conversations yet.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                } else {
                    ForEach(chatThreads) { thread in
                        Button {
                            agentController.selectThread(thread.id)
                            showingChatHistory = false
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(thread.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                if !thread.lastPreview.isEmpty {
                                    Text(thread.lastPreview)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.07)))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .pointerCursor()
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyChat: some View {
        Text("Yaven sees your screens only when you submit. Simple open/send requests run right away; riskier actions pause for review.")
            .font(.system(size: 13))
            .foregroundColor(.secondary)
            .lineSpacing(3)
            .padding(.top, 4)
    }

    @ViewBuilder
    private var chatStatusLine: some View {
        let label: String? = {
            switch agentController.state {
            case .thinking:        return "Capturing screen context…"
            case .answering:       return "Responding…"
            case .planning:        return "Preparing a plan…"
            case .approvalRequired: return "Review before Yaven acts."
            case .executing:       return "Executing…"
            case .done:            return "Done."
            case .error:           return "Something went wrong."
            case .idle:            return nil
            }
        }()
        if let label {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
    }

    private func chatBubble(_ msg: YavenChatMessage) -> some View {
        HStack {
            if msg.role == .user { Spacer(minLength: 34) }
            Text(msg.text)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .lineSpacing(3)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(msg.role == .user ? Color.cyan.opacity(0.14) : Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(msg.role == .user ? Color.cyan.opacity(0.14) : Color.white.opacity(0.08), lineWidth: 0.5)
                )
            if msg.role == .assistant { Spacer(minLength: 34) }
        }
        .frame(maxWidth: .infinity, alignment: msg.role == .user ? .trailing : .leading)
    }

    private func chatApprovalCard(_ plan: YavenActionPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(plan.goal).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(plan.risk.rawValue.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(plan.risk == .high ? .red : plan.risk == .medium ? .orange : .green)
            }
            Text(plan.summary).font(.system(size: 12)).foregroundColor(.secondary)
            HStack {
                Button("Approve") { agentController.approveCurrentPlan() }
                    .keyboardShortcut(.return, modifiers: [])
                Button("Cancel") { agentController.cancelCurrentPlan() }
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 0.5))
    }

    private func chatResultCard(_ result: YavenExecutionResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(result.succeeded ? "Completed" : "Stopped")
                .font(.system(size: 13, weight: .semibold))
            Text(result.message)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
    }

    private func chatErrorCard(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13))
            .foregroundColor(.red.opacity(0.85))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.08)))
    }

    private var chatInputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask Yaven anything…", text: $command)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .focused($isCommandFocused)
                .onSubmit(submitCommand)
                .onAppear { isCommandFocused = true }

            if !command.isEmpty {
                Button(action: submitCommand) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(0.88)))
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.055))
        .overlay(Rectangle().frame(height: 0.5).foregroundColor(.white.opacity(0.09)), alignment: .top)
    }

    private func submitCommand() {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        agentController.submit(trimmed)
        command = ""
        isCommandFocused = true
    }

    private func scrollTo(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    // MARK: - Automations expanded

    private var automationsExpandedView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !activityObserver.isEnabled {
                    activityOptInCard
                }
                activitySection(
                    title: "Needs approval",
                    threads: agentController.needsApprovalThreads,
                    emptyText: "Nothing waiting."
                )
                activitySection(
                    title: "Running",
                    threads: agentController.runningThreads,
                    emptyText: "No background tasks."
                )
                activitySection(
                    title: "Recent",
                    threads: Array(agentController.recentThreads.prefix(8)),
                    emptyText: "No recent tasks."
                )
            }
            .padding(.horizontal, 32)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
    }

    private var activityOptInCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Local activity awareness")
                .font(.system(size: 13, weight: .semibold))
            Text("Yaven can log which apps you switch between so future automations have better context.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineSpacing(2)
            Button("Enable") { activityObserver.setEnabled(true) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .pointerCursor()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 0.5))
    }

    private func activitySection(title: String, threads: [YavenThreadSummary], emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            if threads.isEmpty {
                Text(emptyText)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.vertical, 2)
            } else {
                ForEach(threads) { thread in
                    activityRow(thread)
                }
            }
        }
    }

    private func activityRow(_ thread: YavenThreadSummary) -> some View {
        Button { agentController.selectThread(thread.id) } label: {
            HStack(alignment: .top, spacing: 9) {
                Circle()
                    .fill(threadStatusColor(thread.status))
                    .frame(width: 7, height: 7)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(thread.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(thread.lastPreview.isEmpty ? thread.status.displayTitle : thread.lastPreview)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(thread.requiresAttention ? 0.12 : 0.07)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    private func threadStatusColor(_ status: YavenThreadStatus) -> Color {
        switch status {
        case .queued:          return .yellow.opacity(0.8)
        case .running:         return .cyan
        case .approvalRequired: return .orange
        case .completed:       return .green
        case .failed:          return .red
        case .cancelled:       return Color.secondary
        }
    }

    // MARK: - Notifications expanded

    private var notificationsExpandedView: some View {
        VStack {
            Spacer()
            Image(systemName: "bell.slash")
                .font(.system(size: 30))
                .foregroundColor(.white.opacity(0.14))
            Text("No notifications")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.26))
                .padding(.top, 6)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Automations hub

    private enum AutomationItem: String, CaseIterable, Identifiable {
        case logCall        = "log-call"
        case preCallBrief   = "pre-call-brief"
        case processMeeting = "process-meeting"
        case proposalDraft  = "proposal-draft"
        case invoiceChase   = "invoice-chase"
        case scopeGuardian  = "scope-guardian"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .logCall:        return "Log Sales Call"
            case .preCallBrief:   return "Pre-Call Brief"
            case .processMeeting: return "Process Meeting"
            case .proposalDraft:  return "Proposal Draft"
            case .invoiceChase:   return "Invoice Chase"
            case .scopeGuardian:  return "Scope Guardian"
            }
        }

        var icon: String {
            switch self {
            case .logCall:        return "phone.fill"
            case .preCallBrief:   return "doc.text.magnifyingglass"
            case .processMeeting: return "sparkles"
            case .proposalDraft:  return "doc.badge.plus"
            case .invoiceChase:   return "envelope.badge.fill"
            case .scopeGuardian:  return "shield.lefthalf.filled"
            }
        }

        var tagline: String {
            switch self {
            case .logCall:        return "Extract call notes, update HubSpot, draft follow-up emails."
            case .preCallBrief:   return "3-bullet brief auto-surfaces 5 min before each call."
            case .processMeeting: return "Turn Granola meeting notes into action items."
            case .proposalDraft:  return "Paste a client brief, get a full proposal draft in Gmail."
            case .invoiceChase:   return "Generate a polite but firm payment chase email."
            case .scopeGuardian:  return "Detect scope creep and draft a professional boundary response."
            }
        }
    }

    private var automationsExpandedView2: some View {
        Group {
            if let drill = automationDrillIn {
                automationDetailContent(drill)
            } else {
                automationListContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var automationListContent: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(AutomationItem.allCases) { item in
                    AutomationListCard(
                        displayName: item.displayName,
                        icon: item.icon,
                        tagline: item.tagline
                    ) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            automationDrillIn = item
                            if item != .processMeeting {
                                onPreferredHeightChange(Self.logCallHeight)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func automationDetailContent(_ item: AutomationItem) -> some View {
        switch item {
        case .logCall:
            ToolConnectionGateView(tools: [.init(name: "HubSpot", composioKey: "HUBSPOT", icon: "person.fill")]) {
                AnyView(
                    ScrollView {
                        YavenLogCallWidget(controller: logCallController)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 10)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .preCallBrief:
            PreCallBriefAutomationView(controller: preCallBriefController)

        case .processMeeting:
            MeetingExpandedView { newHeight in
                onPreferredHeightChange(newHeight + 44)
            }

        case .proposalDraft:
            ProposalDraftView()

        case .invoiceChase:
            InvoiceChaseView()

        case .scopeGuardian:
            ScopeGuardianView()
        }
    }

    // MARK: - First-run overlay

    @ViewBuilder
    private var firstRunOverlay: some View {
        switch firstRunPanelMode {
        case .hidden:
            EmptyView()
        case .firstMessage:
            YavenFirstMessageView(onYes: onFirstRunYes, onLater: onFirstRunLater)
                .padding(.horizontal, 32).padding(.vertical, 18)
        case .cleanup:
            cleanupContent(for: cleanupController.phase)
                .padding(.horizontal, 32).padding(.vertical, 18)
        }
    }

    @ViewBuilder
    private func cleanupContent(for phase: YavenCleanupPhase) -> some View {
        switch phase {
        case .idle:
            ProgressView().controlSize(.small)
        case .scanning(let lines, let visibleLineCount):
            ScanningProgressView(lines: lines, visibleLineCount: visibleLineCount)
        case .awaitingApproval(let plan, let emailsByID):
            CategoriesApprovalContainer(plan: plan, emailsByID: emailsByID, cleanupController: cleanupController, onSkip: onCleanupSkip)
        case .executing(let lines):
            CleanupExecutionView(lines: lines)
        case .done(let archived, let filed, let inbox, let needsReply):
            CleanupDoneView(archivedCount: archived, filedReceiptCount: filed, inboxCount: inbox, needsReplyItems: needsReply, onDraftReply: onDraftReply, onContinue: onCleanupContinue)
        case .skipped, .error:
            Button("Back to Yaven") { onCleanupContinue() }
                .buttonStyle(.bordered).controlSize(.small).pointerCursor()
        }
    }
}

// MARK: - Compact cards

private struct ChatCompactCard: View {
    @ObservedObject var agentController: YavenAgentController
    let onTap: () -> Void

    var body: some View {
        CompactCard(icon: "bubble.left.fill", title: "Chat", onTap: onTap) {
            if let last = agentController.chatMessages.last {
                Text(last.text)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.50))
                    .lineLimit(3)
                    .lineSpacing(2)
            } else if agentController.isWorking {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini)
                    Text("Working…")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Ask anything…")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.25))
            }
        }
    }
}

private struct ActivityCompactCard: View {
    @ObservedObject var agentController: YavenAgentController
    let onTap: () -> Void

    var body: some View {
        CompactCard(icon: "bolt.fill", title: "Activity", onTap: onTap) {
            let approvals = agentController.needsApprovalThreads.count
            let running   = agentController.runningThreads.count
            let recent    = agentController.recentThreads.count

            VStack(alignment: .leading, spacing: 3) {
                if approvals > 0 {
                    statRow(label: "Needs approval", count: approvals, color: .orange)
                }
                if running > 0 {
                    statRow(label: "Running", count: running, color: .cyan)
                }
                statRow(label: "Recent", count: recent, color: .secondary)
            }
        }
    }

    private func statRow(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text("\(count) \(label)")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.50))
        }
    }
}

private struct NotificationsCompactCard: View {
    let onTap: () -> Void

    var body: some View {
        CompactCard(icon: "bell.fill", title: "Alerts", onTap: onTap) {
            Text("No new alerts")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.25))
        }
    }
}

private struct AutomationsCompactCard: View {
    @ObservedObject var logCallController: LogCallController
    @ObservedObject var briefController: PreCallBriefController
    let onTap: () -> Void

    var body: some View {
        CompactCard(icon: "sparkles", title: "Automations", onTap: onTap) {
            VStack(alignment: .leading, spacing: 3) {
                Text(logCallStatusLabel)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(logCallIsIdle ? 0.25 : 0.55))
                    .lineLimit(1)

                if briefController.lastBrief != nil || briefController.isGenerating {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.blue.opacity(0.7))
                            .frame(width: 5, height: 5)
                        Text(briefController.isGenerating ? "Brief generating…" : "Brief ready")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.45))
                    }
                }
            }
        }
    }

    private var logCallIsIdle: Bool {
        if case .idle = logCallController.phase { return true }
        return false
    }

    private var logCallStatusLabel: String {
        switch logCallController.phase {
        case .idle:                    return "6 automations"
        case .collectingInput:         return "Log call: paste notes…"
        case .extracting:              return "Log call: analysing…"
        case .awaitingApproval(let a): return "Log call: \(a.count) actions ready"
        case .executing:               return "Log call: running…"
        case .done:                    return "Log call: logged ✓"
        case .failed:                  return "Log call: failed — tap to retry"
        }
    }
}

// MARK: - Automation list card

private struct AutomationListCard: View {
    // AutomationItem is defined inside YavenWidgetBar so we use the raw fields.
    let displayName: String
    let icon: String
    let tagline: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.65))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(tagline)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .lineSpacing(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.25))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 0.5))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }
}

// MARK: - Pre-call brief automation view

private struct PreCallBriefAutomationView: View {
    @ObservedObject var controller: PreCallBriefController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Status card
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(Color.blue.opacity(0.15)).frame(width: 32, height: 32)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.blue.opacity(0.85))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-active")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Polls calendar every 60 s. Brief appears 5 min before each call.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineSpacing(1)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.blue.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.blue.opacity(0.15), lineWidth: 0.5))

                // Last brief preview
                if let brief = controller.lastBrief {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Last brief")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(brief.prospectName)\(brief.company.isEmpty ? "" : " · \(brief.company)")")
                                .font(.system(size: 13, weight: .medium))

                            briefBullet(label: "Rapport", text: brief.rapport, color: .blue)
                            briefBullet(label: "Lead with", text: brief.painPoint, color: .purple)
                            briefBullet(label: "Expect", text: brief.likelyObjection, color: .orange)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
                    }
                } else {
                    Text("No brief generated yet. One will appear automatically before your next external call.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineSpacing(2)
                        .padding(.top, 2)
                }

                // Test button
                Button {
                    PreCallBriefController.shared.testNow()
                } label: {
                    HStack(spacing: 6) {
                        if controller.isGenerating {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                        }
                        Text(controller.isGenerating ? "Generating…" : "Test Now")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.10)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .disabled(controller.isGenerating)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func briefBullet(label: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(color.opacity(0.7)).frame(width: 5, height: 5).padding(.top, 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.4)
                Text(text)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Compact card shell

private struct CompactCard<Content: View>: View {
    let icon: String
    let title: String
    let onTap: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.38))
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.38))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.20))
                }
                content()
                Spacer(minLength: 0)
            }
            .padding(11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 0.75)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }
}
