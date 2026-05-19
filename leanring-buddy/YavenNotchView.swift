//
//  YavenNotchView.swift
//  leanring-buddy
//
//  Notch UI and animation ported directly from boring.notch (TheBoredTeam/boring.notch).
//
//  Key structure (exact boring.notch pattern):
//    let styledContent = notchLayout
//        .padding / .background / .clipShape / .overlay / .shadow
//    styledContent
//        .frame(height: isExpanded ? expandedHeight : nil)   ← spring drives this
//        .animation(open/close spring, value: isExpanded)
//

import Combine
import SwiftUI

// MARK: - Expansion state

/// Owned by YavenShellController; observed by YavenNotchView.
@MainActor
final class YavenNotchExpansion: ObservableObject {
    @Published var isExpanded: Bool = false {
        didSet { onExpandedChanged?(isExpanded) }
    }
    var onExpandedChanged: ((Bool) -> Void)?

    func open() {
        guard !isExpanded else { return }
        isExpanded = true
    }

    func close() {
        guard isExpanded else { return }
        isExpanded = false
    }
}

// MARK: - Panel tab

enum YavenPanelTab: CaseIterable, Equatable {
    case chat
    case automations
    case notifications

    var icon: String {
        switch self {
        case .chat:          return "bubble.left.fill"
        case .automations:   return "bolt.fill"
        case .notifications: return "bell.fill"
        }
    }

    var panelTitle: String {
        switch self {
        case .chat:          return "What can Yaven help you with?"
        case .automations:   return "Activity"
        case .notifications: return "Notifications"
        }
    }
}

// MARK: - Animation constants (exact values from boring.notch ContentView.swift)

enum YavenNotchAnimation {
    static let openDuration: TimeInterval  = 0.42
    static let closeDuration: TimeInterval = 0.45

    static let open  = Animation.spring(response: 0.42, dampingFraction: 0.8,  blendDuration: 0)
    static let close = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)

    static func expansion(isExpanded: Bool) -> Animation {
        isExpanded ? open : close
    }
}

// MARK: - View

struct YavenNotchView: View {
    @ObservedObject var expansion: YavenNotchExpansion
    @ObservedObject var agentController: YavenAgentController
    @ObservedObject var arrivalCoordinator: OnboardingArrivalCoordinator
    @ObservedObject var focusCoordinator: YavenPanelFocusCoordinator
    @ObservedObject var cleanupController: YavenCleanupController
    let firstRunPanelMode: YavenFirstRunPanelMode
    let onPreferredHeightChange: (CGFloat) -> Void
    let onFirstRunYes: () -> Void
    let onFirstRunLater: () -> Void
    let onCleanupSkip: () -> Void
    let onCleanupContinue: () -> Void
    let onDraftReply: (NeedsReplyItem) -> Void

    // Layout constants referenced by YavenShellController.
    static let pillWidth: CGFloat        = 250
    static let pillHeight: CGFloat       = 36
    static let panelWidth: CGFloat       = 640
    static let panelContentHeight: CGFloat = 380
    static let expandedHeight: CGFloat   = pillHeight + panelContentHeight // 416

    @State private var isHovering = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var isPulse = false

