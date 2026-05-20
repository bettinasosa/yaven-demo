//
//  YavenPanelView.swift
//  leanring-buddy
//

import Combine
import SwiftUI

@MainActor
final class YavenPanelFocusCoordinator: ObservableObject {
    @Published var focusRequestID = UUID()
    @Published private(set) var widgetFocusRequestID = UUID()
    @Published private(set) var requestedWidgetFocus: WidgetFocus?

    func requestInputFocus() {
        focusRequestID = UUID()
    }

    func requestWidgetFocus(_ focus: WidgetFocus) {
        requestedWidgetFocus = focus
        widgetFocusRequestID = UUID()
    }
}

struct YavenPanelView: View {
    @ObservedObject var focusCoordinator: YavenPanelFocusCoordinator
    @ObservedObject var agentController: YavenAgentController
    @ObservedObject var cleanupController: YavenCleanupController
    let firstRunPanelMode: YavenFirstRunPanelMode
    let activeTab: YavenPanelTab
    let onPreferredHeightChange: (CGFloat) -> Void
    let onFirstRunYes: () -> Void
    let onFirstRunLater: () -> Void
    let onCleanupSkip: () -> Void
    let onCleanupContinue: () -> Void
    let onDraftReply: (NeedsReplyItem) -> Void

    @FocusState private var isCommandFieldFocused: Bool
    @ObservedObject private var activityObserver = YavenActivityObserver.shared
    @State private var command = ""

