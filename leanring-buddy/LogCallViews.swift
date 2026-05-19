//
//  LogCallViews.swift
//  leanring-buddy
//
//  UI for the Sales Call Logger workflow.
//  All views are small, composable, and read from LogCallController.
//

import SwiftUI

// MARK: - Log Call chip

/// Small pill button shown in the chat empty state.
struct LogCallChip: View {

    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "phone.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("Log Call")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.88))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }
}

// MARK: - Root workflow view

/// Switches between workflow phases and fills the panel content area.
struct LogCallWorkflowView: View {

    @ObservedObject var controller: LogCallController

    var body: some View {
        Group {
            switch controller.phase {
            case .idle:
                EmptyView()

            case .collectingInput:
                LogCallInputView(controller: controller)

            case .extracting:
                LogCallSpinnerView(message: "Analysing call content…")

            case .awaitingApproval(let actions):
                LogCallApprovalView(actions: actions, controller: controller)

            case .executing:
                LogCallSpinnerView(message: "Running approved actions…")

            case .done(let data, let actions):
                LogCallDoneView(data: data, actions: actions, controller: controller)

            case .failed(let message):
                LogCallFailedView(message: message, controller: controller)
            }
        }
    }
}

// MARK: - Input view

private struct LogCallInputView: View {

    @ObservedObject var controller: LogCallController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Log Sales Call")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Cancel") { controller.cancel() }
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .buttonStyle(.plain)
                    .pointerCursor()
            }

            Text("Paste call notes, a transcript, or Granola output below.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            TextEditor(text: $controller.pastedContent)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(minHeight: 120, maxHeight: 200)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                )

            HStack(spacing: 10) {
                Button("Try demo") {
                    controller.startWithDemo()
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .buttonStyle(.plain)
                .pointerCursor()

                Spacer()

                Button("Analyse") {
                    controller.submitContent()
                }
                .buttonStyle(LogCallPrimaryButtonStyle())
                .disabled(controller.pastedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .pointerCursor()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
        )
    }
}

// MARK: - Spinner view

private struct LogCallSpinnerView: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }
}

// MARK: - Approval view

private struct LogCallApprovalView: View {

    let actions: [WorkflowAction]
    @ObservedObject var controller: LogCallController

    @State private var approvedIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Review proposed actions")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Cancel") { controller.cancel() }
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .buttonStyle(.plain)
                    .pointerCursor()
            }

            ForEach(actions) { action in
                LogCallActionRow(
                    action: action,
                    isApproved: approvedIDs.contains(action.id),
                    onToggle: { toggled in
                        if toggled { approvedIDs.insert(action.id) }
                        else { approvedIDs.remove(action.id) }
                    }
                )
            }

            HStack {
                Button("Select all") {
                    approvedIDs = Set(actions.map(\.id))
                }
                .font(.system(size: 12))
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .pointerCursor()

                Spacer()

                Button("Run \(approvedIDs.count) action\(approvedIDs.count == 1 ? "" : "s")") {
                    controller.executeApproved(approvedIDs: approvedIDs)
                }
                .buttonStyle(LogCallPrimaryButtonStyle())
                .disabled(approvedIDs.isEmpty)
                .pointerCursor()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
        )
        .onAppear {
            // Pre-select all pending actions.
            approvedIDs = Set(actions.filter { $0.status == .pending }.map(\.id))
        }
    }
}

// MARK: - Action row

private struct LogCallActionRow: View {

    let action: WorkflowAction
    let isApproved: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        Button {
            onToggle(!isApproved)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isApproved ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundColor(isApproved ? .cyan : .white.opacity(0.30))
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(action.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    Text(action.description)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isApproved ? Color.cyan.opacity(0.08) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isApproved ? Color.cyan.opacity(0.20) : Color.white.opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }
}

// MARK: - Done view

private struct LogCallDoneView: View {

    let data: SalesCallData
    let actions: [WorkflowAction]
    @ObservedObject var controller: LogCallController

    private var succeededCount: Int { actions.filter { $0.status == .succeeded }.count }
    private var failedCount: Int    { actions.filter { $0.status == .failed }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Call logged")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Done") { controller.cancel() }
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .buttonStyle(.plain)
                    .pointerCursor()
            }

            if !data.callSummary.isEmpty {
                Text(data.callSummary)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
            }

            HStack(spacing: 16) {
                statPill(label: "Done", count: succeededCount, color: .green)
                if failedCount > 0 {
                    statPill(label: "Failed", count: failedCount, color: .red)
                }
            }

            if failedCount > 0 {
                ForEach(actions.filter { $0.status == .failed }) { action in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 12))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.title)
                                .font(.system(size: 12, weight: .medium))
                            if let err = action.errorMessage {
                                Text(err)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
        )
    }

    private func statPill(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(count) \(label)")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Failed view

private struct LogCallFailedView: View {
    let message: String
    @ObservedObject var controller: LogCallController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Extraction failed")
                    .font(.system(size: 13, weight: .semibold))
            }

            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            HStack {
                Button("Try again") {
                    controller.startWithPastedNotes()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .pointerCursor()

                Button("Cancel") {
                    controller.cancel()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .pointerCursor()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.red.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.red.opacity(0.12), lineWidth: 0.5)
        )
    }
}

// MARK: - Button style

struct LogCallPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.75 : 0.88))
            )
    }
}