    // Corner radii from boring.notch cornerRadiusInsets
    private var topCornerRadius: CGFloat    { expansion.isExpanded ? 19 : 6  }
    private var bottomCornerRadius: CGFloat { expansion.isExpanded ? 24 : 14 }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                // ── boring.notch pattern (adapted) ───────────────────────────────
                // frame comes before background so the black fill spans the full
                // animated size (not just the VStack's collapsed natural height).
                // clipShape comes after background so all fill is clipped with
                // rounded corners — no straight-edge artefact during close.
                notchLayout
                    .padding(
                        .horizontal,
                        expansion.isExpanded ? 19 : 14
                    )
                    .padding([.horizontal, .bottom], expansion.isExpanded ? 12 : 0)
                    .frame(width: expansion.isExpanded ? Self.panelWidth : Self.pillWidth,
                           height: expansion.isExpanded ? Self.expandedHeight : Self.pillHeight,
                           alignment: .top)
                    .background(Color.black)
                    .clipShape(
                        NotchShape(
                            topCornerRadius: topCornerRadius,
                            bottomCornerRadius: bottomCornerRadius
                        )
                    )
                    .overlay(alignment: .top) {
                        // 1 px seam fill — prevents hairline gap at screen edge.
                        Rectangle()
                            .fill(Color.black)
                            .frame(height: 1)
                            .padding(.horizontal, topCornerRadius)
                    }
                    .shadow(
                        color: expansion.isExpanded ? .black.opacity(0.7) : .clear,
                        radius: 6
                    )
                    .animation(
                        expansion.isExpanded ? YavenNotchAnimation.open : YavenNotchAnimation.close,
                        value: expansion.isExpanded
                    )
                    .contentShape(Rectangle())
                    .onHover  { handleHover($0) }
                // ─────────────────────────────────────────────────────────────────
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(edges: .top)
        .onAppear { isPulse = true }
        .onChange(of: agentController.isActivityInboxVisible) { _, visible in
            if visible { expansion.open() }
        }
    }

    // MARK: - Notch layout

    @ViewBuilder
    private var notchLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Pill header row — always visible at collapsed height.
            // Tap gesture lives here only so widget bar buttons don't close the panel.
            HStack(spacing: 8) {
                Spacer()
                if agentController.isWorking {
                    workingDot
                }
                Spacer()
            }
            .frame(height: Self.pillHeight)
            .contentShape(Rectangle())
            .onTapGesture { handleTap() }

            // Panel content — inserted/removed with boring.notch's transition.
            if expansion.isExpanded {
                YavenWidgetBar(
                    agentController: agentController,
                    cleanupController: cleanupController,
                    focusCoordinator: focusCoordinator,
                    firstRunPanelMode: firstRunPanelMode,
                    onPreferredHeightChange: onPreferredHeightChange,
                    onFirstRunYes: onFirstRunYes,
                    onFirstRunLater: onFirstRunLater,
                    onCleanupSkip: onCleanupSkip,
                    onCleanupContinue: onCleanupContinue,
                    onDraftReply: onDraftReply
                )
                .transition(.asymmetric(
                    insertion: .opacity.animation(.easeOut(duration: 0.20).delay(0.15)),
                    removal:   .opacity.animation(.easeIn(duration: 0.10))
                ))
                .allowsHitTesting(expansion.isExpanded)
            }
        }
    }

    // MARK: - Working indicator

    private var workingDot: some View {
        Circle()
            .fill(Color.white.opacity(isPulse ? 0.90 : 0.30))
            .frame(width: 5, height: 5)
            .animation(
                .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                value: isPulse
            )
    }

    // MARK: - Interaction handlers

    private func handleTap() {
        hoverTask?.cancel()
        hoverTask = nil
        if expansion.isExpanded { expansion.close() } else { expansion.open() }
    }

    private func handleHover(_ hovering: Bool) {
        isHovering = hovering
        hoverTask?.cancel()
        hoverTask = nil
        guard hovering, !expansion.isExpanded else { return }
        hoverTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, isHovering else { return }
            expansion.open()
        }
    }
}

// MARK: - NotchShape
//
// Exact copy of boring.notch's NotchShape.swift (TheBoredTeam/boring.notch).
// Original source: DynamicNotchKit by MrKai77.

struct NotchShape: Shape {
    private var topCornerRadius: CGFloat
    private var bottomCornerRadius: CGFloat

    init(topCornerRadius: CGFloat? = nil, bottomCornerRadius: CGFloat? = nil) {
        self.topCornerRadius    = topCornerRadius    ?? 6
        self.bottomCornerRadius = bottomCornerRadius ?? 14
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius    = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        path.addQuadCurve(
            to:      CGPoint(x: rect.minX + topCornerRadius, y: rect.minY + topCornerRadius),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY)
        )

        path.addLine(to: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY - bottomCornerRadius))

        path.addQuadCurve(
            to:      CGPoint(x: rect.minX + topCornerRadius + bottomCornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY)
        )

        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius - bottomCornerRadius, y: rect.maxY))

        path.addQuadCurve(
            to:      CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY - bottomCornerRadius),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY)
        )

        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY + topCornerRadius))

        path.addQuadCurve(
            to:      CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY)
        )

        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))

        return path
    }
}
