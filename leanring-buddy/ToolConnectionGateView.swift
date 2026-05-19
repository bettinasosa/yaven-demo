//
//  ToolConnectionGateView.swift
//  leanring-buddy
//
//  Reusable gate that checks whether required Composio tools are connected.
//  Shows a connection prompt instead of the child content when tools are missing.
//

import SwiftUI

struct ComposioRequiredTool {
    let name: String
    let composioKey: String
    let icon: String
}

struct ToolConnectionGateView<Content: View>: View {

    let tools: [ComposioRequiredTool]
    @ViewBuilder let content: () -> Content

    @State private var connectedKeys: Set<String> = OnboardingManager.connectedToolKeys
    @State private var connectingKey: String? = nil
    @State private var connectError: String? = nil

    private var entityId: String { OnboardingManager.savedEntityId ?? "" }

    private var missingTools: [ComposioRequiredTool] {
        tools.filter { !connectedKeys.contains($0.composioKey.uppercased()) }
    }

    var body: some View {
        if entityId.isEmpty {
            accountGate
        } else if missingTools.isEmpty {
            content()
        } else {
            connectionGate
        }
    }

    // MARK: - No account gate

    private var accountGate: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.35))

            VStack(spacing: 5) {
                Text("Sign in to continue")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.80))
                Text("Complete setup to use this feature.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Tool connection gate

    private var connectionGate: some View {
        VStack(spacing: 16) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 28))
                .foregroundColor(.white.opacity(0.35))

            VStack(spacing: 5) {
                Text(missingTools.count == 1
                     ? "Connect \(missingTools[0].name)"
                     : "Connect your tools")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.80))
                Text("Required to run this automation.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(missingTools, id: \.composioKey) { tool in
                    toolConnectRow(tool)
                }
            }
            .padding(.horizontal, 32)

            if let error = connectError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func toolConnectRow(_ tool: ComposioRequiredTool) -> some View {
        let isConnecting = connectingKey == tool.composioKey
        let isConnected  = connectedKeys.contains(tool.composioKey.uppercased())

        return HStack(spacing: 10) {
            Image(systemName: tool.icon)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.55))
                .frame(width: 20)

            Text(tool.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.80))

            Spacer()

            if isConnected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green.opacity(0.80))
            } else if isConnecting {
                ProgressView()
                    .controlSize(.mini)
                    .tint(.white.opacity(0.55))
                Text("Waiting…")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                Button {
                    Task { await triggerConnect(tool) }
                } label: {
                    Text("Connect")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.88)))
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(isConnected ? Color.green.opacity(0.30) : Color.white.opacity(0.08), lineWidth: 0.75)
        )
    }

    // MARK: - Connect action

    private func triggerConnect(_ tool: ComposioRequiredTool) async {
        connectingKey = tool.composioKey
        connectError = nil

        let result = await ComposioConnector.connect(
            composioKey: tool.composioKey,
            entityId: entityId
        )

        switch result {
        case .connected:
            connectedKeys = OnboardingManager.connectedToolKeys
        case .timedOut:
            connectError = "Connection timed out. Try again."
        case .unsupported:
            // Mark as connected so the gate passes — tool doesn't need OAuth.
            OnboardingManager.markToolConnected(tool.composioKey)
            connectedKeys = OnboardingManager.connectedToolKeys
        case .failed(let msg):
            connectError = "Could not connect: \(msg)"
        }

        connectingKey = nil
    }
}
