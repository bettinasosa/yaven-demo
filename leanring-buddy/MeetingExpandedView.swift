//
//  MeetingExpandedView.swift
//  leanring-buddy
//
//  Full-panel UI for the Founder Meeting-to-Action Pipeline.
//
//  Phases rendered:
//    idle / sourceSelection → source picker
//    fetchingTranscript / extracting → spinner
//    awaitingApproval → extraction summary + per-action approval cards
//    executing → running action list
//    done → summary + reset
//    error → error message + retry
//

import SwiftUI

struct MeetingExpandedView: View {

    @StateObject private var controller = MeetingPipelineController()
    let onPreferredHeightChange: (CGFloat) -> Void
    @State private var connectedKeys: Set<String> = OnboardingManager.connectedToolKeys
    @State private var connectingToolKey: String? = nil
    @State private var connectError: String? = nil

    // Heights for each phase (content below the header).
    private static let pickerHeight: CGFloat   = 260
    private static let spinnerHeight: CGFloat  = 140
    private static let approvalHeight: CGFloat = 460
    private static let executingHeight: CGFloat = 300
    private static let doneHeight: CGFloat     = 220
    private static let errorHeight: CGFloat    = 160

    var body: some View {
        phaseContent
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: controller.phase.key) { _, _ in
            onPreferredHeightChange(height(for: controller.phase))
        }
        .onAppear {
            connectedKeys = OnboardingManager.connectedToolKeys
            controller.beginSourceSelection()
            onPreferredHeightChange(Self.pickerHeight)
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch controller.phase {
        case .idle, .sourceSelection:
            sourceSelectionView
        case .capturingScreen:
            spinnerView(label: "Reading current screen…")
        case .fetchingTranscript:
            spinnerView(label: "Fetching from Granola…")
        case .extracting:
            spinnerView(label: "Extracting meeting data…")
        case .awaitingApproval(let extraction, let actions):
            approvalView(extraction: extraction, actions: actions)
        case .executing(_, let actions):
            executingView(actions: actions)
        case .done(_, let actions):
            doneView(actions: actions)
        case .error(let message):
            errorView(message: message)
        }
    }

    private func height(for phase: MeetingPipelinePhase) -> CGFloat {
        switch phase {
        case .idle, .sourceSelection:          return Self.pickerHeight
        case .capturingScreen:                 return Self.spinnerHeight
        case .fetchingTranscript, .extracting: return Self.spinnerHeight
        case .awaitingApproval:                return Self.approvalHeight
        case .executing:                       return Self.executingHeight
        case .done:                            return Self.doneHeight
        case .error:                           return Self.errorHeight
        }
    }

    // MARK: - Source selection

    @State private var pasteText: String = ""
    @State private var showPasteEditor: Bool = false
    @FocusState private var isPasteFocused: Bool

