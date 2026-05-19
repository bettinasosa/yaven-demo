//
//  YavenNotchView.swift
//  leanring-buddy
//
//  Unified expanding notch view.
//
//  Collapsed — a 250 × 36 pill with the cloud/water mascot.
//  Expanded  — the pill becomes the full-width header of a 560 × (36+content)
//              container that drops the chat panel below it.
//
//  Open triggers: hover (300 ms delay) or tap.
//  Close triggers: tap, Escape, or click outside.
//

import Combine
import SwiftUI

// MARK: - Expansion state

/// Owned by YavenShellController; observed by YavenNotchView.
/// Lets the shell controller open/close and the view toggle by itself.
@MainActor
final class YavenNotchExpansion: ObservableObject {
    @Published var isExpanded: Bool = false {
        didSet { onExpandedChanged?(isExpanded) }
    }
    /// Called on every isExpanded change. Set by YavenShellController to resize the window.
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

enum YavenNotchAnimation {
    static let openDuration: TimeInterval = 0.40
    static let closeDuration: TimeInterval = 0.35

    static let open = Animation.easeInOut(duration: openDuration)
    static let close = Animation.easeInOut(duration: closeDuration)

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

    @AppStorage(OnboardingAppearance.defaultsKey)
    private var selectedAppearanceRaw = OnboardingAppearance.cloud.rawValue

    @State private var isHovering = false
    @State private var hoverOpenTask: Task<Void, Never>? = nil
    @State private var isPulse = false

    // Layout constants kept here so the shell controller can reference them.
    static let pillWidth: CGFloat = 250
    static let pillHeight: CGFloat = 36
    static let panelWidth: CGFloat = 560
    static let panelContentHeight: CGFloat = 200
    static let expandedHeight: CGFloat = pillHeight + panelContentHeight // 236

    private enum NotchMetrics {
        static let collapsedTopCornerRadius: CGFloat = 7
        static let expandedTopCornerRadius: CGFloat = 21
        static let collapsedBottomCornerRadius: CGFloat = 14
        static let expandedBottomCornerRadius: CGFloat = 24
        static let topCurveVerticalOffset: CGFloat = -1
        static let topAnchorFillHeight: CGFloat = 2
        static let horizontalPadding: CGFloat = 32
    }

    var body: some View {
        VStack(spacing: 0) {
            pillStrip
            if expansion.isExpanded {
                panelContent
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity)
                                .animation(YavenNotchAnimation.open),
                            removal: .move(edge: .top).combined(with: .opacity)
                                .animation(YavenNotchAnimation.close)
                        )
                    )
            }
        }
        // Single clip — pill and panel share one seamless rounded shape.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
        .clipShape(
            NotchShape(
                topCornerRadius: topCornerRadius,
                bottomCornerRadius: bottomCornerRadius,
                topCurveVerticalOffset: NotchMetrics.topCurveVerticalOffset
            )
        )
        .overlay(alignment: .top) {
            topAnchorFill
        }
        .compositingGroup()
        .animation(YavenNotchAnimation.expansion(isExpanded: expansion.isExpanded), value: expansion.isExpanded)
        .ignoresSafeArea(edges: .top)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                isPulse = true
            }
        }
        .onChange(of: arrivalCoordinator.isBreathingEnabled) { _, isEnabled in
            guard isEnabled else { return }
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                isPulse = true
            }
        }
        // When the agent opens the activity inbox (e.g. notification tap), open the panel.
        .onChange(of: agentController.isActivityInboxVisible) { _, visible in
            if visible { expansion.open() }
        }
    }

    // MARK: - Pill strip

    /// The persistent top bar — full-width when expanded, pill-width when collapsed.
    private var pillStrip: some View {
        ZStack {
            // Mascot — centered in expanded state, leading in collapsed.
            HStack(spacing: 8) {
                if expansion.isExpanded { Spacer() }
                mascotIcon
                    .scaleEffect(arrivalCoordinator.orbScale, anchor: .top)
                    .opacity(arrivalCoordinator.orbOpacity)
                if agentController.isWorking { workingDot }
                if expansion.isExpanded { Spacer() }
            }
        }
        .padding(.horizontal, NotchMetrics.horizontalPadding)
        .frame(maxWidth: .infinity)
        .frame(height: Self.pillHeight)
        .background(pillBackground)
        // Hover scale — only while collapsed so the pill feels alive.
        .scaleEffect(isHovering && !expansion.isExpanded ? 1.04 : 1.0, anchor: .top)
        .animation(.spring(response: 0.28, dampingFraction: 0.74), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
            if hovering && !expansion.isExpanded {
                hoverOpenTask?.cancel()
                hoverOpenTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled, isHovering else { return }
                    withAnimation(YavenNotchAnimation.open) {
                        expansion.open()
                    }
                }
            } else if !hovering {
                hoverOpenTask?.cancel()
                hoverOpenTask = nil
            }
        }
        .onTapGesture {
            hoverOpenTask?.cancel()
            hoverOpenTask = nil
            withAnimation(YavenNotchAnimation.expansion(isExpanded: !expansion.isExpanded)) {
                if expansion.isExpanded { expansion.close() } else { expansion.open() }
            }
        }
        .pointerCursor()
    }

    // MARK: - Pill internals

    private var pillBackground: some View {
        Color.black
    }

    /// Center strip anchored to the screen edge; padded so the raised top curves stay visible.
    private var topAnchorFill: some View {
        Rectangle()
            .fill(Color.black)
            .frame(height: NotchMetrics.topAnchorFillHeight)
            .padding(.horizontal, NotchMetrics.horizontalPadding)
            .offset(y: NotchMetrics.topCurveVerticalOffset)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var mascotIcon: some View {
        switch selectedAppearance {
        case .cloud:
            Image("CloudMascot")
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: 22, height: 22)
        case .water:
            Circle()
                .fill(RadialGradient(
                    colors: [Color.white.opacity(0.90), Color.white.opacity(0.25)],
                    center: .topLeading,
                    startRadius: 1,
                    endRadius: 13
                ))
                .frame(width: 18, height: 18)
        }
    }

    private var workingDot: some View {
        Circle()
            .fill(Color.white.opacity(isPulse ? 0.90 : 0.30))
            .frame(width: 5, height: 5)
            .animation(
                .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                value: isPulse
            )
    }

    // MARK: - Panel content

    private var panelContent: some View {
        ZStack(alignment: .bottom) {
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
            // Height is driven by the shell controller via onPreferredHeightChange —
            // do not fix it here or expanded widgets will be clipped to the compact height.
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Subtle glass fade at the bottom edge — breaks the fully-black look.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color.white.opacity(0.03), location: 0.6),
                    .init(color: Color.white.opacity(0.07), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 72)
            .allowsHitTesting(false)
        }
    }

    private var selectedAppearance: OnboardingAppearance {
        OnboardingAppearance(rawValue: selectedAppearanceRaw) ?? .cloud
    }

    private var topCornerRadius: CGFloat {
        expansion.isExpanded ? NotchMetrics.expandedTopCornerRadius : NotchMetrics.collapsedTopCornerRadius
    }

    private var bottomCornerRadius: CGFloat {
        expansion.isExpanded ? NotchMetrics.expandedBottomCornerRadius : NotchMetrics.collapsedBottomCornerRadius
    }
}

