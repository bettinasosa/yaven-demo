//
//  YavenOrbView.swift
//  leanring-buddy
//

import SwiftUI

struct YavenOrbView: View {
    /// Diameter of the orb circle.
    let size: CGFloat
    /// Full extended window width — the orb sits in the bottom-right corner;
    /// the remaining transparent area holds the hover quick-action fan.
    let windowWidth: CGFloat
    let windowHeight: CGFloat

    @ObservedObject var agentController: YavenAgentController
    @ObservedObject var arrivalCoordinator: OnboardingArrivalCoordinator
    let onTogglePanel: () -> Void
    /// "What needs my attention right now?"
    let onNeedsAttention: () -> Void
    /// "Remember what's on my screen"
    let onRememberThis: () -> Void
    /// "Help me reply to this"
    let onHelpReply: () -> Void

    @AppStorage(OnboardingAppearance.defaultsKey) private var selectedAppearanceRaw = OnboardingAppearance.defaultAppearance.rawValue
    @State private var isPulseExpanded = false
    @State private var isHovering = false

    /// Orb centre in SwiftUI (y-down) coordinates within the extended window.
    private var orbCenter: CGPoint {
        CGPoint(x: windowWidth - size / 2, y: windowHeight - size / 2)
    }

    var body: some View {
        ZStack {
            if isHovering {
                quickActionFan
                    .transition(
                        .scale(scale: 0.5, anchor: .bottomTrailing)
                        .combined(with: .opacity)
                    )
            }

            orbBody
                .scaleEffect(arrivalCoordinator.orbScale)
                .opacity(arrivalCoordinator.orbOpacity)
                .frame(width: size, height: size)
                .position(orbCenter)

            // Circular tap target — orb area only, not the transparent hover region.
            Color.clear
                .frame(width: size, height: size)
                .contentShape(Circle())
                .position(orbCenter)
                .onTapGesture { onTogglePanel() }
        }
        .frame(width: windowWidth, height: windowHeight)
        .scaleEffect(
            agentController.isWorking && isPulseExpanded ? 1.03 : 1,
            anchor: .bottomTrailing
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.74), value: isHovering)
        .onHover { isHovering = $0 }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) {
                isPulseExpanded = true
            }
        }
        .onChange(of: arrivalCoordinator.isBreathingEnabled) { _, isEnabled in
            guard isEnabled else { return }
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                isPulseExpanded = true
            }
        }
    }

    // MARK: - Quick-action fan
    //
    // Three buttons fan from the orb centre upward and to the left.
    // Fan radius = 80 pt; angles measured from straight-up going left:
    //   Button 1 → 15°  (upper right-ish)
    //   Button 2 → 50°  (middle diagonal)
    //   Button 3 → 80°  (nearly horizontal, leftmost)
    //
    // Min gap between button centres ≈ 41 pt > button diameter (30 pt) → no overlap.

    private var quickActionFan: some View {
        ZStack {
            fanButton(
                icon: "exclamationmark.circle.fill",
                label: "What needs attention?",
                action: onNeedsAttention
            )
            .position(
                x: orbCenter.x - sin15 * fanRadius,
                y: orbCenter.y - cos15 * fanRadius
            )

            fanButton(
                icon: "bookmark.fill",
                label: "Remember this",
                action: onRememberThis
            )
            .position(
                x: orbCenter.x - sin50 * fanRadius,
                y: orbCenter.y - cos50 * fanRadius
            )

            fanButton(
                icon: "arrowshape.turn.up.left.fill",
                label: "Help me reply",
                action: onHelpReply
            )
            .position(
                x: orbCenter.x - sin80 * fanRadius,
                y: orbCenter.y - cos80 * fanRadius
            )
        }
    }

    // Pre-computed trig constants so the fan positions are easy to read and adjust.
    private let fanRadius: CGFloat = 80
    private let sin15: CGFloat = 0.2588
    private let cos15: CGFloat = 0.9659
    private let sin50: CGFloat = 0.7660
    private let cos50: CGFloat = 0.6428
    private let sin80: CGFloat = 0.9848
    private let cos80: CGFloat = 0.1736

    private func fanButton(
        icon: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        QuickActionFanButton(
            icon: icon,
            label: label,
            isGlassMode: selectedAppearance.isGlassMode,
            action: action
        )
    }

    // MARK: - Orb body

    @ViewBuilder
    private var orbBody: some View {
        switch selectedAppearance {
        case .black:
            blackOrbBody.clipShape(Circle())
        case .glass:
            glassOrbBody.clipShape(Circle())
        }
    }

    private var selectedAppearance: OnboardingAppearance {
        OnboardingAppearance.fromStoredRawValue(selectedAppearanceRaw)
    }

    // MARK: - Orb bodies

    private var blackOrbBody: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(white: 0.18),
                            Color(white: 0.03),
                            Color.black
                        ],
                        center: UnitPoint(x: 0.30, y: 0.18),
                        startRadius: 1,
                        endRadius: size * 0.76
                    )
                )

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.24),
                            Color.white.opacity(0.06),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Ellipse()
                .fill(Color.white.opacity(0.28))
                .frame(width: size * 0.40, height: size * 0.14)
                .blur(radius: 3)
                .offset(x: -size * 0.16, y: -size * 0.22)
        }
    }

    private var glassOrbBody: some View {
        ZStack {
            glassOrbBase

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.46),
                            Color(red: 0.74, green: 0.64, blue: 0.50).opacity(0.34),
                            Color(red: 0.50, green: 0.46, blue: 0.38).opacity(0.18),
                            Color(red: 0.18, green: 0.18, blue: 0.17).opacity(0.08)
                        ],
                        center: UnitPoint(x: 0.28, y: 0.18),
                        startRadius: 1,
                        endRadius: size * 0.82
                    )
                )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.clear,
                            Color(red: 0.88, green: 0.78, blue: 0.62).opacity(0.08),
                            Color(red: 0.18, green: 0.18, blue: 0.17).opacity(0.06)
                        ],
                        center: UnitPoint(x: 0.72, y: 0.76),
                        startRadius: size * 0.14,
                        endRadius: size * 0.64
                    )
                )

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.22),
                            Color.white.opacity(0.08),
                            Color(red: 0.88, green: 0.78, blue: 0.62).opacity(0.08),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Ellipse()
                .fill(Color.white.opacity(0.60))
                .frame(width: size * 0.46, height: size * 0.18)
                .blur(radius: 5)
                .offset(x: -size * 0.15, y: -size * 0.21)

            Ellipse()
                .fill(Color.white.opacity(0.62))
                .frame(width: size * 0.20, height: size * 0.08)
                .blur(radius: 1.5)
                .offset(x: -size * 0.22, y: -size * 0.25)
        }
    }

    @ViewBuilder
    private var glassOrbBase: some View {
        if #available(macOS 26.0, *) {
            Color.white.opacity(0.001)
                .glassEffect(
                    .regular
                        .interactive(true)
                        .tint(Color(red: 0.66, green: 0.56, blue: 0.42).opacity(0.18)),
                    in: Circle()
                )
        } else {
            VisualEffectBackground(material: .underWindowBackground, blendingMode: .behindWindow)
                .clipShape(Circle())
                .overlay(Circle().fill(Color.white.opacity(0.08)))
        }
    }
}