    private var isFirstRunMode: Bool {
        firstRunPanelMode != .hidden
    }

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
            Color.black.opacity(0.55)
            // Gradient fades the pill's solid black into the glass below naturally.
            LinearGradient(
                colors: [Color.black, Color.clear],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.22)
            )
            panelContent
        }
        .frame(width: 500, height: agentController.preferredPanelHeight)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 20,
                bottomTrailingRadius: 20,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
        .onAppear {
            focusCommandField()
            onPreferredHeightChange(agentController.preferredPanelHeight)
        }
        .onChange(of: focusCoordinator.focusRequestID) { _, _ in
            focusCommandField()
        }
        .onChange(of: agentController.preferredPanelHeight) { _, newHeight in
            onPreferredHeightChange(newHeight)
        }
    }

    private var panelContent: some View {
        VStack(spacing: 12) {
            if !isFirstRunMode {
                questionTitle
            }
            contentArea
            if !isFirstRunMode && activeTab == .chat {
                commandField
                footer
            }
        }
        .padding(24)
    }

    private var panelGlassOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            Color(red: 0.96, green: 0.75, blue: 0.38).opacity(0.08),
                            Color(red: 0.88, green: 0.50, blue: 0.25).opacity(0.10),
                            Color.black.opacity(0.16)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.98, green: 0.85, blue: 0.50).opacity(0.14),
                            Color.clear
                        ],
                        center: UnitPoint(x: 0.16, y: 0.10),
                        startRadius: 8,
                        endRadius: 360
                    )
                )

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color(red: 0.05, green: 0.07, blue: 0.24).opacity(0.18)
                        ],
                        startPoint: .center,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.30),
                            Color.cyan.opacity(0.14),
                            Color.black.opacity(0.22)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
        }
        .allowsHitTesting(false)
    }

    private var panelTitleText: String {
        guard activeTab == .chat else { return activeTab.panelTitle }
        let firstName = YavenUserContext.shared.firstName
        guard !firstName.isEmpty else { return activeTab.panelTitle }
        let hour = Calendar.current.component(.hour, from: Date())
        let greeting = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        return "\(greeting), \(firstName)."
    }

    private var questionTitle: some View {
        HStack {
            Text(panelTitleText)
                .font(.custom("Fraunces-SemiBold", size: 21, relativeTo: .title3))
                .foregroundColor(.primary)

            Spacer()

            if agentController.isWorking {
                ProgressView()
                    .controlSize(.small)
            }

            if activeTab == .chat {
                newChatButton
            }
        }
        .padding(.top, 6)
    }

    private var activityButton: some View {
        Button {
            agentController.showActivityInbox()
        } label: {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary.opacity(0.82))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.10))
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .help("Activity history")
        .accessibilityLabel("Activity history")
        .pointerCursor()
    }

    private var newChatButton: some View {
        Button {
            command = ""
            agentController.clearChatMemory()
            focusCommandField()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary.opacity(0.82))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.10))
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .help("New chat")
        .accessibilityLabel("New chat")
        .pointerCursor()
    }

    private var commandField: some View {
        TextField("Ask Yaven anything...", text: $command)
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .foregroundColor(.primary)
            .focused($isCommandFieldFocused)
            .onSubmit(submitCommand)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: 48)
            .background(commandFieldBackground)
            .overlay(commandFieldBorder)
    }

    private var contentArea: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if isFirstRunMode {
                        firstRunContent
                    } else if activeTab == .automations {
                        activityInbox
                    } else if activeTab == .notifications {
                        notificationsView
                    } else {
                        // .chat
                        statusLine

                        if isEmptyState {
                            emptyState
                        }

                        ForEach(agentController.chatMessages) { message in
                            chatBubble(message)
                        }

                        if let plan = agentController.currentPlan {
                            approvalCard(plan)
                        } else if let approval = agentController.selectedApproval {
                            approvalRequestCard(approval)
                        }

                        if let executionResult = agentController.executionResult {
                            resultCard(executionResult)
                        }

                        if let errorMessage = agentController.errorMessage {
                            errorCard(errorMessage)
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("conversation-bottom")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                scrollToBottom(scrollProxy)
            }
            .onChange(of: agentController.chatMessages.count) { _, _ in
                scrollToBottom(scrollProxy)
            }
            .onChange(of: agentController.chatMessages.last?.text ?? "") { _, _ in
                scrollToBottom(scrollProxy)
            }
            .onChange(of: cleanupController.phase) { _, _ in
                scrollToBottom(scrollProxy)
            }
        }
    }

    @ViewBuilder
    private var firstRunContent: some View {
        switch firstRunPanelMode {
        case .hidden:
            EmptyView()
        case .firstMessage:
            YavenFirstMessageView(
                onYes: onFirstRunYes,
                onLater: onFirstRunLater
            )
        case .cleanup:
            cleanupContent(for: cleanupController.phase)
        }
    }

    @ViewBuilder
    private func cleanupContent(for phase: YavenCleanupPhase) -> some View {
        switch phase {
        case .idle:
            ProgressView()
                .controlSize(.small)
        case .scanning(let lines, let visibleLineCount):
            ScanningProgressView(lines: lines, visibleLineCount: visibleLineCount)
        case .awaitingApproval(let plan, let emailsByID):
            CategoriesApprovalContainer(
                plan: plan,
                emailsByID: emailsByID,
                cleanupController: cleanupController,
                onSkip: onCleanupSkip
            )
        case .executing(let lines):
            CleanupExecutionView(lines: lines)
        case .done(let archivedCount, let filedReceiptCount, let inboxCount, let needsReplyItems):
            CleanupDoneView(
                archivedCount: archivedCount,
                filedReceiptCount: filedReceiptCount,
                inboxCount: inboxCount,
                needsReplyItems: needsReplyItems,
                onDraftReply: onDraftReply,
                onContinue: onCleanupContinue
            )
        case .skipped:
            VStack(alignment: .leading, spacing: 12) {
                Text("Skipped inbox cleanup.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Button("Ask Yaven something") {
                    onCleanupContinue()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .pointerCursor()
            }
        case .error(let message):
            VStack(alignment: .leading, spacing: 12) {
                errorCard(message)
                Button("Back to Yaven") {
                    onCleanupContinue()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .pointerCursor()
            }
        }
    }

    private var isResearchThread: Bool {
        agentController.threads
            .first(where: { $0.id == agentController.selectedThreadID })?.kind == .research
    }

    private var statusLine: some View {
        Group {
            switch agentController.state {
            case .thinking:
                Text("Capturing screen context...")
            case .answering:
                Text(isResearchThread ? "Researching..." : "Claude is responding...")
            case .planning:
                Text("Preparing an approval plan...")
            case .approvalRequired:
                Text("Review before Yaven takes action.")
            case .executing:
                Text("Executing approved steps...")
            case .done:
                Text(isResearchThread ? "Artifact saved to Desktop." : "Done.")
            case .error:
                Text("Yaven needs attention.")
            case .idle:
                EmptyView()
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(.secondary)
    }

    private var activityInbox: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !activityObserver.isEnabled {
                activityOptInCard
            }
            activitySection(
                title: "Needs approval",
                threads: agentController.needsApprovalThreads,
                emptyText: "Nothing waiting on you."
            )
            activitySection(
                title: "Running",
                threads: agentController.runningThreads,
                emptyText: "No background tasks running."
            )
            activitySection(
                title: "Recent",
                threads: Array(agentController.recentThreads.prefix(8)),
                emptyText: "No recent tasks yet."
            )
        }
    }

    private var activityOptInCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Local activity awareness")
                .font(.system(size: 13, weight: .semibold))
            Text("Yaven can remember which apps you switch between so future automations have better context. Screens are still captured only when you submit.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
            Button("Enable local app log") {
                activityObserver.setEnabled(true)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .pointerCursor()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
        )
    }

    private var notificationsView: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "bell.slash")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.18))
            Text("No notifications")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.30))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func activitySection(
        title: String,
        threads: [YavenThreadSummary],
        emptyText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            if threads.isEmpty {
                Text(emptyText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary.opacity(0.75))
                    .padding(.vertical, 3)
            } else {
                ForEach(threads) { thread in
                    activityThreadRow(thread)
                }
            }
        }
    }

    private func activityThreadRow(_ thread: YavenThreadSummary) -> some View {
        Button {
            agentController.selectThread(thread.id)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                statusDot(for: thread.status)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(thread.title)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)

                        Text(thread.kind.displayTitle)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    if !thread.lastPreview.isEmpty {
                        Text(thread.lastPreview)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    } else {
                        Text(thread.status.displayTitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(thread.requiresAttention ? 0.12 : 0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    private func statusDot(for status: YavenThreadStatus) -> some View {
        Circle()
            .fill(statusColor(status))
            .frame(width: 8, height: 8)
    }

    private var isEmptyState: Bool {
        agentController.state == .idle &&
        !agentController.isActivityInboxVisible &&
        agentController.chatMessages.isEmpty &&
        agentController.responseText.isEmpty &&
        agentController.currentPlan == nil &&
        agentController.executionResult == nil &&
        agentController.errorMessage == nil
    }

    private var emptyState: some View {
        Text("Yaven sees your screens only when you submit. Simple open/send requests can run right away; riskier actions still pause for review.")
            .font(.system(size: 13))
            .foregroundColor(.secondary)
            .lineSpacing(3)
            .padding(.top, 6)
    }

    private var footer: some View {
        Text("Screen context is captured on submit. Simple open/send requests may run directly.")
            .font(.system(size: 11))
            .foregroundColor(.secondary.opacity(0.8))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func approvalCard(_ plan: YavenActionPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(plan.goal)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(plan.risk.rawValue.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(riskColor(plan.risk))
            }

            Text(plan.summary)
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            if let draftText = plan.draftText, !draftText.isEmpty {
                Text(draftText)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(plan.steps.enumerated()), id: \.element.id) { index, step in
                    Text("\(index + 1). \(step.description)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Button("Approve") {
                    agentController.approveCurrentPlan()
                }
                .keyboardShortcut(.return, modifiers: [])

                Button("Cancel") {
                    agentController.cancelCurrentPlan()
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
        )
    }

    private func approvalRequestCard(_ approval: YavenApprovalRequest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(approval.title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(approval.kind == .crmSkill ? "CRM" : "APPROVAL")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.orange)
            }

            Text(approval.summary)
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            if let crmPlan = decodeCRMPlan(from: approval) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(crmPlan.actions.enumerated()), id: \.offset) { index, action in
                        Text("\(index + 1). \(action.summary)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            } else if let mailPlan = decodeMailCleanupPlan(from: approval) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(mailPlan.batches.enumerated()), id: \.element.id) { index, batch in
                        Text("\(index + 1). \(batch.actionTitle) \(batch.messageIds.count) \(batch.category.displayTitle) — \(batch.summary)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }

            HStack {
                Button("Approve") {
                    agentController.approveCurrentPlan()
                }
                .keyboardShortcut(.return, modifiers: [])

                Button("Cancel") {
                    agentController.cancelCurrentPlan()
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
        )
    }

    private func chatBubble(_ message: YavenChatMessage) -> some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 34)
            }

            bubbleText(message.text)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .lineSpacing(3)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(chatBubbleBackground(for: message.role))
                .overlay(chatBubbleBorder(for: message.role))

            if message.role == .assistant {
                Spacer(minLength: 34)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    @ViewBuilder
    private func bubbleText(_ text: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
        } else {
            Text(text)
        }
    }

    private func chatBubbleBackground(for role: YavenChatRole) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(role == .user ? Color.cyan.opacity(0.15) : Color.white.opacity(0.08))
    }

    private func chatBubbleBorder(for role: YavenChatRole) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(role == .user ? Color.cyan.opacity(0.16) : Color.white.opacity(0.08), lineWidth: 0.5)
    }

    private func resultCard(_ result: YavenExecutionResult) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(result.succeeded ? "Completed" : "Stopped")
                .font(.system(size: 13, weight: .semibold))
            Text(result.message)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            if let failedStepDescription = result.failedStepDescription {
                Text("Failed step: \(failedStepDescription)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.red.opacity(0.9))

            if shouldShowPermissionButtons(for: message) {
                HStack {
                    if message.localizedCaseInsensitiveContains("screen recording") {
                        Button("Screen Recording") {
                            agentController.requestScreenRecordingPermission()
                        }
                    }
                    if message.localizedCaseInsensitiveContains("accessibility") {
                        Button("Accessibility") {
                            agentController.requestAccessibilityPermission()
                        }
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.08)))
    }

    private var commandFieldBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(0.10))
    }

    private var commandFieldBorder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
    }

    private func riskColor(_ risk: YavenActionRisk) -> Color {
        switch risk {
        case .low:
            return .green
        case .medium:
            return .yellow
        case .high:
            return .red
        }
    }

    private func statusColor(_ status: YavenThreadStatus) -> Color {
        switch status {
        case .queued:
            return .yellow.opacity(0.8)
        case .running:
            return .cyan
        case .approvalRequired:
            return .orange
        case .completed:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .secondary
        }
    }

    private func decodeCRMPlan(from approval: YavenApprovalRequest) -> HubSpotCRMUpdatePlan? {
        guard approval.kind == .crmSkill,
              let data = approval.payloadJSON.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(HubSpotCRMUpdatePlan.self, from: data)
    }

    private func decodeMailCleanupPlan(from approval: YavenApprovalRequest) -> YavenMailCleanupApprovalPlan? {
        guard approval.kind == .mailCleanup,
              let data = approval.payloadJSON.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(YavenMailCleanupApprovalPlan.self, from: data)
    }

    private func shouldShowPermissionButtons(for message: String) -> Bool {
        message.localizedCaseInsensitiveContains("screen recording") ||
        message.localizedCaseInsensitiveContains("accessibility")
    }

    private func submitCommand() {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else { return }

        agentController.submit(trimmedCommand)
        command = ""
        focusCommandField()
    }

    private func scrollToBottom(_ scrollProxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                scrollProxy.scrollTo("conversation-bottom", anchor: .bottom)
            }
        }
    }

    private func focusCommandField() {
        DispatchQueue.main.async {
            isCommandFieldFocused = true
        }
    }
}
