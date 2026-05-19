//
//  YavenLogCallWidget.swift
//  leanring-buddy
//
//  Compact widget card for the Sales Call Logger workflow.
//  Lets the user choose which connected tools should receive call output.
//

import SwiftUI

struct YavenLogCallWidget: View {

    @ObservedObject var controller: LogCallController
    @State private var connectedKeys: Set<String> = OnboardingManager.connectedToolKeys
    @State private var connectingToolKey: String? = nil
    @State private var connectError: String? = nil

    private static let supportedTools: [ComposioRequiredTool] = [
        .init(name: "HubSpot", composioKey: "HUBSPOT", icon: "person.fill"),
        .init(name: "Gmail", composioKey: "GMAIL", icon: "envelope.fill"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            toolSetup
            Spacer(minLength: 0)
            phaseContent
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(widgetBackground)
        .overlay(widgetBorder)
        .onAppear {
            connectedKeys = OnboardingManager.connectedToolKeys
            controller.refreshToolSelectionFromConnections()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: "phone.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.45))
            Text("Log Call")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.45))
            Spacer()
            if case .idle = controller.phase { } else {
                Button {
                    controller.cancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
        }
    }

    // MARK: - Phase content

    @ViewBuilder
    private var phaseContent: some View {
        switch controller.phase {
        case .idle:
            idlePrompt

        case .collectingInput:
            inputContent

        case .extracting:
            spinnerRow("Analysing call…")

        case .awaitingApproval(let actions):
            approvalContent(actions)

        case .executing:
            spinnerRow("Running actions…")

        case .done(_, let actions):
            doneContent(actions)

        case .failed(let message):
            failedContent(message)
        }
    }

    // MARK: - Idle

    private var idlePrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Log a sales call using the tools you choose.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.45))
                .lineLimit(2)
                .lineSpacing(2)

            HStack(spacing: 6) {
                Button("Read screen") {
                    controller.startFromScreen()
                }
                .buttonStyle(WidgetChipStyle())
                .disabled(controller.selectedToolKeys.isEmpty)
                .pointerCursor()

                Button("Paste notes") {
                    controller.startWithPastedNotes()
                }
                .buttonStyle(WidgetChipStyle(isDim: true))
                .disabled(controller.selectedToolKeys.isEmpty)
                .pointerCursor()

                Button("Demo") {
                    controller.startWithDemo()
                }
                .buttonStyle(WidgetChipStyle(isDim: true))
                .pointerCursor()
            }
        }
    }

    // MARK: - Tool setup

    private var toolSetup: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Self.supportedTools, id: \.composioKey) { tool in
                    toolButton(tool)
                }
            }

            if let connectError {
                Text(connectError)
                    .font(.system(size: 10))
                    .foregroundColor(.red.opacity(0.78))
                    .lineLimit(2)
            }
        }
    }

    private func toolButton(_ tool: ComposioRequiredTool) -> some View {
        let key = tool.composioKey.uppercased()
        let isConnected = connectedKeys.contains(key)
        let isSelected = controller.selectedToolKeys.contains(key)
        let isConnecting = connectingToolKey == key

        return Button {
            if isConnected {
                controller.setTool(key, enabled: !isSelected)
            } else {
                Task { await connect(tool) }
            }
        } label: {
            HStack(spacing: 5) {
                if isConnecting {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white.opacity(0.55))
                } else {
                    Image(systemName: isConnected && isSelected ? "checkmark.circle.fill" : tool.icon)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(isConnected ? tool.name : "Connect \(tool.name)")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(isConnected && isSelected ? .black : .white.opacity(0.55))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isConnected && isSelected ? Color.white.opacity(0.88) : Color.white.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .disabled(isConnecting)
    }

    private func connect(_ tool: ComposioRequiredTool) async {
        guard !(OnboardingManager.savedEntityId ?? "").isEmpty else {
            connectError = "Sign in before connecting \(tool.name)."
            return
        }

        connectingToolKey = tool.composioKey.uppercased()
        connectError = nil

        let result = await ComposioConnector.connect(
            composioKey: tool.composioKey,
            entityId: OnboardingManager.savedEntityId ?? ""
        )

        switch result {
        case .connected, .unsupported:
            OnboardingManager.markToolConnected(tool.composioKey)
            connectedKeys = OnboardingManager.connectedToolKeys
            controller.setTool(tool.composioKey, enabled: true)
        case .timedOut:
            connectError = "\(tool.name) connection timed out."
        case .failed(let message):
            connectError = "Could not connect \(tool.name): \(message)"
        }

        connectingToolKey = nil
    }

    // MARK: - Input

    private var inputContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $controller.pastedContent)
                .font(.system(size: 11))
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 56)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )

            Button("Analyse") {
                controller.submitContent()
            }
            .buttonStyle(WidgetChipStyle())
            .disabled(
                controller.pastedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || controller.selectedToolKeys.isEmpty
            )
            .pointerCursor()
        }
    }

    // MARK: - Approval

    private func approvalContent(_ actions: [WorkflowAction]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(actions.count) action\(actions.count == 1 ? "" : "s") ready")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.75))

            ForEach(actions.prefix(3)) { action in
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.cyan.opacity(0.6))
                        .frame(width: 4, height: 4)
                    Text(action.title)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            if actions.count > 3 {
                Text("+\(actions.count - 3) more")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.35))
            }

            Button("Run all") {
                controller.executeApproved(approvedIDs: Set(actions.map(\.id)))
            }
            .buttonStyle(WidgetChipStyle())
            .disabled(actions.isEmpty)
            .pointerCursor()
        }
    }

    // MARK: - Done

    private func doneContent(_ actions: [WorkflowAction]) -> some View {
        let succeeded = actions.filter { $0.status == .succeeded }.count
        let failed    = actions.filter { $0.status == .failed }.count

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 12))
                Text("Logged")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))
            }
            Text("\(succeeded) done\(failed > 0 ? ", \(failed) failed" : "")")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.40))
            Button("New call") {
                controller.cancel()
            }
            .buttonStyle(WidgetChipStyle(isDim: true))
            .pointerCursor()
        }
    }

    // MARK: - Failed

    private func failedContent(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(.red.opacity(0.75))
                .lineLimit(3)
            Button("Retry") {
                controller.startWithPastedNotes()
            }
            .buttonStyle(WidgetChipStyle())
            .pointerCursor()
        }
    }

    // MARK: - Spinner

    private func spinnerRow(_ label: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.mini)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.45))
        }
    }

    // MARK: - Styling

    private var widgetBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(0.055))
    }

    private var widgetBorder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color.white.opacity(0.09), lineWidth: 0.75)
    }
}

// MARK: - Chip button style

struct WidgetChipStyle: ButtonStyle {
    var isDim: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(isDim ? .white.opacity(0.45) : .black)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isDim ? Color.white.opacity(0.10) : Color.white.opacity(configuration.isPressed ? 0.72 : 0.85))
            )
    }
}