private struct QuickActionFanButton: View {
    let icon: String
    let label: String
    let isGlassMode: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(isHovering ? 0.92 : 0.76))
                .frame(width: 32, height: 32)
                .background { buttonBackground }
                .overlay(Circle().stroke(Color.white.opacity(isHovering ? 0.30 : 0.18), lineWidth: 0.8))
        }
        .buttonStyle(QuickActionFanButtonStyle())
        .scaleEffect(isHovering ? 1.08 : 1)
        .shadow(color: Color.black.opacity(isHovering ? 0.30 : 0.22), radius: isHovering ? 9 : 6, y: isHovering ? 3 : 2)
        .help(label)
        .pointerCursor()
        .accessibilityLabel(label)
        .onHover { hovering in
            withAnimation(.spring(response: 0.22, dampingFraction: 0.70)) {
                isHovering = hovering
            }
        }
    }

    @ViewBuilder
    private var buttonBackground: some View {
        if isGlassMode, #available(macOS 26.0, *) {
            Color.white.opacity(0.001)
                .glassEffect(
                    .clear
                        .interactive(true)
                        .tint(Color.white.opacity(isHovering ? 0.14 : 0.07)),
                    in: Circle()
                )
        } else {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().fill(Color.white.opacity(isHovering ? 0.12 : 0.06)))
        }
    }
}

private struct QuickActionFanButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.72), value: configuration.isPressed)
    }
}