// MARK: - Notch shape
//
// Ported from boring.notch / DynamicNotchKit.
// The shape is wider at the very top (flush with the screen edge) and narrows
// toward the bottom via quadratic bezier curves — the classic Dynamic Island look.
//
//  ┌──────────────────────────────┐  ← full width, flat at screen top
//  │  ╭──────────────────────╮   │  ← topCornerRadius rounds the inner top
//  │  │                      │   │
//  │  │                      │   │
//     ╯                      ╰      ← bottomCornerRadius sweeps the exit outward

struct NotchShape: Shape {
    /// Small rounding at the top inner corners (pill-meets-screen transition).
    var topCornerRadius: CGFloat
    /// Larger outward sweep at the bottom (where the pill exits the menu bar).
    var bottomCornerRadius: CGFloat
    /// Negative values lift the top shoulder so the curve appears to enter from above the screen edge.
    var topCurveVerticalOffset: CGFloat

    init(
        topCornerRadius: CGFloat = 6,
        bottomCornerRadius: CGFloat = 14,
        topCurveVerticalOffset: CGFloat = 0
    ) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
        self.topCurveVerticalOffset = topCurveVerticalOffset
    }

    // Lets SwiftUI animate corner radii when toggling open/closed.
    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(topCornerRadius, .init(bottomCornerRadius, topCurveVerticalOffset)) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second.first
            topCurveVerticalOffset = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tr = topCornerRadius
        let br = bottomCornerRadius
        let topY = rect.minY + topCurveVerticalOffset

        // Top-left shoulder starts slightly above the window so the visible curve meets the screen edge.
        path.move(to: CGPoint(x: rect.minX, y: topY))

        // Top-left inner corner (small convex rounding).
        path.addQuadCurve(
            to:      CGPoint(x: rect.minX + tr, y: topY + tr),
            control: CGPoint(x: rect.minX + tr, y: topY)
        )

        // Left inner edge ↓
        path.addLine(to: CGPoint(x: rect.minX + tr, y: rect.maxY - br))

        // Bottom-left exit sweep (concave outward — the Dynamic Island corner).
        path.addQuadCurve(
            to:      CGPoint(x: rect.minX + tr + br, y: rect.maxY),
            control: CGPoint(x: rect.minX + tr,      y: rect.maxY)
        )

        // Bottom edge →
        path.addLine(to: CGPoint(x: rect.maxX - tr - br, y: rect.maxY))

        // Bottom-right exit sweep.
        path.addQuadCurve(
            to:      CGPoint(x: rect.maxX - tr,      y: rect.maxY - br),
            control: CGPoint(x: rect.maxX - tr,      y: rect.maxY)
        )

        // Right inner edge ↑
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: topY + tr))

        // Top-right inner corner.
        path.addQuadCurve(
            to:      CGPoint(x: rect.maxX,      y: topY),
            control: CGPoint(x: rect.maxX - tr, y: topY)
        )

        // Top edge ← (back to the lifted origin)
        path.addLine(to: CGPoint(x: rect.minX, y: topY))

        return path
    }
}
