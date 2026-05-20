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
    @Published var dragProgress: CGFloat = 0 {
        didSet { onDragProgressChanged?(dragProgress) }
    }
    var onExpandedChanged: ((Bool) -> Void)?
    var onDragProgressChanged: ((CGFloat) -> Void)?

    func open() {
        guard !isExpanded else { return }
        isExpanded = true
        setDragProgress(0)
    }

    func close() {
        guard isExpanded || dragProgress > 0 else { return }
        setDragProgress(0)
        guard isExpanded else { return }
        isExpanded = false
    }

    func setDragProgress(_ progress: CGFloat) {
        let boundedProgress = min(max(progress, 0), 1)
        guard abs(dragProgress - boundedProgress) > 0.001 else { return }
        dragProgress = boundedProgress
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
    static let pillWidth: CGFloat        = 180
    static let pillHeight: CGFloat       = 33
    static let panelWidth: CGFloat       = 600
    static let panelContentHeight: CGFloat = 380
    static let expandedHeight: CGFloat   = pillHeight + panelContentHeight // Default 414
    private static let minimumPanelContentHeight: CGFloat = 180
    private static let maximumPanelContentHeight: CGFloat = 620

    @State private var isHovering = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var isPulse = false
    @State private var isApprovalCueHovering = false
    @State private var isDraggingExpansion = false
    @State private var shineProgress: CGFloat = 0.28
    @State private var preferredPanelContentHeight = Self.panelContentHeight
    @AppStorage(OnboardingAppearance.defaultsKey) private var selectedAppearanceRaw = OnboardingAppearance.defaultAppearance.rawValue

    // Corner radii from boring.notch cornerRadiusInsets
    private var topCornerRadius: CGFloat    { interpolate(from: 6, to: 19)  }
    private var bottomCornerRadius: CGFloat { interpolate(from: 14, to: 24) }
    private var selectedAppearance: OnboardingAppearance {
        OnboardingAppearance.fromStoredRawValue(selectedAppearanceRaw)
    }
    private var expansionProgress: CGFloat {
        expansion.isExpanded ? 1 : expansion.dragProgress
    }
    private var isVisuallyExpanded: Bool {
        expansionProgress > 0.001
    }
    private var currentWidth: CGFloat {
        interpolate(from: Self.pillWidth, to: Self.panelWidth)
    }
    private var expandedContentHeight: CGFloat {
        Self.clampedPanelContentHeight(preferredPanelContentHeight)
    }
    private var currentExpandedHeight: CGFloat {
        Self.pillHeight + expandedContentHeight
    }
    private var currentHeight: CGFloat {
        interpolate(from: Self.pillHeight, to: currentExpandedHeight)
    }
    private var shellHorizontalPadding: CGFloat {
        interpolate(from: 14, to: 19)
    }
    private var shellBottomPadding: CGFloat {
        interpolate(from: 0, to: 12)
    }
    private var panelContentOpacity: Double {
        let progress = (expansionProgress - 0.55) / 0.45
        return Double(min(max(progress, 0), 1))
    }
    private var shouldRenderPanelContent: Bool {
        expansion.isExpanded || expansion.dragProgress > 0.55
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                // ── boring.notch pattern (adapted) ───────────────────────────────
                // frame comes before background so the selected shell fill spans
                // the full animated size (not just the VStack's collapsed natural height).
                // clipShape comes after background so all fill is clipped with
                // rounded corners — no straight-edge artefact during close.
                notchLayout
                    .padding(
                        .horizontal,
                        shellHorizontalPadding
                    )
                    .padding([.horizontal, .bottom], shellBottomPadding)
                    .frame(width: currentWidth,
                           height: currentHeight,
                           alignment: .top)
                    .background { notchBackground }
                    .clipShape(
                        NotchShape(
                            topCornerRadius: topCornerRadius,
                            bottomCornerRadius: bottomCornerRadius
                        )
                    )
                    .overlay {
                        notchBorder
                    }
                    .overlay(alignment: .top) {
                        // 1 px seam fill — prevents hairline gap at screen edge.
                        Rectangle()
                            .fill(topSeamColor)
                            .frame(height: 1)
                            .padding(.horizontal, topCornerRadius)
                    }
                    .shadow(
                        color: isVisuallyExpanded ? notchShadowColor : .clear,
                        radius: selectedAppearance.isGlassMode ? interpolate(from: 8, to: 22) : 6,
                        y: selectedAppearance.isGlassMode ? interpolate(from: 2, to: 12) : 0
                    )
                    .animation(
                        expansion.isExpanded ? YavenNotchAnimation.open : YavenNotchAnimation.close,
                        value: expansion.isExpanded
                    )
                    .contentShape(Rectangle())
                    .gesture(collapsedExpansionDrag)
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

    // MARK: - Appearance

    @ViewBuilder
    private var notchBackground: some View {
        if selectedAppearance.isGlassMode {
            ZStack {
                glassSurface
                glassLensTint
                glassSurfaceHighlights

                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.white.opacity(interpolate(from: 0.10, to: 0.16)),
                        Color.white.opacity(interpolate(from: 0.04, to: 0.08)),
                        Color.clear
                    ],
                    startPoint: UnitPoint(x: shineProgress - 0.44, y: -0.10),
                    endPoint: UnitPoint(x: shineProgress + 0.24, y: 1.06)
                )
                .blendMode(.plusLighter)
            }
        } else {
            Color.black
        }
    }

    @ViewBuilder
    private var glassSurface: some View {
        let shape = NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius
        )

        if #available(macOS 26.0, *) {
            // Native Liquid Glass — .regular gives the standard bright Apple glass preset.
            // No dark tint overlays; the system handles surface rendering.
            Color.white.opacity(0.001)
                .glassEffect(
                    .regular
                        .interactive(true),
                    in: shape
                )
        } else {
            ZStack {
                VisualEffectBackground(material: .underWindowBackground, blendingMode: .behindWindow)

                shape
                    .fill(Color(red: 0.18, green: 0.18, blue: 0.18).opacity(interpolate(from: 0.08, to: 0.13)))

                shape
                    .fill(Color.white.opacity(interpolate(from: 0.015, to: 0.025)))

                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(interpolate(from: 0.045, to: 0.065)),
                                Color.clear,
                                Color.black.opacity(interpolate(from: 0.015, to: 0.030))
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
    }

    @ViewBuilder
    private var glassLensTint: some View {
        if #available(macOS 26.0, *) {
            // Native glass handles lens tinting — skip the dark overlay.
            EmptyView()
        } else {
            NotchShape(
                topCornerRadius: topCornerRadius,
                bottomCornerRadius: bottomCornerRadius
            )
            .fill(Color(red: 0.18, green: 0.18, blue: 0.18).opacity(interpolate(from: 0.08, to: 0.12)))
        }
    }

    private var glassSurfaceHighlights: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.white.opacity(interpolate(from: 0.12, to: 0.18)),
                    Color.white.opacity(0.030),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.white.opacity(interpolate(from: 0.12, to: 0.18)),
                    Color(red: 0.86, green: 0.90, blue: 0.92).opacity(interpolate(from: 0.05, to: 0.08)),
                    Color.clear
                ],
                center: UnitPoint(x: 0.16, y: 0.02),
                startRadius: 4,
                endRadius: interpolate(from: 160, to: 420)
            )

            LinearGradient(
                colors: [
                    Color.white.opacity(interpolate(from: 0.12, to: 0.18)),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.34)
            )

            RadialGradient(
                colors: [
                    Color.white.opacity(interpolate(from: 0.08, to: 0.12)),
                    Color.clear
                ],
                center: UnitPoint(x: 0.88, y: 0.90),
                startRadius: 0,
                endRadius: interpolate(from: 140, to: 360)
            )
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var notchBorder: some View {
        if selectedAppearance.isGlassMode, #unavailable(macOS 26.0) {
            // macOS 26+: native glass renders its own edges — manual stroke not needed.
            // macOS 25 and below: draw a subtle gradient stroke to define the glass edge.
            NotchShape(
                topCornerRadius: topCornerRadius,
                bottomCornerRadius: bottomCornerRadius
            )
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(interpolate(from: 0.46, to: 0.56)),
                        Color.white.opacity(interpolate(from: 0.18, to: 0.24)),
                        Color.white.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.65
            )
        }
    }

    private var topSeamColor: Color {
        selectedAppearance.isGlassMode ? Color.white.opacity(0.16) : Color.black
    }

    private var notchShadowColor: Color {
        selectedAppearance.isGlassMode ? Color.clear : Color.black.opacity(0.7)
    }

    // MARK: - Notch layout

    @ViewBuilder
    private var notchLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Pill header row — always visible at collapsed height.
            // Tap gesture lives here only so widget bar buttons don't close the panel.
            HStack(spacing: 8) {
                Spacer()
                if !isVisuallyExpanded && agentController.needsApprovalThreads.count > 0 {
                    approvalCue
                } else if agentController.isWorking {
                    workingDot
                }
                Spacer()
            }
            .frame(height: Self.pillHeight)
            .contentShape(Rectangle())
            .onTapGesture { handleTap() }

            // Panel content — inserted/removed with boring.notch's transition.
            if shouldRenderPanelContent {
                YavenWidgetBar(
                    agentController: agentController,
                    cleanupController: cleanupController,
                    focusCoordinator: focusCoordinator,
                    firstRunPanelMode: firstRunPanelMode,
                    onPreferredHeightChange: handlePreferredHeightChange,
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
                .opacity(panelContentOpacity)
                .scaleEffect(interpolate(from: 1.04, to: 1), anchor: .top)
                .blur(radius: interpolate(from: 5, to: 0))
                .allowsHitTesting(expansion.isExpanded)
            }
        }
    }

    @ViewBuilder
    private var approvalCue: some View {
        if selectedAppearance.isGlassMode {
            if #available(macOS 26.0, *) {
                approvalCueButton
                    .buttonStyle(.glass(.clear.interactive(true).tint(Color.white.opacity(0.055))))
            } else {
                approvalCueButton
                    .buttonStyle(MenuCueButtonStyle())
            }
        } else {
            approvalCueButton
                .buttonStyle(MenuCueButtonStyle())
        }
    }

    private var approvalCueButton: some View {
        Button {
            openApprovalsPanel()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(agentController.needsApprovalThreads.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(approvalCueBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.44),
                                Color.orange.opacity(0.28),
                                selectedAppearance.isGlassMode
                                    ? Color.white.opacity(0.10)
                                    : Color.black.opacity(0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            )
            .shadow(color: Color.orange.opacity(isApprovalCueHovering ? 0.34 : 0.18), radius: 10, y: 4)
            .scaleEffect(isApprovalCueHovering ? 1.08 : 1)
        }
        .pointerCursor()
        .help("Review pending approvals")
        .onHover { isApprovalCueHovering = $0 }
    }

    private var approvalCueBackground: some View {
        ZStack {
            Capsule()
                .fill(Color.orange.opacity(selectedAppearance.isGlassMode ? 0.30 : 0.22))
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.26),
                            Color.clear,
                            selectedAppearance.isGlassMode
                                ? Color.white.opacity(0.08)
                                : Color.black.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
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

    private var collapsedExpansionDrag: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                guard !expansion.isExpanded else { return }
                hoverTask?.cancel()
                hoverTask = nil
                isDraggingExpansion = true
                let downwardTranslation = max(value.translation.height, 0)
                expansion.setDragProgress(downwardTranslation / Self.panelContentHeight)
            }
            .onEnded { value in
                guard !expansion.isExpanded else { return }
                isDraggingExpansion = false
                let downwardTranslation = max(value.translation.height, 0)
                let predictedTranslation = max(value.predictedEndTranslation.height, downwardTranslation)
                let shouldOpen = expansion.dragProgress > 0.36 || predictedTranslation > 150
                if shouldOpen {
                    expansion.open()
                } else {
                    withAnimation(YavenNotchAnimation.close) {
                        expansion.setDragProgress(0)
                    }
                }
            }
    }

    private func handleTap() {
        if isApprovalCueHovering {
            return
        }
        hoverTask?.cancel()
        hoverTask = nil
        if !isVisuallyExpanded && agentController.needsApprovalThreads.count > 0 {
            openApprovalsPanel()
            return
        }
        if expansion.isExpanded { expansion.close() } else { expansion.open() }
    }

    private func handleHover(_ hovering: Bool) {
        isHovering = hovering
        withAnimation(.easeInOut(duration: 0.34)) {
            shineProgress = hovering ? 0.72 : 0.28
        }
        hoverTask?.cancel()
        hoverTask = nil
        guard hovering, !expansion.isExpanded, !isDraggingExpansion else { return }
        hoverTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, isHovering else { return }
            expansion.open()
        }
    }

    private func openApprovalsPanel() {
        hoverTask?.cancel()
        hoverTask = nil
        if !expansion.isExpanded {
            expansion.open()
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            focusCoordinator.requestWidgetFocus(.approvals)
        }
    }

    private func handlePreferredHeightChange(_ preferredHeight: CGFloat) {
        let clampedHeight = Self.clampedPanelContentHeight(preferredHeight)
        if abs(preferredPanelContentHeight - clampedHeight) > 0.5 {
            withAnimation(YavenNotchAnimation.expansion(isExpanded: expansion.isExpanded)) {
                preferredPanelContentHeight = clampedHeight
            }
        }
        onPreferredHeightChange(clampedHeight)
    }

    private static func clampedPanelContentHeight(_ height: CGFloat) -> CGFloat {
        min(max(height, minimumPanelContentHeight), maximumPanelContentHeight)
    }

    private func interpolate(from start: CGFloat, to end: CGFloat) -> CGFloat {
        start + (end - start) * expansionProgress
    }

    private func interpolate(from start: Double, to end: Double) -> Double {
        start + (end - start) * Double(expansionProgress)
    }
}

private struct MenuCueButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.68), value: configuration.isPressed)
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
