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

    @AppStorage(OnboardingAppearance.defaultsKey) private var selectedAppearanceRaw = OnboardingAppearance.water.rawValue
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
                tint: Color(red: 0.98, green: 0.82, blue: 0.44),
                action: onNeedsAttention
            )
            .position(
                x: orbCenter.x - sin15 * fanRadius,
                y: orbCenter.y - cos15 * fanRadius
            )

            fanButton(
                icon: "bookmark.fill",
                label: "Remember this",
                tint: Color(red: 0.98, green: 0.66, blue: 0.44),
                action: onRememberThis
            )
            .position(
                x: orbCenter.x - sin50 * fanRadius,
                y: orbCenter.y - cos50 * fanRadius
            )

            fanButton(
                icon: "arrowshape.turn.up.left.fill",
                label: "Help me reply",
                tint: Color(red: 0.80, green: 0.68, blue: 0.98),
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
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(tint.opacity(0.32), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .help(label)
        .shadow(color: tint.opacity(0.30), radius: 6, y: 2)
    }

    // MARK: - Orb body

    @ViewBuilder
    private var orbBody: some View {
        switch selectedAppearance {
        case .water:
            waterOrbBody.clipShape(Circle())
        case .cloud:
            YavenOnboardingMascotView(appearance: .cloud, size: size)
        }
    }

    private var selectedAppearance: OnboardingAppearance {
        OnboardingAppearance(rawValue: selectedAppearanceRaw) ?? .water
    }

    // MARK: - Water orb body

    private var waterOrbBody: some View {
        ZStack {
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.82),
                            Color(red: 1.00, green: 0.92, blue: 0.72).opacity(0.28),
                            Color(red: 0.96, green: 0.80, blue: 0.54).opacity(0.32),
                            Color(red: 0.72, green: 0.58, blue: 0.40).opacity(0.22)
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
                            Color(red: 0.50, green: 0.35, blue: 0.18).opacity(0.16),
                            Color(red: 0.28, green: 0.18, blue: 0.08).opacity(0.16)
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
                            Color.white.opacity(0.52),
                            Color(red: 1.00, green: 0.90, blue: 0.62).opacity(0.22),
                            Color(red: 0.98, green: 0.76, blue: 0.48).opacity(0.12),
                            Color(red: 0.30, green: 0.20, blue: 0.10).opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Ellipse()
                .fill(Color(red: 1.00, green: 0.88, blue: 0.52).opacity(0.60))
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
}
