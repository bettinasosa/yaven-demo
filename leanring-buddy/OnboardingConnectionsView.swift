//
//  OnboardingConnectionsView.swift
//  leanring-buddy
//
//  Stage between form and appearance picker. Gmail is surfaced as essential
//  (Yaven reads your inbox for context). Tools the user picked in the form
//  are shown below as optional. Continue is always available — we don't
//  gate it — but the button copy makes Gmail's importance clear.
//

import SwiftUI

struct OnboardingConnectionsView: View {
    @ObservedObject var onboardingManager: OnboardingManager

    private var gmailConnector: OnboardingConnectorState? {
        onboardingManager.connectors.first { $0.composioKey == "gmail" }
    }

    private var otherConnectors: [OnboardingConnectorState] {
        onboardingManager.connectors.filter { $0.composioKey != "gmail" }
    }

    private var gmailConnected: Bool {
        gmailConnector?.status == .connected
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Connect your tools")
                    .font(OnboardingDS.Fonts.heading(size: 26))
                    .foregroundStyle(OnboardingDS.Colors.cloudCream)
                    .multilineTextAlignment(.center)

                Text("Yaven reads your context to work smarter.")
                    .font(OnboardingDS.Fonts.body(size: 14))
                    .foregroundStyle(OnboardingDS.Colors.steelHaze)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 36)
            .padding(.horizontal, 32)

            Spacer().frame(height: 24)

            ScrollView {
                VStack(spacing: 10) {
                    // Gmail — always shown, marked essential
                    ConnectionRow(
                        connector: gmailConnector ?? OnboardingConnectorState(
                            tool: Tool(name: "Gmail", composioKey: "gmail", logo: "https://cdn.jsdelivr.net/gh/devicons/devicon/icons/google/google-original.svg")
                        ),
                        isEssential: true
                    ) {
                        onboardingManager.connectTool(composioKey: "gmail")
                    }

                    // User-selected tools (excluding Gmail if already in the list)
                    if !otherConnectors.isEmpty {
                        Text("Optional")
                            .font(OnboardingDS.Fonts.caption(size: 11))
                            .fontWeight(.medium)
                            .foregroundStyle(OnboardingDS.Colors.steelHaze.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)

                        ForEach(otherConnectors) { connector in
                            ConnectionRow(connector: connector, isEssential: false) {
                                onboardingManager.connectTool(composioKey: connector.composioKey)
                            }
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 8)
            }

            Spacer()

            VStack(spacing: 8) {
                if !gmailConnected {
                    Text("Yaven works best with Gmail connected.")
                        .font(OnboardingDS.Fonts.caption(size: 12))
                        .foregroundStyle(OnboardingDS.Colors.steelHaze.opacity(0.7))
                        .multilineTextAlignment(.center)
                }

                Button(gmailConnected ? "Continue" : "Skip for now") {
                    onboardingManager.proceedFromConnections()
                }
                .font(OnboardingDS.Fonts.body(size: 14))
                .fontWeight(.medium)
                .foregroundStyle(OnboardingDS.Colors.cloudCream)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(gmailConnected
                    ? OnboardingDS.Colors.skyBlue
                    : OnboardingDS.Colors.glassFill)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            gmailConnected ? Color.clear : OnboardingDS.Colors.glassBorder,
                            lineWidth: 0.5
                        )
                )
                .buttonStyle(.plain)
                .pointerCursor()
                .animation(OnboardingDS.Animation.standard, value: gmailConnected)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 28)
        }
    }
}

// MARK: - Connection Row

private struct ConnectionRow: View {
    let connector: OnboardingConnectorState
    let isEssential: Bool
    let onConnect: () -> Void

    @State private var successScale: CGFloat = 1

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 36, height: 36)
                if !connector.logo.isEmpty {
                    AsyncSVGImage(urlString: connector.logo, size: 26)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(connector.name)
                        .font(OnboardingDS.Fonts.body(size: 14))
                        .fontWeight(.medium)
                        .foregroundStyle(OnboardingDS.Colors.cloudCream)

                    if isEssential {
                        Text("Essential")
                            .font(OnboardingDS.Fonts.caption(size: 10))
                            .fontWeight(.medium)
                            .foregroundStyle(OnboardingDS.Colors.skyBlue)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(OnboardingDS.Colors.skyBlue.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            actionControl
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            connector.status == .connected
                ? Color.green.opacity(0.08)
                : OnboardingDS.Colors.glassFill
        )
        .clipShape(RoundedRectangle(cornerRadius: OnboardingDS.Layout.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OnboardingDS.Layout.cardRadius, style: .continuous)
                .strokeBorder(
                    connector.status == .connected
                        ? Color.green.opacity(0.35)
                        : isEssential && connector.status != .connected
                            ? OnboardingDS.Colors.skyBlue.opacity(0.3)
                            : OnboardingDS.Colors.glassBorder,
                    lineWidth: connector.status == .connected ? 1 : isEssential ? 1 : 0.5
                )
        )
        .scaleEffect(successScale)
        .onChange(of: connector.status) { _, newStatus in
            guard newStatus == .connected else { return }
            // Spring bounce when the connection succeeds
            withAnimation(.spring(response: 0.35, dampingFraction: 0.45)) {
                successScale = 1.03
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6).delay(0.18)) {
                successScale = 1.0
            }
        }
    }

    @ViewBuilder
    private var actionControl: some View {
        switch connector.status {
        case .notConnected:
            Button("Connect", action: onConnect)
                .font(OnboardingDS.Fonts.body(size: 13))
                .fontWeight(.medium)
                .foregroundStyle(OnboardingDS.Colors.cloudCream)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(OnboardingDS.Colors.skyBlue)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .buttonStyle(.plain)
                .pointerCursor()

        case .connecting:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                    .tint(OnboardingDS.Colors.steelHaze)
                Text("Connecting...")
                    .font(OnboardingDS.Fonts.caption())
                    .foregroundStyle(OnboardingDS.Colors.steelHaze)
            }

        case .connected:
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.green.opacity(0.8))
                Text("Connected")
                    .font(OnboardingDS.Fonts.caption())
                    .foregroundStyle(OnboardingDS.Colors.steelHaze)
            }

        case .skipped:
            Text("Skipped")
                .font(OnboardingDS.Fonts.caption())
                .foregroundStyle(OnboardingDS.Colors.steelHaze.opacity(0.45))

        case .unsupported:
            Text("Not available")
                .font(OnboardingDS.Fonts.caption())
                .foregroundStyle(OnboardingDS.Colors.steelHaze.opacity(0.35))
        }
    }
}