    private var sourceSelectionView: some View {
        VStack(spacing: 14) {
            if showPasteEditor {
                pasteEditorView
            } else {
                sourcePicker
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var sourcePicker: some View {
        VStack(spacing: 10) {
            Text("Where are the meeting notes?")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.75))
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                SourceButton(icon: "list.bullet.clipboard.fill", title: "Granola", subtitle: "Latest meeting") {
                    controller.selectGranola()
                }
                SourceButton(icon: "doc.text.fill", title: "Paste notes", subtitle: "Raw text or transcript") {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        showPasteEditor = true
                        isPasteFocused = true
                    }
                }
                SourceButton(icon: "wand.and.sparkles", title: "Demo", subtitle: "Benchmark seed meeting") {
                    controller.selectDemo()
                }
                SourceButton(icon: "rectangle.dashed", title: "Screen", subtitle: "Read visible notes") {
                    controller.selectScreen()
                }
            }
        }
    }

    private var pasteEditorView: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Paste meeting notes")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        showPasteEditor = false
                        pasteText = ""
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.40))
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }

            TextEditor(text: $pasteText)
                .focused($isPasteFocused)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.85))
                .scrollContentBackground(.hidden)
                .background(Color.white.opacity(0.06))
                .cornerRadius(10)
                .frame(height: 140)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.75)
                )

            Button {
                let trimmed = pasteText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                controller.selectPasted(trimmed)
            } label: {
                Text("Extract")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.90))
                    .cornerRadius(9)
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    // MARK: - Spinner

    private func spinnerView(label: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
                .tint(.white.opacity(0.55))
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Approval

    private func approvalView(extraction: MeetingExtraction, actions: [MeetingProposedAction]) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    extractionSummaryCard(extraction)

                    Text("Proposed actions")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.top, 4)

                    ForEach(actions) { action in
                        let requiredTool = action.kind.requiredTool
                        ActionApprovalCard(
                            action: action,
                            requiredTool: requiredTool,
                            isToolConnected: isConnected(requiredTool),
                            isConnecting: connectingToolKey == requiredTool.composioKey
                        ) { status in
                            controller.setActionStatus(action.id, status)
                        } onConnect: {
                            Task { await connect(requiredTool) }
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 14)
                .padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            approvalBottomBar(actions: actions)
        }
    }

    private func extractionSummaryCard(_ e: MeetingExtraction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(e.meetingTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.88))

            Text(e.summary)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.60))
                .lineSpacing(2)

            if !e.attendees.isEmpty {
                Label(e.attendees.joined(separator: ", "), systemImage: "person.2.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(2)
            }

            if !e.actionItems.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Action items")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    ForEach(e.actionItems) { item in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•").foregroundColor(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(item.owner): \(item.task)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.60))
                                if let deadline = item.deadline {
                                    Text(deadline)
                                        .font(.system(size: 10))
                                        .foregroundColor(.orange.opacity(0.75))
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 0.75)
        )
    }

    private func approvalBottomBar(actions: [MeetingProposedAction]) -> some View {
        let availableActionIDs = Set(actions.filter { isConnected($0.kind.requiredTool) }.map(\.id))
        let hasMissingTools = availableActionIDs.count < actions.count

        return VStack(alignment: .leading, spacing: 4) {
            if let connectError {
                Text(connectError)
                    .font(.system(size: 10))
                    .foregroundColor(.red.opacity(0.78))
            }

            HStack(spacing: 10) {
                Button {
                    controller.approveAll(availableActionIDs: availableActionIDs)
                } label: {
                    Text(hasMissingTools ? "Approve connected" : "Approve all")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.75))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(availableActionIDs.isEmpty ? 0.05 : 0.10))
                        )
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .disabled(availableActionIDs.isEmpty)

                Spacer()

                Button {
                    controller.reset()
                    showPasteEditor = false
                    pasteText = ""
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
                .pointerCursor()

                Button {
                    controller.executeApproved()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Run \(controller.approvedCount > 0 ? "\(controller.approvedCount)" : "")")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(controller.approvedCount > 0 ? Color.white.opacity(0.88) : Color.white.opacity(0.20))
                    )
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .disabled(controller.approvedCount == 0)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
        .overlay(Rectangle().frame(height: 0.5).foregroundColor(.white.opacity(0.08)), alignment: .top)
    }

    private func isConnected(_ tool: ComposioRequiredTool) -> Bool {
        connectedKeys.contains(tool.composioKey.uppercased())
    }

    private func connect(_ tool: ComposioRequiredTool) async {
        guard !(OnboardingManager.savedEntityId ?? "").isEmpty else {
            connectError = "Sign in before connecting \(tool.name)."
            return
        }

        connectingToolKey = tool.composioKey
        connectError = nil

        let result = await ComposioConnector.connect(
            composioKey: tool.composioKey,
            entityId: OnboardingManager.savedEntityId ?? ""
        )

        switch result {
        case .connected, .unsupported:
            OnboardingManager.markToolConnected(tool.composioKey)
            connectedKeys = OnboardingManager.connectedToolKeys
        case .timedOut:
            connectError = "\(tool.name) connection timed out."
        case .failed(let message):
            connectError = "Could not connect \(tool.name): \(message)"
        }

        connectingToolKey = nil
    }

    // MARK: - Executing

    private func executingView(actions: [MeetingProposedAction]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Running actions…")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.70))

                ForEach(actions) { action in
                    ActionStatusRow(action: action)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Done

    private func doneView(actions: [MeetingProposedAction]) -> some View {
        let completed = actions.filter { if case .completed = $0.status { return true }; return false }.count
        let failed    = actions.filter { if case .failed    = $0.status { return true }; return false }.count

        return VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundColor(.green.opacity(0.80))

            VStack(spacing: 4) {
                Text("Meeting processed")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                Text(doneSummaryLabel(completed: completed, failed: failed))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Button {
                controller.reset()
                showPasteEditor = false
                pasteText = ""
            } label: {
                Text("Process another")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                    )
            }
            .buttonStyle(.plain)
            .pointerCursor()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func doneSummaryLabel(completed: Int, failed: Int) -> String {
        if failed == 0 {
            return "\(completed) action\(completed == 1 ? "" : "s") completed"
        }
        return "\(completed) completed · \(failed) failed"
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundColor(.orange.opacity(0.80))
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 16)
            Button {
                controller.reset()
                showPasteEditor = false
                pasteText = ""
            } label: {
                Text("Try again")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                    )
            }
            .buttonStyle(.plain)
            .pointerCursor()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Source button

private struct SourceButton: View {
    let icon: String
    let title: String
    let subtitle: String
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(disabled ? .white.opacity(0.18) : .white.opacity(0.60))
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(disabled ? .white.opacity(0.25) : .white.opacity(0.80))
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(disabled ? .white.opacity(0.18) : .white.opacity(0.38))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(disabled ? 0.03 : 0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .disabled(disabled)
    }
}

// MARK: - Action approval card

private struct ActionApprovalCard: View {
    let action: MeetingProposedAction
    let requiredTool: ComposioRequiredTool
    let isToolConnected: Bool
    let isConnecting: Bool
    let onStatusChange: (MeetingActionStatus) -> Void
    let onConnect: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: action.kind.systemIcon)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.45))
                .frame(width: 20, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(action.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.80))
                Text(action.detail)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
                    .lineSpacing(1)
                    .lineLimit(3)

                if !isToolConnected && action.status == .pending {
                    Label("Connect \(requiredTool.name) to run this action", systemImage: "link")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.orange.opacity(0.75))
                }
            }

            Spacer()

            approvalControl
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(cardStroke, lineWidth: 0.75)
        )
    }

    @ViewBuilder
    private var approvalControl: some View {
        switch action.status {
        case .pending:
            HStack(spacing: 6) {
                Button {
                    onStatusChange(.rejected)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.40))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .pointerCursor()

                if isToolConnected {
                    Button {
                        onStatusChange(.approved)
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.white.opacity(0.85)))
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                } else {
                    Button(action: onConnect) {
                        HStack(spacing: 5) {
                            if isConnecting {
                                ProgressView()
                                    .controlSize(.mini)
                                    .tint(.black.opacity(0.75))
                            } else {
                                Image(systemName: "link")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            Text(isConnecting ? "Connecting" : "Connect")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 9)
                        .frame(height: 26)
                        .background(Capsule().fill(Color.white.opacity(0.85)))
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                    .disabled(isConnecting)
                }
            }

        case .approved:
            Button {
                onStatusChange(.pending)
            } label: {
                Text("Approved")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.green.opacity(0.85))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Color.green.opacity(0.15))
                    )
            }
            .buttonStyle(.plain)
            .pointerCursor()

        case .rejected:
            Button {
                onStatusChange(.pending)
            } label: {
                Text("Skipped")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Color.white.opacity(0.07))
                    )
            }
            .buttonStyle(.plain)
            .pointerCursor()

        default:
            EmptyView()
        }
    }

    private var cardBackground: Color {
        switch action.status {
        case .approved: return Color.green.opacity(0.08)
        case .rejected: return Color.white.opacity(0.03)
        default:        return isToolConnected ? Color.white.opacity(0.06) : Color.orange.opacity(0.05)
        }
    }

    private var cardStroke: Color {
        switch action.status {
        case .approved: return Color.green.opacity(0.25)
        case .rejected: return Color.white.opacity(0.06)
        default:        return isToolConnected ? Color.white.opacity(0.09) : Color.orange.opacity(0.14)
        }
    }
}

// MARK: - Action status row (executing / done)

private struct ActionStatusRow: View {
    let action: MeetingProposedAction

    var body: some View {
        HStack(spacing: 10) {
            statusIcon
                .frame(width: 20, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.78))
                Text(action.status.label)
                    .font(.system(size: 11))
                    .foregroundColor(statusLabelColor)
            }

            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch action.status {
        case .executing:
            ProgressView()
                .controlSize(.mini)
                .tint(.white.opacity(0.55))
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.green.opacity(0.80))
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.red.opacity(0.75))
        case .rejected:
            Image(systemName: "minus.circle")
                .font(.system(size: 14))
                .foregroundColor(.secondary.opacity(0.60))
        default:
            Image(systemName: action.kind.systemIcon)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.35))
        }
    }

    private var statusLabelColor: Color {
        switch action.status {
        case .completed: return .green.opacity(0.80)
        case .failed:    return .red.opacity(0.75)
        case .executing: return .cyan.opacity(0.80)
        case .rejected:  return .secondary
        default:         return .secondary
        }
    }
}
