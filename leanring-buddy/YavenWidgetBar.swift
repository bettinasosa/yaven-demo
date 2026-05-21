//
//  YavenWidgetBar.swift
//  leanring-buddy
//
//  Horizontal widget bar — boring.notch style.
//
//  Default (compact): 4 cards side-by-side at 160 px tall.
//  Click any card → that widget expands to fill the panel at a taller height.
//  Back chevron returns to the compact row.
//
//  Heights (content only, pill height added by shell):
//    compact        160 px
//    chat           420 px
//    automations    360 px
//    notifications  200 px
//    logCall        360 px
//

import Combine
import SwiftUI

// MARK: - Focus state

enum WidgetFocus: Equatable {
    case none
    case chat
    case automations
    case notifications
    case logCall
    case meeting
    case agents
    case approvals
}

// MARK: - Home screen data

private let homePrimaryBlue = Color(red: 0.22, green: 0.55, blue: 1.0)

private enum HomeLogo {
    case sfSymbol(String, Color)
    case composio(String)
}

private struct HomeNeedsYouItem: Identifiable {
    let id = UUID()
    let logo: HomeLogo
    let title: String
    let source: String
    let due: String
    let urgency: HomeNeedsYouUrgency
}

private enum HomeNeedsYouUrgency { case overdue, today, upcoming }

private enum HomeLayout: String, CaseIterable, Identifiable, Hashable {
    case commandCenter = "A"
    case focus         = "B"
    case recap         = "D"
    var id: String { rawValue }
    var name: String {
        switch self {
        case .commandCenter: return "Command"
        case .focus:         return "Focus"
        case .recap:         return "Recap"
        }
    }
}

private enum DayPickerStyle: Int, CaseIterable { case pills, strip, stepper }

private let homeNeedsYouFakeData: [HomeNeedsYouItem] = [
    HomeNeedsYouItem(logo: .composio("gmail"),       title: "Follow-up to Jamie Chen",    source: "Meeting Loop",      due: "Overdue",   urgency: .overdue),
    HomeNeedsYouItem(logo: .composio("linkedin"),    title: "LinkedIn batch — 10 drafts", source: "LinkedIn Outreach", due: "Due today",  urgency: .today),
    HomeNeedsYouItem(logo: .composio("granola_mcp"), title: "Product sync — notes",        source: "Meeting Loop",      due: "Due today",  urgency: .today),
]

private struct HomeYavenDoneItem: Identifiable {
    let id = UUID()
    let logo: HomeLogo
    let title: String
}

private let homeYavenDoneFakeData: [HomeYavenDoneItem] = [
    HomeYavenDoneItem(logo: .composio("gmail"),       title: "Sorted & labelled 15 emails"),
    HomeYavenDoneItem(logo: .composio("slack"),       title: "8 Slack reply drafts ready"),
    HomeYavenDoneItem(logo: .composio("granola_mcp"), title: "Call notes from Jamie Chen saved"),
]

// MARK: - Main bar

struct YavenWidgetBar: View {

    @ObservedObject var agentController: YavenAgentController
    @ObservedObject var cleanupController: YavenCleanupController
    @ObservedObject var focusCoordinator: YavenPanelFocusCoordinator
    let firstRunPanelMode: YavenFirstRunPanelMode
    let onPreferredHeightChange: (CGFloat) -> Void
    let onFirstRunYes: () -> Void
    let onFirstRunLater: () -> Void
    let onCleanupSkip: () -> Void
    let onCleanupContinue: () -> Void
    let onDraftReply: (NeedsReplyItem) -> Void

    @StateObject private var logCallController = LogCallController()
    @ObservedObject private var activityObserver = YavenActivityObserver.shared
    @ObservedObject private var preCallBriefController = PreCallBriefController.shared

    @State private var widgetFocus: WidgetFocus = .none
    @State private var automationDrillIn: AutomationItem? = nil
    @State private var agentWorkflowMode: AgentWorkflowMode = .overview
    @State private var agentWorkflowNameOverrides: [String: String] = [:]
    @State private var agentWorkflowHumanReviewOverrides: [String: Bool] = [:]
    @State private var agentWorkflowToolIconOverrides: [String: String] = [:]
    @State private var hoveredAgentWorkflowID: String? = nil
    @State private var pushedAgentWorkflowID: String? = nil
    @State private var showingChatHistory = false
    @State private var command: String = ""
    @State private var homeNeedsYouItems: [HomeNeedsYouItem] = homeNeedsYouFakeData
    @State private var homeLayout: HomeLayout = .commandCenter
    @State private var hoveredRecapItemID: UUID? = nil
    @State private var focusDayOffset: Int = 0
    @State private var dayPickerStyle: DayPickerStyle = .pills
    @State private var chatInputHoverPoint: CGPoint? = nil
    @FocusState private var isCommandFocused: Bool

    @State private var iconNavHovered: Int = -1
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(OnboardingAppearance.defaultsKey) private var selectedAppearanceRaw = OnboardingAppearance.defaultAppearance.rawValue

    private static let compactHeight: CGFloat        = 380
    private static let chatHeight: CGFloat           = 420
    private static let automationsHeight: CGFloat    = 420

    /// Exact height for the flows file-drawer view (no header overhead).
    private static var flowsDrawerHeight: CGFloat {
        AgentWorkflowDrawerLayout.totalHeight(for: 6)
    }
    private static let notificationsHeight: CGFloat  = 220
    private static let logCallHeight: CGFloat        = 380
    private static let meetingHeight: CGFloat        = 460
    private static let compactIconTopOffset: CGFloat = -28
    private static let expandedHeaderTopOffset: CGFloat = -28

    private enum Motion {
        static let focus = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.84, blendDuration: 0)
        static let reveal = Animation.easeOut(duration: 0.20)
    }

    private var selectedAppearance: OnboardingAppearance {
        OnboardingAppearance.fromStoredRawValue(selectedAppearanceRaw)
    }

    var body: some View {
        Group {
            if firstRunPanelMode != .hidden {
                firstRunOverlay
            } else if widgetFocus == .none {
                compactRow
                    .transition(focusTransition)
            } else {
                expandedView
                    .transition(focusTransition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Motion.focus, value: widgetFocus)
        .onAppear { onPreferredHeightChange(Self.compactHeight) }
        .onChange(of: widgetFocus) { _, focus in
            // Meeting widget drives its own height via onPreferredHeightChange callbacks.
            if focus != .meeting {
                onPreferredHeightChange(height(for: focus))
            }
            if focus != .chat { showingChatHistory = false }
            if focus != .logCall && focus != .agents { automationDrillIn = nil }
            if focus != .agents {
                agentWorkflowMode = .overview
                hoveredAgentWorkflowID = nil
            }
        }
        // When the shell requests focus (hotkey / notification tap), focus input without switching views.
        .onChange(of: focusCoordinator.focusRequestID) { _, _ in
            DispatchQueue.main.async { isCommandFocused = true }
        }
        .onChange(of: focusCoordinator.widgetFocusRequestID) { _, _ in
            guard let requestedFocus = focusCoordinator.requestedWidgetFocus else { return }
            setWidgetFocus(requestedFocus)
            if requestedFocus == .chat {
                DispatchQueue.main.async { isCommandFocused = true }
            }
        }
    }

    private var focusTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.98, anchor: .top)
                .combined(with: .opacity)
                .animation(Motion.reveal),
            removal: .opacity.animation(.easeIn(duration: 0.10))
        )
    }

    private func setWidgetFocus(_ focus: WidgetFocus) {
        withAnimation(Motion.focus) {
            widgetFocus = focus
        }
    }

    private func height(for focus: WidgetFocus) -> CGFloat {
        switch focus {
        case .none:          return Self.compactHeight
        case .chat:          return Self.chatHeight
        case .automations:   return Self.automationsHeight
        case .notifications: return Self.notificationsHeight
        case .logCall:       return Self.logCallHeight
        case .meeting:       return Self.meetingHeight
        case .agents:        return automationDrillIn == nil ? Self.flowsDrawerHeight : Self.automationsHeight
        case .approvals:     return Self.automationsHeight
        }
    }

    // MARK: - Compact row (home screen)

    private var compactRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Icon nav bar
            HStack {
                HStack(spacing: 4) {
                    iconNavButton(0, systemImage: "chart.xyaxis.line", label: "Log", focus: .automations)
                    iconNavButton(1, systemImage: "bolt.fill", label: "Flows", focus: .agents)
                }
                Spacer()
                HStack(spacing: 4) {
                    iconNavButton(2, systemImage: "bubble.left.fill", label: "Chat", focus: .chat)
                    iconNavButton(
                        3, systemImage: "tray.fill", label: "Desk", focus: .approvals,
                        badgeCount: 4
                    )
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, Self.compactIconTopOffset)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    homeLayoutPicker
                    homeLayoutContent
                    Spacer().frame(height: 24)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Home header

    private var homeHeader: some View {
        Text(greetingText)
            .font(.system(size: 22, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .padding(.bottom, 22)
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = YavenUserContext.shared.firstName
        let salutation: String
        switch hour {
        case 5..<12:  salutation = "Good morning"
        case 12..<17: salutation = "Good afternoon"
        case 17..<21: salutation = "Good evening"
        default:      salutation = "Good night"
        }
        return name.isEmpty ? salutation : "\(salutation), \(name)"
    }

    // MARK: - Quick wins section

    private var homeQuickWinsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Quick wins")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                Text("Yaven has done the work — these just need you.")
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.32))
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 12)

            VStack(spacing: 3) {
                // Highlight item — call with Jamie Chen
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(homePrimaryBlue.opacity(0.60))
                        .frame(width: 2.5)
                    HStack(spacing: 10) {
                        homeLogoView(.sfSymbol("phone.fill", homePrimaryBlue))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Call ended with Jamie Chen")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.88))
                                .lineLimit(1)
                            Text("Notes drafted")
                                .font(.system(size: 11))
                                .foregroundColor(Color(red: 0.40, green: 0.85, blue: 0.60).opacity(0.80))
                        }
                        Spacer(minLength: 4)
                        HStack(spacing: 5) {
                            homeActionButton("Add to Notion", filled: true)  { }
                            homeActionButton("Set up flow?",  filled: false) { setWidgetFocus(.agents) }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(homePrimaryBlue.opacity(0.07)))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 20)

                // Slack messages
                homeQuickWinRow(
                    logo: .composio("slack"),
                    title: "8 Slack messages",
                    descriptor: "Drafts ready",
                    descriptorIsReady: true,
                    buttonLabel: "Review & send"
                )

                // Emails
                homeQuickWinRow(
                    logo: .composio("gmail"),
                    title: "15 emails",
                    descriptor: "Drafts ready",
                    descriptorIsReady: true,
                    buttonLabel: "Review & send"
                )

                // Context shortcut
                homeQuickWinRow(
                    logo: .sfSymbol("arrow.uturn.left.circle.fill", Color.white.opacity(0.40)),
                    title: "Claude Code — auth bug fix",
                    descriptor: "Where you left off",
                    descriptorIsReady: false,
                    buttonLabel: "Jump back in"
                )
            }
        }
        .padding(.bottom, 22)
    }

    private func homeQuickWinRow(
        logo: HomeLogo,
        title: String,
        descriptor: String,
        descriptorIsReady: Bool,
        buttonLabel: String
    ) -> some View {
        HStack(spacing: 10) {
            homeLogoView(logo)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.82))
                    .lineLimit(1)
                Text(descriptor)
                    .font(.system(size: 11))
                    .foregroundColor(
                        descriptorIsReady
                            ? Color(red: 0.40, green: 0.85, blue: 0.60).opacity(0.75)
                            : Color.white.opacity(0.30)
                    )
            }
            Spacer(minLength: 4)
            homeActionButton(buttonLabel, filled: true) { }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private func homeLogoView(_ logo: HomeLogo) -> some View {
        switch logo {
        case .sfSymbol(let name, let tint):
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.opacity(0.14))
                    .frame(width: 28, height: 28)
                Image(systemName: name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(tint.opacity(0.90))
            }
        case .composio(let key):
            AsyncSVGImage(urlString: "https://logos.composio.dev/api/\(key)", size: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .frame(width: 28, height: 28)
        }
    }

    private func homeActionButton(_ label: String, filled: Bool, action: @escaping () -> Void) -> some View {
        let textOpacity = filled ? 0.90 : 0.68
        let fillOpacity = filled ? 0.14 : 0.055
        let strokeOpacity = filled ? 0.18 : 0.10

        return Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(textOpacity))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(fillOpacity))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.white.opacity(strokeOpacity), lineWidth: 0.5)
                )
                .fixedSize()
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    // MARK: - Needs you section

    private var homeNeedsYouSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Needs you")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 28)
                .padding(.bottom, 12)

            VStack(spacing: 3) {
                ForEach(homeNeedsYouItems) { item in
                    homeNeedsYouRow(item)
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                }
            }
            .animation(.spring(response: 0.30, dampingFraction: 0.82), value: homeNeedsYouItems.map(\.id.uuidString).joined())

            Button { setWidgetFocus(.approvals) } label: {
                Text("See all on your Desk →")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.28))
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .padding(.horizontal, 28)
            .padding(.top, 12)
        }
    }

    private func homeNeedsYouRow(_ item: HomeNeedsYouItem) -> some View {
        HStack(spacing: 10) {
            homeLogoView(item.logo)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.82))
                    .lineLimit(1)
                HStack(spacing: 0) {
                    Text(item.source + " · ")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.28))
                    Text(item.due)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(dueColor(item.urgency))
                }
            }

            Spacer(minLength: 4)

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    homeNeedsYouItems.removeAll { $0.id == item.id }
                }
            } label: {
                Text("Approve")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.90))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white.opacity(0.14))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                    )
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .pointerCursor()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
    }

    private func dueColor(_ urgency: HomeNeedsYouUrgency) -> Color {
        switch urgency {
        case .overdue:  return .red.opacity(0.85)
        case .today:    return Color(red: 0.95, green: 0.75, blue: 0.30)
        case .upcoming: return .white.opacity(0.35)
        }
    }

    // MARK: - Home layout picker

    private var homeLayoutPicker: some View {
        HStack(spacing: 4) {
            ForEach(HomeLayout.allCases) { option in
                let isSelected = homeLayout == option
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        homeLayout = option
                    }
                } label: {
                    HStack(spacing: isSelected ? 4 : 0) {
                        Text(option.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(isSelected ? .white.opacity(0.92) : .white.opacity(0.38))
                        if isSelected {
                            Text(option.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.68))
                                .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .leading)))
                        }
                    }
                    .padding(.horizontal, isSelected ? 9 : 7)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isSelected ? Color.white.opacity(0.12) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(isSelected ? Color.white.opacity(0.18) : Color.clear, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: homeLayout)
    }

    // MARK: - Home layout content switcher

    @ViewBuilder
    private var homeLayoutContent: some View {
        switch homeLayout {
        case .commandCenter:
            Group {
                homeHeader
                homeQuickWinsSection
                homeNeedsYouSection
            }
        case .focus:   homeLayoutB
        case .recap:   homeLayoutD
        }
    }


    // MARK: - Home Layout B — Focus

    private var homeLayoutB: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Clock + greeting
            VStack(alignment: .leading, spacing: 4) {
                TimelineView(.periodic(from: Date(), by: 30)) { context in
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(.white)
                }
                Text(greetingText)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.32))
            }
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .padding(.bottom, 20)

            // Day filter + style dots
            HStack(alignment: .center, spacing: 0) {
                Group {
                    switch dayPickerStyle {
                    case .pills:   dayFilterPills
                    case .strip:   dayFilterStrip
                    case .stepper: dayFilterStepper
                    }
                }
                Spacer(minLength: 8)
                // Three-dot style switcher
                HStack(spacing: 6) {
                    ForEach(DayPickerStyle.allCases, id: \.rawValue) { style in
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.80)) {
                                dayPickerStyle = style
                            }
                        } label: {
                            Circle()
                                .fill(dayPickerStyle == style
                                      ? Color.white.opacity(0.60)
                                      : Color.white.opacity(0.18))
                                .frame(width: 5, height: 5)
                        }
                        .buttonStyle(.plain)
                        .pointerCursor()
                    }
                }
                .padding(.trailing, 24)
            }
            .padding(.bottom, 16)

            // Top priority card
            if let topItem = homeNeedsYouItems.first {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        homeLogoView(topItem.logo)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Top priority")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(homePrimaryBlue.opacity(0.85))
                                .tracking(0.5)
                            Text(topItem.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    HStack(spacing: 6) {
                        Text(topItem.source)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.32))
                        Text("·")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.20))
                        Text(topItem.due)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(dueColor(topItem.urgency))
                        Spacer()
                        homeActionButton("Approve", filled: true) {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                homeNeedsYouItems.removeAll { $0.id == topItem.id }
                            }
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(homePrimaryBlue.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(homePrimaryBlue.opacity(0.18), lineWidth: 0.5)
                )
                .padding(.horizontal, 20)
            } else {
                Text("Nothing urgent — nice work.")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.30))
                    .padding(.horizontal, 28)
            }

            Button { setWidgetFocus(.approvals) } label: {
                Text("See all on your Desk →")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.28))
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .padding(.horizontal, 28)
            .padding(.top, 18)
        }
    }

    // MARK: - Day filter styles

    /// Style 1 — text pills: Today / Tomorrow / This week
    private var dayFilterPills: some View {
        HStack(spacing: 5) {
            ForEach([(0, "Today"), (1, "Tomorrow"), (7, "This week")], id: \.0) { offset, label in
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.80)) {
                        focusDayOffset = offset
                    }
                } label: {
                    Text(label)
                        .font(.system(size: 11, weight: focusDayOffset == offset ? .semibold : .regular))
                        .foregroundColor(focusDayOffset == offset ? .white : .white.opacity(0.35))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(focusDayOffset == offset ? Color.white.opacity(0.11) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(focusDayOffset == offset ? Color.white.opacity(0.17) : Color.clear,
                                        lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
        }
        .padding(.leading, 20)
    }

    /// Style 2 — 5-day strip: M T W T F with date circles
    private var dayFilterStrip: some View {
        HStack(spacing: 0) {
            ForEach(focusWeekDays, id: \.offset) { day in
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.80)) {
                        focusDayOffset = day.offset
                    }
                } label: {
                    VStack(spacing: 3) {
                        Text(day.letter)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(focusDayOffset == day.offset ? .white : .white.opacity(0.28))
                        ZStack {
                            Circle()
                                .fill(focusDayOffset == day.offset
                                      ? homePrimaryBlue
                                      : Color.white.opacity(day.isToday ? 0.08 : 0))
                                .frame(width: 26, height: 26)
                            Text(day.number)
                                .font(.system(size: 12,
                                              weight: focusDayOffset == day.offset ? .bold : .regular))
                                .foregroundColor(focusDayOffset == day.offset
                                                 ? .white
                                                 : .white.opacity(day.isToday ? 0.70 : 0.40))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 44) // leave room for the style dots
    }

    /// Style 3 — stepper: ◀ Wednesday, 21 May ▶
    private var dayFilterStepper: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.80)) {
                    focusDayOffset -= 1
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(focusDayOffset > -6 ? 0.55 : 0.18))
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .disabled(focusDayOffset <= -6)

            Text(focusDayLabel)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .frame(minWidth: 130, alignment: .center)
                .animation(.none, value: focusDayOffset)

            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.80)) {
                    focusDayOffset += 1
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(focusDayOffset < 13 ? 0.55 : 0.18))
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .disabled(focusDayOffset >= 13)
        }
        .padding(.leading, 24)
    }

    // MARK: - Day filter helpers

    private var focusDayLabel: String {
        if focusDayOffset == 0 { return "Today" }
        if focusDayOffset == 1 { return "Tomorrow" }
        if focusDayOffset == -1 { return "Yesterday" }
        guard let day = Calendar.current.date(byAdding: .day, value: focusDayOffset, to: Date()) else {
            return ""
        }
        return day.formatted(.dateTime.weekday(.wide).day().month())
    }

    private var focusWeekDays: [(letter: String, number: String, offset: Int, isToday: Bool)] {
        let cal = Calendar.current
        let today = Date()
        let todayStart = cal.startOfDay(for: today)
        // Start from Monday of current week
        let weekday = cal.component(.weekday, from: today)
        let mondayDelta = -((weekday - 2 + 7) % 7)
        return (0..<5).compactMap { i in
            guard let day = cal.date(byAdding: .day, value: mondayDelta + i, to: today) else { return nil }
            let offset = cal.dateComponents([.day], from: todayStart, to: cal.startOfDay(for: day)).day ?? 0
            let wday = cal.component(.weekday, from: day)
            let letter = String(cal.shortStandaloneWeekdaySymbols[wday - 1].prefix(1))
            let number = String(cal.component(.day, from: day))
            return (letter: letter, number: number, offset: offset, isToday: offset == 0)
        }
    }


    // MARK: - Home Layout D — Recap

    private var homeLayoutD: some View {
        let purple = Color(red: 0.75, green: 0.50, blue: 1.00)
        let green  = Color(red: 0.35, green: 0.85, blue: 0.55)
        return VStack(alignment: .leading, spacing: 0) {

            // Greeting + day context
            VStack(alignment: .leading, spacing: 5) {
                Text(greetingText)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
                HStack(spacing: 0) {
                    Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                    Text("  ·  4 meetings  ·  \(homeNeedsYouItems.count) to-do")
                }
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.28))
                .animation(.spring(response: 0.30, dampingFraction: 0.82), value: homeNeedsYouItems.count)
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 14)

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5)
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

            // "To-do today" header with animated countdown
            HStack(alignment: .center) {
                Text("To-do today")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(purple.opacity(0.85))
                Spacer()
                if !homeNeedsYouItems.isEmpty {
                    Text("\(homeNeedsYouItems.count)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundColor(purple.opacity(0.50))
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.spring(response: 0.30, dampingFraction: 0.82), value: homeNeedsYouItems.count)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 6)

            // To-do rows — hover-reveal approve, urgency left bar
            VStack(spacing: 2) {
                ForEach(homeNeedsYouItems) { item in
                    recapToDoRow(item)
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                }
                if homeNeedsYouItems.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(green.opacity(0.70))
                        Text("All clear — great work.")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.84), value: homeNeedsYouItems.map(\.id.uuidString).joined())
            .padding(.bottom, 16)

            // "Yaven handled" — clearly done, visually receded
            Text("Yaven handled")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.25))
                .tracking(0.3)
                .padding(.horizontal, 28)
                .padding(.bottom, 6)

            VStack(spacing: 0) {
                ForEach(homeYavenDoneFakeData) { item in
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(green.opacity(0.55))
                        homeLogoView(item.logo)
                        Text(item.title)
                            .font(.system(size: 11.5, weight: .regular))
                            .foregroundColor(.white.opacity(0.35))
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(green.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(green.opacity(0.09), lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 18)
        }
    }

    // Row with urgency left bar, hover lift + background, approve that reveals on hover
    private func recapToDoRow(_ item: HomeNeedsYouItem) -> some View {
        let isHovered = hoveredRecapItemID == item.id
        let urgencyColor = dueColor(item.urgency)

        return HStack(spacing: 0) {
            // Urgency left bar — brightens on hover
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(urgencyColor.opacity(isHovered ? 0.85 : 0.28))
                .frame(width: 2.5)
                .padding(.vertical, 10)
                .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isHovered)

            HStack(spacing: 10) {
                homeLogoView(item.logo)
                    .scaleEffect(isHovered ? 1.06 : 1.0)
                    .animation(.spring(response: 0.28, dampingFraction: 0.68), value: isHovered)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(isHovered ? 0.95 : 0.82))
                        .lineLimit(1)
                        .animation(.easeOut(duration: 0.14), value: isHovered)
                    HStack(spacing: 0) {
                        Text(item.source + "  ·  ")
                            .foregroundColor(.white.opacity(0.25))
                        Text(item.due)
                            .foregroundColor(urgencyColor)
                    }
                    .font(.system(size: 10))
                }

                Spacer(minLength: 4)

                // Approve button: ghost at rest → tinted + labelled on hover
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        homeNeedsYouItems.removeAll { $0.id == item.id }
                    }
                } label: {
                    HStack(spacing: isHovered ? 5 : 0) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(isHovered ? urgencyColor : .white.opacity(0.18))
                        if isHovered {
                            Text("Approve")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(urgencyColor.opacity(0.90))
                                .fixedSize()
                                .transition(.opacity.combined(with: .scale(scale: 0.75, anchor: .leading)))
                        }
                    }
                    .padding(.horizontal, isHovered ? 9 : 4)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(urgencyColor.opacity(isHovered ? 0.10 : 0))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(urgencyColor.opacity(isHovered ? 0.20 : 0), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isHovered)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.06 : 0))
        )
        .offset(y: isHovered ? -1 : 0)
        .shadow(color: .black.opacity(isHovered ? 0.20 : 0), radius: 8, x: 0, y: 3)
        .padding(.horizontal, 14)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isHovered)
        .onHover { hovering in
            hoveredRecapItemID = hovering ? item.id : nil
        }
    }


    // MARK: - Icon nav button (Style F — expanding pill)

    private func iconNavButton(
        _ index: Int,
        systemImage: String,
        label: String,
        focus: WidgetFocus,
        badgeCount: Int = 0
    ) -> some View {
        let isActive  = widgetFocus == focus
        let isHovered = iconNavHovered == index
        let expanded  = isActive || isHovered
        return Button { setWidgetFocus(focus) } label: {
            HStack(spacing: expanded ? 7 : 0) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(expanded ? .white.opacity(isActive ? 0.95 : 0.85) : .white.opacity(0.65))
                        .frame(width: 18, height: 18)
                    if badgeCount > 0 {
                        Text("\(badgeCount)")
                            .font(.system(size: 7.5, weight: .bold))
                            .monospacedDigit()
                            .foregroundColor(.white.opacity(0.90))
                            .padding(.horizontal, 3.5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.white.opacity(0.22)))
                            .offset(x: 7, y: -4)
                    }
                }
                .frame(width: 18, height: 18, alignment: .leading)
                if expanded {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isActive ? .white.opacity(0.92) : .white.opacity(0.82))
                        .fixedSize()
                        .transition(.opacity.combined(with: .scale(scale: 0.7, anchor: .leading)))
                }
            }
            .padding(.horizontal, expanded ? 10 : 4)
            .padding(.vertical, expanded ? 6 : 3)
            .background(
                Capsule()
                    .fill(expanded
                          ? (isActive ? Color.white.opacity(0.16) : Color.white.opacity(0.10))
                          : Color.clear)
                    .overlay(
                        Capsule().strokeBorder(
                            expanded ? Color.white.opacity(0.20) : Color.clear,
                            lineWidth: 0.5
                        )
                    )
            )
            .animation(.spring(response: 0.30, dampingFraction: 0.68), value: expanded)
            .animation(.spring(response: 0.30, dampingFraction: 0.68), value: isActive)
        }
        .buttonStyle(NavIconButtonStyle())
        .pointerCursor()
        .help(label)
        .accessibilityLabel(label)
        .accessibilityHint("Opens \(label)")
        .onHover { h in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                if h {
                    iconNavHovered = index
                } else if iconNavHovered == index {
                    iconNavHovered = -1
                }
            }
        }
    }

    private struct NavIconButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
                .opacity(configuration.isPressed ? 0.86 : 1)
                .animation(.spring(response: 0.18, dampingFraction: 0.72), value: configuration.isPressed)
        }
    }

    // MARK: - Expanded wrapper

    private var expandedView: some View {
        // Flows folder drawer: no header, no padding — content comes directly from the pill button.
        if widgetFocus == .agents && automationDrillIn == nil {
            return AnyView(
                expandedContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        }
        if widgetFocus == .approvals {
            return AnyView(
                expandedContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, Self.expandedHeaderTopOffset)
            )
        }
        return AnyView(
            VStack(spacing: 0) {
                expandedHeader
                Divider().opacity(0.12)
                expandedContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.top, Self.expandedHeaderTopOffset)
        )
    }

    private var expandedHeader: some View {
        HStack(spacing: 0) {
            Button {
                if widgetFocus == .agents,
                   automationDrillIn != nil,
                   agentWorkflowMode != .overview {
                    withAnimation(Motion.focus) { agentWorkflowMode = .overview }
                    onPreferredHeightChange(Self.automationsHeight)
                } else if (widgetFocus == .logCall || widgetFocus == .agents), automationDrillIn != nil {
                    withAnimation(Motion.focus) {
                        automationDrillIn = nil
                        agentWorkflowMode = .overview
                    }
                    // Agents returns to the headerless drawer; logCall returns to the automation list
                    onPreferredHeightChange(widgetFocus == .agents ? Self.flowsDrawerHeight : Self.automationsHeight)
                } else {
                    setWidgetFocus(.none)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text(expandedTitle)
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.55))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerCursor()

            Spacer()

            if widgetFocus == .chat {
                HStack(spacing: 12) {
                    // History: toggle past chat threads.
                    Button {
                        showingChatHistory.toggle()
                    } label: {
                        Image(systemName: showingChatHistory ? "bubble.left.fill" : "clock.arrow.circlepath")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(showingChatHistory ? 0.55 : 0.35))
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()

                    // New chat — only when there are active messages.
                    if !agentController.chatMessages.isEmpty && !showingChatHistory {
                        Button {
                            command = ""
                            agentController.clearChatMemory()
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.35))
                        }
                        .buttonStyle(.plain)
                        .pointerCursor()
                    }
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 10)
    }

    private var expandedTitle: String {
        switch widgetFocus {
        case .chat:          return "Chat"
        case .automations:   return "Log"
        case .notifications: return "Notifications"
        case .logCall:       return automationDrillIn?.displayName ?? "Automations"
        case .meeting:       return "Process Meeting"
        case .agents:        return agentExpandedTitle
        case .approvals:     return "Desk"
        case .none:          return ""
        }
    }

    private var agentExpandedTitle: String {
        guard let drill = automationDrillIn else { return "Flows" }
        let baseTitle = agentWorkflow(for: drill).map { agentWorkflowName($0) } ?? drill.displayName
        switch agentWorkflowMode {
        case .overview: return baseTitle
        case .run:      return "Run \(baseTitle)"
        case .edit:     return "Edit \(baseTitle)"
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        switch widgetFocus {
        case .chat:
            chatExpandedView
        case .automations:
            YavenLogView { _ in
                setWidgetFocus(.agents)
            }
        case .notifications:
            notificationsExpandedView
        case .logCall:
            automationsExpandedView2
        case .meeting:
            MeetingExpandedView { newHeight in
                onPreferredHeightChange(newHeight + 44) // +44 for the expanded header
            }
        case .agents:
            agentsExpandedView
        case .approvals:
            YavenDeskView(
                onClose: { setWidgetFocus(.none) },
                onPreferredHeightChange: onPreferredHeightChange
            )
        case .none:
            EmptyView()
        }
    }

    // MARK: - Chat expanded

    private var chatExpandedView: some View {
        let showEmpty = agentController.chatMessages.isEmpty
            && agentController.state == .idle
            && agentController.currentPlan == nil
            && agentController.executionResult == nil
            && agentController.errorMessage == nil

        return VStack(spacing: 0) {
            if showingChatHistory {
                fakeChatConversation
            } else if showEmpty {
                VStack(spacing: 0) {
                    Spacer()
                    emptyChatState
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                chatInputBar
            } else {
                chatMessagesArea
                chatInputBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color.clear, Color.white.opacity(0.022)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var chatMessagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        chatStatusLine

                        ForEach(agentController.chatMessages) { msg in
                            chatBubble(msg)
                        }

                        if let plan = agentController.currentPlan {
                            chatApprovalCard(plan)
                        }

                        if let result = agentController.executionResult {
                            chatResultCard(result)
                        }

                        if let error = agentController.errorMessage {
                            chatErrorCard(error)
                        }

                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 10)
                    .padding(.bottom, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: agentController.chatMessages.count) { _, _ in scrollTo(proxy) }
                .onChange(of: agentController.chatMessages.last?.text ?? "") { _, _ in scrollTo(proxy) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty chat state

    private var emptyChatState: some View {
        VStack(spacing: 14) {
            ChatEmptyOrbView(isGlassMode: selectedAppearance.isGlassMode)

            Text("What do you need?")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.38))

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    chatChip("Draft an email")
                    chatChip("Research a topic")
                    chatChip("Summarise something")
                }
                HStack(spacing: 8) {
                    chatChip("Set up a new flow")
                    chatChip("Just ask…")
                }
            }
        }
        .padding(.horizontal, 20)
        .opacity(command.isEmpty ? 1 : 0)
        .animation(.easeOut(duration: 0.15), value: command.isEmpty)
    }

    private func chatChip(_ label: String) -> some View {
        Button {
            command = label
            isCommandFocused = true
        } label: {
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(.white.opacity(0.42))
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.07)))
                .overlay(Capsule().stroke(Color.white.opacity(0.11), lineWidth: 0.5))
                .fixedSize()
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    // MARK: - Fake conversation (toggled by history icon)

    private var fakeChatConversation: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // User message
                HStack {
                    Spacer(minLength: 48)
                    Text("Can you draft an outreach email to the person I'm looking at?")
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .lineSpacing(3)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(red: 0.22, green: 0.55, blue: 1.0))
                        )
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.bottom, 20)

                // Yaven response
                HStack(alignment: .top, spacing: 10) {
                    YavenOnboardingMascotView(appearance: .black, size: 20)
                        .opacity(0.72)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 12) {
                        // Intro
                        Text("The person on your screen is **Sarah Mitchell**, Head of Growth at Loopkit — a Series B workflow automation company based in London. Here's what I found:")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.82))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)

                        // Research card
                        VStack(alignment: .leading, spacing: 10) {
                            Text("From her LinkedIn she's been in the role for 8 months, joined from Intercom, and has been posting about scaling outbound recently. Loopkit just announced a partnership with HubSpot two weeks ago — good timing for an intro.\n\nI pulled her direct email from Apollo: **s.mitchell@loopkit.io**\n\nI also checked your Notion and pulled your current service offering and a few recent client results to shape the pitch.")
                                .font(.system(size: 12.5))
                                .foregroundColor(.white.opacity(0.68))
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 6) {
                                fakeSourceTag("LinkedIn", color: Color(red: 0.10, green: 0.46, blue: 0.82))
                                fakeSourceTag("Apollo",   color: Color(red: 0.42, green: 0.25, blue: 0.85))
                                fakeSourceTag("Notion",   color: Color(white: 0.55))
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 0.5))

                        // Email draft card
                        HStack(spacing: 0) {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(Color(red: 0.22, green: 0.55, blue: 1.0).opacity(0.65))
                                .frame(width: 2.5)

                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("DRAFT")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(Color(red: 0.22, green: 0.55, blue: 1.0).opacity(0.80))
                                        .tracking(0.8)
                                    Spacer()
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.22))
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Subject: Loopkit x [Your Company]")
                                        .font(.system(size: 12, weight: .semibold).italic())
                                        .foregroundColor(.white.opacity(0.72))

                                    Text("Hi Sarah,\n\nSaw the HubSpot announcement — congrats on that, big distribution move.\n\nI work with growth teams at companies like yours on outbound systems that remove the manual research and sequencing work from the process entirely. A recent client went from 8 hours a week on prospecting to under one — same output, fraction of the time.\n\nWorth a 20 minute call to see if there's a fit?\n\n[Your name]")
                                        .font(.system(size: 12).italic())
                                        .foregroundColor(.white.opacity(0.60))
                                        .lineSpacing(3)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(12)
                        }
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08)))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 0.5))

                        // Follow-up line
                        Text("Want me to tweak the tone, adjust the pitch angle, or send it?")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.82))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fakeSourceTag(_ name: String, color: Color) -> some View {
        Text(name)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(color.opacity(0.90))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
            .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 0.5))
    }

    @ViewBuilder
    private var chatStatusLine: some View {
        let label: String? = {
            switch agentController.state {
            case .thinking:        return "Capturing screen context…"
            case .answering:       return "Responding…"
            case .planning:        return "Preparing a plan…"
            case .approvalRequired: return "Review before Yaven acts."
            case .executing:       return "Executing…"
            case .done:            return "Done."
            case .error:           return "Something went wrong."
            case .idle:            return nil
            }
        }()
        if let label {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
    }

    private func chatBubble(_ msg: YavenChatMessage) -> some View {
        HStack {
            if msg.role == .user { Spacer(minLength: 34) }
            Text(msg.text)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .lineSpacing(3)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(msg.role == .user ? Color.cyan.opacity(0.14) : Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(msg.role == .user ? Color.cyan.opacity(0.14) : Color.white.opacity(0.08), lineWidth: 0.5)
                )
            if msg.role == .assistant { Spacer(minLength: 34) }
        }
        .frame(maxWidth: .infinity, alignment: msg.role == .user ? .trailing : .leading)
    }

    private func chatApprovalCard(_ plan: YavenActionPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(plan.goal).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(plan.risk.rawValue.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(plan.risk == .high ? .red : plan.risk == .medium ? .orange : .green)
            }
            Text(plan.summary).font(.system(size: 12)).foregroundColor(.secondary)
            HStack {
                Button("Approve") { agentController.approveCurrentPlan() }
                    .keyboardShortcut(.return, modifiers: [])
                Button("Cancel") { agentController.cancelCurrentPlan() }
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 0.5))
    }

    private func chatResultCard(_ result: YavenExecutionResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(result.succeeded ? "Completed" : "Stopped")
                .font(.system(size: 13, weight: .semibold))
            Text(result.message)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
    }

    private func chatErrorCard(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13))
            .foregroundColor(.red.opacity(0.85))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.08)))
    }

    private var chatInputBar: some View {
        let cornerRadius: CGFloat = 22

        return HStack(spacing: 8) {
            TextField("Ask me anything or describe a task…", text: $command)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .focused($isCommandFocused)
                .onSubmit(submitCommand)
                .onAppear { isCommandFocused = true }

            if !command.isEmpty {
                Button(action: submitCommand) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(0.88)))
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background {
            ChatInputGlassFill(cornerRadius: cornerRadius, isGlassMode: selectedAppearance.isGlassMode)
        }
        .overlay {
            CursorShineRoundedBorder(cornerRadius: cornerRadius, hoverPoint: chatInputHoverPoint)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                chatInputHoverPoint = location
            case .ended:
                chatInputHoverPoint = nil
            }
        }
        .animation(.easeOut(duration: 0.16), value: chatInputHoverPoint == nil)
    }

    private func submitCommand() {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        agentController.submit(trimmed)
        command = ""
        isCommandFocused = true
    }

    private func scrollTo(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    // MARK: - Automations expanded

    private var automationsExpandedView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !activityObserver.isEnabled {
                    activityOptInCard
                }
                activitySection(
                    title: "Needs approval",
                    threads: agentController.needsApprovalThreads,
                    emptyText: "Nothing waiting."
                )
                activitySection(
                    title: "Running",
                    threads: agentController.runningThreads,
                    emptyText: "No background tasks."
                )
                activitySection(
                    title: "Recent",
                    threads: Array(agentController.recentThreads.prefix(8)),
                    emptyText: "No recent tasks."
                )
            }
            .padding(.horizontal, 32)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
    }

    private var activityOptInCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Local activity awareness")
                .font(.system(size: 13, weight: .semibold))
            Text("Yaven can log which apps you switch between so future automations have better context.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineSpacing(2)
            Button("Enable") { activityObserver.setEnabled(true) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .pointerCursor()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 0.5))
    }

    private func activitySection(title: String, threads: [YavenThreadSummary], emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            if threads.isEmpty {
                Text(emptyText)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.vertical, 2)
            } else {
                ForEach(threads) { thread in
                    activityRow(thread)
                }
            }
        }
    }

    private func activityRow(_ thread: YavenThreadSummary) -> some View {
        Button { agentController.selectThread(thread.id) } label: {
            HStack(alignment: .top, spacing: 9) {
                Circle()
                    .fill(threadStatusColor(thread.status))
                    .frame(width: 7, height: 7)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(thread.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(thread.lastPreview.isEmpty ? thread.status.displayTitle : thread.lastPreview)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(thread.requiresAttention ? 0.12 : 0.07)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    private func threadStatusColor(_ status: YavenThreadStatus) -> Color {
        switch status {
        case .queued:          return .yellow.opacity(0.8)
        case .running:         return .cyan
        case .approvalRequired: return .orange
        case .completed:       return .green
        case .failed:          return .red
        case .cancelled:       return Color.secondary
        }
    }

    // MARK: - Agents expanded (file drawer)

    private var agentsExpandedView: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let drill = automationDrillIn, let workflow = agentWorkflow(for: drill) {
                    switch agentWorkflowMode {
                    case .overview:
                        agentWorkflowDetail(workflow)
                            .transition(.scale(scale: 0.94, anchor: .top).combined(with: .opacity))
                    case .run:
                        automationDetailContent(drill)
                    case .edit:
                        agentWorkflowEditor(workflow)
                    }
                } else {
                    agentWorkflowFolderDrawer
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        }
    }

    // MARK: - Approvals expanded

    private var approvalsExpandedView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                activitySection(
                    title: "Needs approval",
                    threads: agentController.needsApprovalThreads,
                    emptyText: "No pending approvals."
                )
            }
            .padding(.horizontal, 32)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Notifications expanded

    private var notificationsExpandedView: some View {
        VStack {
            Spacer()
            Image(systemName: "bell.slash")
                .font(.system(size: 30))
                .foregroundColor(.white.opacity(0.14))
            Text("No notifications")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.26))
                .padding(.top, 6)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Automations hub

    private enum AgentWorkflowMode: Equatable {
        case overview
        case run
        case edit
    }

    private enum AutomationItem: String, CaseIterable, Identifiable {
        case logCall        = "log-call"
        case preCallBrief   = "pre-call-brief"
        case processMeeting = "process-meeting"
        case proposalDraft  = "proposal-draft"
        case invoiceChase   = "invoice-chase"
        case scopeGuardian  = "scope-guardian"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .logCall:        return "Log Sales Call"
            case .preCallBrief:   return "Pre-Call Brief"
            case .processMeeting: return "Process Meeting"
            case .proposalDraft:  return "Proposal Draft"
            case .invoiceChase:   return "Invoice Chase"
            case .scopeGuardian:  return "Scope Guardian"
            }
        }

        var icon: String {
            switch self {
            case .logCall:        return "phone.fill"
            case .preCallBrief:   return "doc.text.magnifyingglass"
            case .processMeeting: return "sparkles"
            case .proposalDraft:  return "doc.badge.plus"
            case .invoiceChase:   return "envelope.badge.fill"
            case .scopeGuardian:  return "shield.lefthalf.filled"
            }
        }

        var tagline: String {
            switch self {
            case .logCall:        return "Extract call notes, update HubSpot, draft follow-up emails."
            case .preCallBrief:   return "3-bullet brief auto-surfaces 5 min before each call."
            case .processMeeting: return "Turn Granola meeting notes into action items."
            case .proposalDraft:  return "Paste a client brief, get a full proposal draft in Gmail."
            case .invoiceChase:   return "Generate a polite but firm payment chase email."
            case .scopeGuardian:  return "Detect scope creep and draft a professional boundary response."
            }
        }
    }

    private var automationsExpandedView2: some View {
        Group {
            if let drill = automationDrillIn {
                automationDetailContent(drill)
            } else {
                automationListContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Agent file drawer data

    private struct AgentFile: Identifiable {
        let id: String
        let name: String
        let icon: String
        let tagline: String
        let automationItem: AutomationItem?
        var isAvailable: Bool { automationItem != nil }
    }

    private struct AgentCategory: Identifiable {
        let id: String
        let name: String
        let color: Color
        let agents: [AgentFile]
    }

    private struct WorkflowTool: Identifiable {
        let id: String
        let name: String
        let domain: String?         // loads favicon via Google Favicon API
        let systemImage: String?    // fallback SF Symbol when no domain
        let color: Color
        let composioKey: String?    // if set, uses Composio logo CDN (same as dashboard icons)

        init(id: String, name: String, domain: String?, systemImage: String?, color: Color, composioKey: String? = nil) {
            self.id = id; self.name = name; self.domain = domain
            self.systemImage = systemImage; self.color = color; self.composioKey = composioKey
        }

        var iconURL: String? {
            if let key = composioKey { return "https://logos.composio.dev/api/\(key)" }
            guard let domain else { return nil }
            return "https://www.google.com/s2/favicons?domain=\(domain)&sz=128"
        }
    }

    private struct AgentWorkflowFolder: Identifiable {
        let item: AutomationItem
        let folderID: String
        let folderName: String
        let summary: String
        let color: Color
        let tools: [WorkflowTool]
        let icon: String
        let tabPosition: CGFloat   // 0.0=left … 1.0=right
        let lightTab: Bool         // true = white tab bg + black text

        var id: String { item.id }
    }

    private var agentWorkflowFolders: [AgentWorkflowFolder] {[
        AgentWorkflowFolder(
            item: .preCallBrief,
            folderID: "094",
            folderName: "Pre-Call Brief",
            summary: "Build a 3-bullet customer brief before your next call.",
            color: Color(red: 0.45, green: 0.70, blue: 1.00),
            tools: [
                WorkflowTool(id: "calendar", name: "Calendar", domain: "calendar.google.com", systemImage: nil, color: Color(red: 0.45, green: 0.70, blue: 1.00)),
                WorkflowTool(id: "hubspot", name: "HubSpot", domain: "hubspot.com", systemImage: nil, color: .orange),
                WorkflowTool(id: "gmail", name: "Gmail", domain: nil, systemImage: nil, color: Color(red: 1.0, green: 0.40, blue: 0.40), composioKey: "gmail")
            ],
            icon: "doc.text.magnifyingglass",
            tabPosition: 0.18,
            lightTab: true
        ),
        AgentWorkflowFolder(
            item: .logCall,
            folderID: "096",
            folderName: "Log Sales Call",
            summary: "Extract notes, update CRM, and draft the follow-up.",
            color: Color(red: 0.35, green: 0.85, blue: 0.60),
            tools: [
                WorkflowTool(id: "granola", name: "Granola", domain: "granola.so", systemImage: nil, color: Color(red: 0.35, green: 0.85, blue: 0.60)),
                WorkflowTool(id: "hubspot", name: "HubSpot", domain: "hubspot.com", systemImage: nil, color: .orange),
                WorkflowTool(id: "gmail", name: "Gmail", domain: nil, systemImage: nil, color: Color(red: 1.0, green: 0.40, blue: 0.40), composioKey: "gmail")
            ],
            icon: "phone.fill",
            tabPosition: 0.36,
            lightTab: false
        ),
        AgentWorkflowFolder(
            item: .processMeeting,
            folderID: "098",
            folderName: "Process Meeting",
            summary: "Turn notes into owners, action items, and next steps.",
            color: Color(red: 0.75, green: 0.50, blue: 1.00),
            tools: [
                WorkflowTool(id: "granola", name: "Granola", domain: "granola.so", systemImage: nil, color: Color(red: 0.75, green: 0.50, blue: 1.00)),
                WorkflowTool(id: "notion", name: "Notion", domain: "notion.so", systemImage: nil, color: .white),
                WorkflowTool(id: "gmail", name: "Gmail", domain: nil, systemImage: nil, color: Color(red: 1.0, green: 0.40, blue: 0.40), composioKey: "gmail")
            ],
            icon: "sparkles",
            tabPosition: 0.54,
            lightTab: true
        ),
        AgentWorkflowFolder(
            item: .proposalDraft,
            folderID: "100",
            folderName: "Proposal Draft",
            summary: "Convert a client brief into a polished proposal draft.",
            color: Color(red: 1.00, green: 0.65, blue: 0.20),
            tools: [
                WorkflowTool(id: "docs", name: "Google Docs", domain: "docs.google.com", systemImage: nil, color: Color(red: 0.45, green: 0.70, blue: 1.00)),
                WorkflowTool(id: "hubspot", name: "HubSpot", domain: "hubspot.com", systemImage: nil, color: .orange),
                WorkflowTool(id: "gmail", name: "Gmail", domain: "mail.google.com", systemImage: nil, color: Color(red: 1.00, green: 0.65, blue: 0.20))
            ],
            icon: "doc.badge.plus",
            tabPosition: 0.72,
            lightTab: false
        ),
        AgentWorkflowFolder(
            item: .invoiceChase,
            folderID: "102",
            folderName: "Invoice Chase",
            summary: "Draft a polite payment nudge with invoice context.",
            color: Color(red: 1.00, green: 0.82, blue: 0.35),
            tools: [
                WorkflowTool(id: "stripe", name: "Stripe", domain: "stripe.com", systemImage: nil, color: Color(red: 0.62, green: 0.56, blue: 1.00)),
                WorkflowTool(id: "hubspot", name: "HubSpot", domain: "hubspot.com", systemImage: nil, color: .orange),
                WorkflowTool(id: "gmail", name: "Gmail", domain: nil, systemImage: nil, color: Color(red: 1.0, green: 0.40, blue: 0.40), composioKey: "gmail")
            ],
            icon: "dollarsign.circle.fill",
            tabPosition: 0.27,
            lightTab: true
        ),
        AgentWorkflowFolder(
            item: .scopeGuardian,
            folderID: "104",
            folderName: "Scope Guardian",
            summary: "Spot scope creep and draft a clear boundary response.",
            color: Color(red: 1.00, green: 0.40, blue: 0.40),
            tools: [
                WorkflowTool(id: "gmail", name: "Gmail", domain: nil, systemImage: nil, color: Color(red: 1.0, green: 0.40, blue: 0.40), composioKey: "gmail"),
                WorkflowTool(id: "docs", name: "Google Docs", domain: "docs.google.com", systemImage: nil, color: Color(red: 0.45, green: 0.70, blue: 1.00)),
                WorkflowTool(id: "slack", name: "Slack", domain: "slack.com", systemImage: nil, color: Color(red: 0.75, green: 0.50, blue: 1.00))
            ],
            icon: "shield.lefthalf.filled",
            tabPosition: 0.63,
            lightTab: false
        )
    ]}

    private func agentWorkflow(for item: AutomationItem) -> AgentWorkflowFolder? {
        agentWorkflowFolders.first { $0.item == item }
    }

    private func agentWorkflowName(_ workflow: AgentWorkflowFolder) -> String {
        let customName = agentWorkflowNameOverrides[workflow.id]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return customName.isEmpty ? workflow.folderName : customName
    }

    private func workflowNameBinding(for workflow: AgentWorkflowFolder) -> Binding<String> {
        Binding(
            get: { agentWorkflowNameOverrides[workflow.id] ?? workflow.folderName },
            set: { agentWorkflowNameOverrides[workflow.id] = $0 }
        )
    }

    private var drawerCategories: [AgentCategory] {[
        AgentCategory(id: "crm", name: "CRM", color: .cyan, agents: [
            AgentFile(id: "log-call",   name: "Log Sales Call",  icon: "phone.fill",              tagline: "Notes → HubSpot → follow-up",    automationItem: .logCall),
            AgentFile(id: "deal-stage", name: "Deal Stage",      icon: "arrow.right.circle.fill", tagline: "Move deals through pipeline",    automationItem: nil),
            AgentFile(id: "enrich",     name: "Enrich Contact",  icon: "person.badge.plus",       tagline: "Auto-research + update CRM",     automationItem: nil),
            AgentFile(id: "followup",   name: "Follow-up",       icon: "envelope.badge.fill",     tagline: "Draft follow-ups from meetings", automationItem: nil),
        ]),
        AgentCategory(id: "comms", name: "Communication", color: Color(red: 0.45, green: 0.65, blue: 1.0), agents: [
            AgentFile(id: "precall",     name: "Pre-Call Brief", icon: "doc.text.magnifyingglass",         tagline: "3-bullet brief before each call", automationItem: .preCallBrief),
            AgentFile(id: "meeting",     name: "Meeting Notes",  icon: "sparkles",                         tagline: "Recordings → action items",       automationItem: .processMeeting),
            AgentFile(id: "email-draft", name: "Email Drafter",  icon: "tray.full.fill",                   tagline: "Context-aware reply drafts",      automationItem: nil),
            AgentFile(id: "slack",       name: "Slack Digest",   icon: "bubble.left.and.bubble.right",     tagline: "Summarise threads you missed",    automationItem: nil),
        ]),
        AgentCategory(id: "sales", name: "Sales", color: .orange, agents: [
            AgentFile(id: "proposal", name: "Proposal Draft",  icon: "doc.badge.plus",        tagline: "Brief → full proposal in Gmail",    automationItem: .proposalDraft),
            AgentFile(id: "invoice",  name: "Invoice Chase",   icon: "creditcard.fill",        tagline: "Polite payment chase emails",       automationItem: .invoiceChase),
            AgentFile(id: "scope",    name: "Scope Guardian",  icon: "shield.lefthalf.filled", tagline: "Detect creep · draft response",     automationItem: .scopeGuardian),
            AgentFile(id: "pricing",  name: "Pricing Analyst", icon: "chart.bar.fill",         tagline: "Compare deals · optimise pricing",  automationItem: nil),
        ]),
    ]}

    // MARK: - Agent workflow folders

    private var agentWorkflowFolderDrawer: some View {
        GeometryReader { proxy in
            let drawerHeight = agentWorkflowDrawerHeight(for: agentWorkflowFolders.count)
            let drawerWidth = agentWorkflowDrawerWidth(availableWidth: proxy.size.width)
            let drawerX = (proxy.size.width - drawerWidth) / 2
            let activeWorkflow = agentWorkflowFolders.first { $0.id == hoveredAgentWorkflowID } ?? agentWorkflowFolders.first

            ZStack(alignment: .topLeading) {
                Button { setWidgetFocus(.none) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Flows")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white.opacity(0.55))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .help("Back")
                .offset(x: 20, y: Self.expandedHeaderTopOffset)
                .zIndex(Double(agentWorkflowFolders.count) + 2)

                ZStack(alignment: .topLeading) {
                    agentDrawerPerspectiveRails(
                        folderCount: agentWorkflowFolders.count,
                        drawerHeight: drawerHeight
                    )
                    .zIndex(-1)

                    ForEach(Array(agentWorkflowFolders.enumerated()), id: \.element.id) { index, workflow in
                        let folderWidth = agentWorkflowFolderWidth(
                            for: index,
                            total: agentWorkflowFolders.count,
                            availableWidth: drawerWidth
                        )
                        let isHovered = hoveredAgentWorkflowID == workflow.id
                        let isPushed = pushedAgentWorkflowID == workflow.id
                        let flickY = flickYOffset(for: index)
                        let yOff = agentWorkflowFolderYOffset(for: index)
                            - (isHovered ? AgentWorkflowDrawerLayout.hoverLift : 0)
                            - (isPushed ? AgentWorkflowDrawerLayout.pushLift : 0)
                            + flickY
                        let centeredX = (drawerWidth - folderWidth) / 2

                        agentWorkflowFolderInStack(workflow, index: index, folderWidth: folderWidth)
                            .offset(x: centeredX, y: yOff)
                            .zIndex(Double(index))
                            .animation(Motion.focus, value: isHovered)
                            .animation(Motion.focus, value: isPushed)
                            .animation(Motion.focus, value: flickY)
                    }

                    agentDrawerSideRailOverlay(drawerHeight: drawerHeight)
                        .zIndex(Double(agentWorkflowFolders.count) + 0.5)

                    agentDrawerFront(activeWorkflow: activeWorkflow, drawerWidth: drawerWidth)
                        .frame(
                            width: drawerWidth + AgentWorkflowDrawerLayout.drawerFrontExtraWidth,
                            height: AgentWorkflowDrawerLayout.drawerFrontHeight + AgentWorkflowDrawerLayout.drawerFrontClipBleed
                        )
                        .offset(
                            x: -AgentWorkflowDrawerLayout.drawerFrontExtraWidth / 2,
                            y: drawerHeight - AgentWorkflowDrawerLayout.drawerFrontHeight
                        )
                        .shadow(color: .black.opacity(0.28), radius: 14, x: 0, y: 8)
                        .zIndex(Double(agentWorkflowFolders.count) + 1)
                }
                .frame(width: drawerWidth, height: drawerHeight, alignment: .topLeading)
                .clipped()
                .offset(x: drawerX, y: AgentWorkflowDrawerLayout.drawerTopOffset)
            }
            .frame(width: proxy.size.width, height: AgentWorkflowDrawerLayout.totalHeight(for: agentWorkflowFolders.count), alignment: .topLeading)
        }
        .frame(height: AgentWorkflowDrawerLayout.totalHeight(for: agentWorkflowFolders.count))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Folder drawer geometry + layout

    private enum AgentWorkflowDrawerLayout {
        static let drawerTopOffset: CGFloat       = 34
        static let drawerBottomPadding: CGFloat   = 0
        static let maxDrawerWidth: CGFloat        = 780
        static let minDrawerWidth: CGFloat        = 560
        static let horizontalMargin: CGFloat      = 64
        static let folderBodyWidth: CGFloat       = 415
        static let folderBodyHeight: CGFloat      = 100
        static let tabWidth: CGFloat              = 122
        static let tabHeight: CGFloat             = 35
        static let folderHeight: CGFloat          = 100
        static let folderStep: CGFloat            = 57
        static let stackTopPadding: CGFloat       = 52
        static let folderPerspectiveWidening: CGFloat = 180
        static let hoverLift: CGFloat             = 5
        static let pushLift: CGFloat              = 10
        static let drawerFrontHeight: CGFloat     = 82
        static let drawerFrontOverlap: CGFloat    = 80
        static let drawerFrontClipBleed: CGFloat  = 12
        static let drawerFrontExtraWidth: CGFloat = 70
        static let folderHInset: CGFloat          = 14
        static let folderSideSlant: CGFloat       = 18
        static let folderCornerRadius: CGFloat    = 10
        static let tabSideSlant: CGFloat          = 9
        static let tabCornerRadius: CGFloat       = 5
        static let tabUnderlap: CGFloat           = 6
        static let folderIconSize: CGFloat        = 18
        static let folderIconTabWidth: CGFloat    = 122
        static let folderTabEdgePadding: CGFloat  = 8

        static func stackHeight(for count: Int) -> CGFloat {
            guard count > 0 else { return 0 }
            return stackTopPadding
                + CGFloat(count - 1) * folderStep
                + folderHeight
                + drawerFrontHeight
                - drawerFrontOverlap
        }

        static func totalHeight(for count: Int) -> CGFloat {
            drawerTopOffset + stackHeight(for: count) + drawerBottomPadding
        }
    }

    private func agentWorkflowDrawerHeight(for count: Int) -> CGFloat {
        AgentWorkflowDrawerLayout.stackHeight(for: count)
    }

    private func agentWorkflowDrawerWidth(availableWidth: CGFloat) -> CGFloat {
        let maxSafeWidth = max(280, availableWidth - 48)
        return min(
            maxSafeWidth,
            AgentWorkflowDrawerLayout.maxDrawerWidth,
            max(AgentWorkflowDrawerLayout.minDrawerWidth, availableWidth - AgentWorkflowDrawerLayout.horizontalMargin)
        )
    }

    /// Extra y-offset applied to cards near the hovered card to simulate flicking through a file drawer.
    private func flickYOffset(for index: Int) -> CGFloat {
        guard let hoveredID = hoveredAgentWorkflowID,
              let hi = agentWorkflowFolders.firstIndex(where: { $0.id == hoveredID }),
              index != hi else { return 0 }
        let dist = index - hi
        guard abs(dist) <= 3 else { return 0 }
        // Earlier cards fan up; later cards fan down.
        let base: CGFloat = 4.0
        let factor = max(0.0, 1.0 - CGFloat(abs(dist) - 1) * 0.45)
        return CGFloat(dist > 0 ? 1 : -1) * base * factor
    }

    private func agentWorkflowFolderYOffset(for index: Int) -> CGFloat {
        AgentWorkflowDrawerLayout.stackTopPadding + CGFloat(index) * AgentWorkflowDrawerLayout.folderStep
    }

    private func agentWorkflowFolderWidth(for index: Int, total: Int, availableWidth: CGFloat) -> CGFloat {
        let availableBodyWidth = max(280, availableWidth - AgentWorkflowDrawerLayout.folderHInset * 2)
        let backWidth = min(AgentWorkflowDrawerLayout.folderBodyWidth, availableBodyWidth)
        let frontWidth = min(
            availableBodyWidth,
            AgentWorkflowDrawerLayout.folderBodyWidth + AgentWorkflowDrawerLayout.folderPerspectiveWidening
        )
        guard total > 1 else { return frontWidth }
        let depth = CGFloat(index) / CGFloat(total - 1)
        return backWidth + (frontWidth - backWidth) * depth
    }

    private func agentWorkflowIconTabPosition(for index: Int, nameTabPosition: CGFloat) -> CGFloat {
        if nameTabPosition < 0.38 { return 0.68 }
        if nameTabPosition > 0.62 { return 0.24 }
        return index.isMultiple(of: 2) ? 0.22 : 0.74
    }

    private func agentDrawerPerspectiveRails(folderCount: Int, drawerHeight: CGFloat) -> some View {
        GeometryReader { proxy in
            let topY     = agentWorkflowFolderYOffset(for: 0)
            let bottomY  = drawerHeight - AgentWorkflowDrawerLayout.drawerFrontHeight + 22
            let backWidth = agentWorkflowFolderWidth(for: 0, total: folderCount, availableWidth: proxy.size.width)
            let frontWidth = agentWorkflowFolderWidth(for: max(0, folderCount - 1), total: folderCount, availableWidth: proxy.size.width)
            let topInset = max(0, (proxy.size.width - backWidth) / 2)
            let bottomInset = max(0, (proxy.size.width - frontWidth) / 2)
            let leftTopX  = topInset
            let rightTopX = proxy.size.width - topInset
            let leftBotX  = bottomInset
            let rightBotX = proxy.size.width - bottomInset
            let wallFill = colorScheme == .dark ? Color.white.opacity(0.035) : Color.black.opacity(0.035)
            let railStroke = colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.18)

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: leftTopX, y: topY))
                    path.addLine(to: CGPoint(x: leftBotX, y: bottomY))
                    path.addLine(to: CGPoint(x: leftBotX + 14, y: bottomY + 26))
                    path.addLine(to: CGPoint(x: leftTopX + 9, y: topY + 18))
                    path.closeSubpath()

                    path.move(to: CGPoint(x: rightTopX, y: topY))
                    path.addLine(to: CGPoint(x: rightBotX, y: bottomY))
                    path.addLine(to: CGPoint(x: rightBotX - 14, y: bottomY + 26))
                    path.addLine(to: CGPoint(x: rightTopX - 9, y: topY + 18))
                    path.closeSubpath()
                }
                .fill(wallFill)

                Path { path in
                    path.move(to: CGPoint(x: leftTopX, y: topY))
                    path.addLine(to: CGPoint(x: leftBotX, y: bottomY))
                    path.move(to: CGPoint(x: rightTopX, y: topY))
                    path.addLine(to: CGPoint(x: rightBotX, y: bottomY))
                }
                .stroke(railStroke, lineWidth: 1.15)

                Path { path in
                    path.move(to: CGPoint(x: leftTopX + 8, y: topY + 22))
                    path.addLine(to: CGPoint(x: leftBotX + 18, y: bottomY + 22))
                    path.move(to: CGPoint(x: rightTopX - 8, y: topY + 22))
                    path.addLine(to: CGPoint(x: rightBotX - 18, y: bottomY + 22))
                }
                .stroke(railStroke.opacity(0.55), lineWidth: 0.7)
            }
        }
        .allowsHitTesting(false)
    }

    private func agentDrawerSideRailOverlay(drawerHeight: CGFloat) -> some View {
        GeometryReader { proxy in
            let topY = agentWorkflowFolderYOffset(for: 0)
            let bottomY = drawerHeight - AgentWorkflowDrawerLayout.drawerFrontHeight + 22
            let folderCount = agentWorkflowFolders.count
            let backWidth = agentWorkflowFolderWidth(for: 0, total: folderCount, availableWidth: proxy.size.width)
            let frontWidth = agentWorkflowFolderWidth(for: max(0, folderCount - 1), total: folderCount, availableWidth: proxy.size.width)
            let topInset = max(0, (proxy.size.width - backWidth) / 2)
            let bottomInset = max(0, (proxy.size.width - frontWidth) / 2)
            let railStroke = colorScheme == .dark ? Color.white.opacity(0.48) : Color.black.opacity(0.34)

            Path { path in
                path.move(to: CGPoint(x: topInset, y: topY))
                path.addLine(to: CGPoint(x: bottomInset, y: bottomY))
                path.move(to: CGPoint(x: proxy.size.width - topInset, y: topY))
                path.addLine(to: CGPoint(x: proxy.size.width - bottomInset, y: bottomY))
            }
            .stroke(
                railStroke,
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
            )
        }
        .allowsHitTesting(false)
    }

    private func agentDrawerFront(activeWorkflow: AgentWorkflowFolder?, drawerWidth _: CGFloat) -> some View {
        let trayBorder: Color = colorScheme == .dark ? .white : .black
        let trayFill = colorScheme == .dark
            ? Color.black
            : Color(red: 0.90, green: 0.90, blue: 0.93)
        let activeName = activeWorkflow.map { agentWorkflowName($0) } ?? "Select workflow"

        return ZStack(alignment: .topLeading) {
            AgentDrawerFrontShape()
                .fill(trayFill)
                .overlay(
                    AgentDrawerFrontShape()
                        .stroke(trayBorder.opacity(colorScheme == .dark ? 0.28 : 0.22), lineWidth: 1.0)
                )

            Rectangle()
                .fill(trayBorder.opacity(colorScheme == .dark ? 0.34 : 0.26))
                .frame(height: 1)

            HStack(alignment: .center, spacing: 10) {
                Spacer(minLength: 0)

                Text(activeName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.86))
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(colorScheme == .dark ? 0.64 : 0.72))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6)
                    )
            }
            .padding(.horizontal, 32)
            .padding(.top, 12)

            Text("betts flows")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.82))
                .padding(.horizontal, 16)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white.opacity(0.24))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.72), lineWidth: 0.8)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, AgentWorkflowDrawerLayout.drawerFrontClipBleed + 11)
        }
    }

    private func agentWorkflowFolderInStack(
        _ workflow: AgentWorkflowFolder,
        index: Int,
        folderWidth: CGFloat
    ) -> some View {
        let isHovered = hoveredAgentWorkflowID == workflow.id
        let isPushed = pushedAgentWorkflowID == workflow.id
        let tabH = AgentWorkflowDrawerLayout.tabHeight
        let tabBorderColor: Color = workflow.lightTab
            ? (colorScheme == .dark ? Color.black : Color.black)
            : (colorScheme == .dark ? Color.white : Color.black)
        let borderOpacity: Double = (isHovered || isPushed) ? 0.84 : 0.56
        let folderFill = colorScheme == .dark
            ? Color.black
            : Color(red: 0.87, green: 0.87, blue: 0.90)
        let folderBorder = colorScheme == .dark ? Color.white : Color.black
        let outlineOpacity: Double = (isHovered || isPushed) ? 0.86 : 0.58
        let nameTabWidth = min(AgentWorkflowDrawerLayout.tabWidth, folderWidth * 0.34)
        let bodyHeight = AgentWorkflowDrawerLayout.folderBodyHeight
        let tabTop = -tabH + AgentWorkflowDrawerLayout.tabUnderlap
        let nameTabCenter = folderWidth * workflow.tabPosition
        let nameTabLeft = min(
            max(nameTabCenter - nameTabWidth / 2, AgentWorkflowDrawerLayout.folderTabEdgePadding),
            folderWidth - nameTabWidth - AgentWorkflowDrawerLayout.folderTabEdgePadding
        )
        let iconTabWidth = min(AgentWorkflowDrawerLayout.folderIconTabWidth, folderWidth * 0.34)
        let iconTabCenter = folderWidth * agentWorkflowIconTabPosition(for: index, nameTabPosition: workflow.tabPosition)
        let iconTabLeft = min(
            max(iconTabCenter - iconTabWidth / 2, AgentWorkflowDrawerLayout.folderTabEdgePadding),
            folderWidth - iconTabWidth - AgentWorkflowDrawerLayout.folderTabEdgePadding
        )
        let nameTabFill = workflow.lightTab
            ? (colorScheme == .dark ? Color.white : Color(red: 0.12, green: 0.12, blue: 0.14))
            : (colorScheme == .dark ? Color.black : Color(red: 0.76, green: 0.76, blue: 0.80))
        let iconTabFill = colorScheme == .dark
            ? Color.black
            : Color(red: 0.12, green: 0.12, blue: 0.14)
        let iconTabBorder = colorScheme == .dark ? Color.white.opacity(0.70) : Color.black.opacity(0.48)

        return Button {
            withAnimation(.spring(response: 0.18, dampingFraction: 0.70)) {
                hoveredAgentWorkflowID = workflow.id
                pushedAgentWorkflowID = workflow.id
            }

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 95_000_000)
                withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                    hoveredAgentWorkflowID = nil
                    pushedAgentWorkflowID = nil
                    automationDrillIn = workflow.item
                    agentWorkflowMode = .overview
                }
                onPreferredHeightChange(Self.automationsHeight)
            }
        } label: {
            ZStack(alignment: .topLeading) {
                WorkflowDrawerTrapezoidShape(
                    topInset: AgentWorkflowDrawerLayout.tabSideSlant,
                    bottomInset: 0,
                    cornerRadius: AgentWorkflowDrawerLayout.tabCornerRadius
                )
                .fill(nameTabFill)
                .frame(width: nameTabWidth, height: tabH)
                .offset(x: nameTabLeft, y: tabTop)

                WorkflowDrawerTrapezoidShape(
                    topInset: AgentWorkflowDrawerLayout.tabSideSlant,
                    bottomInset: 0,
                    cornerRadius: AgentWorkflowDrawerLayout.tabCornerRadius
                )
                .stroke(
                    tabBorderColor.opacity(borderOpacity),
                    style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round)
                )
                .frame(width: nameTabWidth, height: tabH)
                .offset(x: nameTabLeft, y: tabTop)

                WorkflowDrawerTrapezoidShape(
                    topInset: AgentWorkflowDrawerLayout.tabSideSlant,
                    bottomInset: 0,
                    cornerRadius: AgentWorkflowDrawerLayout.tabCornerRadius
                )
                .fill(iconTabFill)
                .frame(width: iconTabWidth, height: tabH)
                .offset(x: iconTabLeft, y: tabTop)

                WorkflowDrawerTrapezoidShape(
                    topInset: AgentWorkflowDrawerLayout.tabSideSlant,
                    bottomInset: 0,
                    cornerRadius: AgentWorkflowDrawerLayout.tabCornerRadius
                )
                .stroke(
                    iconTabBorder.opacity((isHovered || isPushed) ? 0.94 : 0.72),
                    style: StrokeStyle(lineWidth: 0.95, lineCap: .round, lineJoin: .round)
                )
                .frame(width: iconTabWidth, height: tabH)
                .offset(x: iconTabLeft, y: tabTop)

                let bodyShape = WorkflowDrawerBodyShape(
                    bottomInset: AgentWorkflowDrawerLayout.folderSideSlant,
                    cornerRadius: AgentWorkflowDrawerLayout.folderCornerRadius
                )
                bodyShape
                    .fill(folderFill)
                    .frame(width: folderWidth, height: bodyHeight)
                WorkflowDrawerBodyOpenOutlineShape(
                    bottomInset: AgentWorkflowDrawerLayout.folderSideSlant,
                    cornerRadius: AgentWorkflowDrawerLayout.folderCornerRadius
                )
                    .stroke(
                        folderBorder.opacity(outlineOpacity),
                        style: StrokeStyle(lineWidth: (isHovered || isPushed) ? 1.2 : 1.0, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: folderWidth, height: bodyHeight)

                HStack(spacing: 5) {
                    ForEach(Array(workflow.tools.prefix(3))) { tool in
                        workflowToolIcon(
                            tool,
                            size: AgentWorkflowDrawerLayout.folderIconSize,
                            workflowID: workflow.id
                        )
                    }
                }
                .frame(width: iconTabWidth - 16, height: tabH, alignment: .center)
                .offset(x: iconTabLeft + 8, y: tabTop)
                .opacity((isHovered || isPushed) ? 1.0 : 0.82)

                let onLight = workflow.lightTab ? (colorScheme == .dark) : (colorScheme == .light)
                let idColor: Color   = onLight ? .black.opacity(0.42) : .white.opacity(0.40)
                let nameColor: Color = onLight ? .black.opacity(0.86) : .white.opacity(0.90)
                HStack(spacing: 8) {
                    Text(workflow.folderID)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(idColor)
                    Text(agentWorkflowName(workflow))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(nameColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .truncationMode(.tail)
                }
                .frame(width: nameTabWidth * 0.90, height: tabH, alignment: .leading)
                .offset(x: nameTabLeft + nameTabWidth * 0.05, y: tabTop)
            }
            .frame(width: folderWidth, height: AgentWorkflowDrawerLayout.folderHeight, alignment: .topLeading)
            .shadow(
                color: (isHovered || isPushed) ? .white.opacity(0.06) : .black.opacity(0.30),
                radius: (isHovered || isPushed) ? 10 : 2,
                x: 0, y: (isHovered || isPushed) ? 5 : 1
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .onHover { h in
            withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                hoveredAgentWorkflowID = h ? workflow.id : nil
            }
        }
    }

    private func agentWorkflowDetail(_ workflow: AgentWorkflowFolder) -> some View {
        let workflowName = agentWorkflowName(workflow)
        let tabPosition: CGFloat = 0.68
        let tabHeight: CGFloat = 48
        let tabBottomFraction: CGFloat = 0.62
        let tabTopFraction: CGFloat = 0.52
        let surfaceFill = colorScheme == .dark
            ? Color(red: 0.075, green: 0.075, blue: 0.095)
            : Color(red: 0.88, green: 0.88, blue: 0.91)
        let surfaceStroke = colorScheme == .dark ? Color.white.opacity(0.20) : Color.black.opacity(0.18)

        return ScrollView(showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                WorkflowFolderShape(
                    tabPosition: tabPosition,
                    tabHeight: tabHeight,
                    topCorner: 10,
                    tabBottomFraction: tabBottomFraction,
                    tabTopFraction: tabTopFraction
                )
                    .fill(surfaceFill)
                    .overlay(
                        WorkflowFolderTopOutlineShape(
                            tabPosition: tabPosition,
                            tabHeight: tabHeight,
                            topCorner: 10,
                            tabBottomFraction: tabBottomFraction,
                            tabTopFraction: tabTopFraction
                        )
                            .stroke(surfaceStroke, lineWidth: 0.9)
                    )
                    .shadow(color: .black.opacity(0.24), radius: 14, x: 0, y: 8)

                WorkflowTabShape(
                    tabPosition: tabPosition,
                    tabHeight: tabHeight,
                    topCorner: 10,
                    tabBottomFraction: tabBottomFraction,
                    tabTopFraction: tabTopFraction
                )
                    .fill(colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.82))

                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(workflow.folderID)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.36))
                        Text("Single workflow")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.44))
                        Spacer()
                    }

                    HStack(alignment: .top, spacing: 16) {
                        workflowFlowColumn(workflow)
                            .frame(width: 216, alignment: .topLeading)

                        workflowDetailInspector(workflow)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, tabHeight + 14)
                .padding(.bottom, 18)

                GeometryReader { proxy in
                    let titleWidth = max(180, min(360, proxy.size.width * tabTopFraction - 42))
                    let tabCenter = proxy.size.width * tabPosition
                    let titleLeft = min(
                        max(12, tabCenter - titleWidth / 2),
                        max(12, proxy.size.width - titleWidth - 72)
                    )

                    Text(workflowName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .black.opacity(0.82) : .white.opacity(0.88))
                        .lineLimit(1)
                        .frame(width: titleWidth, alignment: .leading)
                        .position(x: titleLeft + titleWidth / 2, y: 24)
                }
                .frame(height: tabHeight)
                .allowsHitTesting(false)

                HStack(spacing: 8) {
                    workflowIconButton(
                        systemImage: "slider.horizontal.3",
                        label: "Edit workflow",
                        tint: .white.opacity(0.58)
                    ) {
                        withAnimation(Motion.focus) { agentWorkflowMode = .edit }
                    }

                    workflowIconButton(
                        systemImage: "play.fill",
                        label: "Run workflow",
                        tint: workflow.color,
                        isProminent: true
                    ) {
                        withAnimation(Motion.focus) { agentWorkflowMode = .run }
                    }
                }
                .padding(.top, 54)
                .padding(.trailing, 16)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.top, 8)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func workflowFlowColumn(_ workflow: AgentWorkflowFolder) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tools and flow")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.48))

            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(workflow.tools.enumerated()), id: \.element.id) { index, tool in
                    workflowFlowStep(workflow: workflow, tool: tool, index: index)
                    if index < workflow.tools.count - 1 {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(workflow.color.opacity(0.55))
                            .frame(width: 34, height: 18)
                    }
                }
            }

            Button {
                withAnimation(Motion.focus) { agentWorkflowMode = .edit }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Edit icons and workflow")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.62))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Capsule().fill(.white.opacity(0.075)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.10), lineWidth: 0.6))
            }
            .buttonStyle(.plain)
            .pointerCursor()
        }
    }

    private func workflowFlowStep(workflow: AgentWorkflowFolder, tool: WorkflowTool, index: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            workflowToolIcon(tool, size: 34, workflowID: workflow.id)

            VStack(alignment: .leading, spacing: 3) {
                Text(tool.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.84))
                    .lineLimit(1)
                Text(workflowToolStepText(for: workflow, index: index))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.38))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private func workflowDetailInspector(_ workflow: AgentWorkflowFolder) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 9) {
                Image(systemName: workflow.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(workflow.color)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(workflow.color.opacity(0.14)))

                VStack(alignment: .leading, spacing: 2) {
                    Text("What it does")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.90))
                    Text(workflow.summary)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.42))
                        .lineLimit(2)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(workflowDetailBullets(for: workflow), id: \.self) { bullet in
                    HStack(alignment: .top, spacing: 7) {
                        Circle()
                            .fill(workflow.color.opacity(0.70))
                            .frame(width: 4, height: 4)
                            .padding(.top, 6)
                        Text(bullet)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.58))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 0.7)

            workflowSettingRow(
                systemImage: "calendar.badge.clock",
                title: "When it runs",
                value: workflowTriggerText(for: workflow),
                tint: workflow.color
            )

            workflowSettingRow(
                systemImage: "text.badge.checkmark",
                title: "Output",
                value: workflowOutputText(for: workflow),
                tint: workflow.color
            )

            workflowHumanReviewControl(workflow)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.065))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.10), lineWidth: 0.7)
                )
        )
    }

    private func workflowSettingRow(systemImage: String, title: String, value: String, tint _: Color) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.72))
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.08)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.35))
                Text(value)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private func workflowHumanReviewControl(_ workflow: AgentWorkflowFolder) -> some View {
        let isEnabled = agentWorkflowHumanReviewOverrides[workflow.id] ?? true

        return Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
                agentWorkflowHumanReviewOverrides[workflow.id] = !isEnabled
            }
        } label: {
            HStack(alignment: .center, spacing: 9) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.76))
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.08)))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Human review")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.35))
                    Text(isEnabled ? workflowHumanReviewText(for: workflow) : "Runs without a review checkpoint")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
                workflowSwitch(isOn: isEnabled, tint: workflow.color)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    private func workflowSwitch(isOn: Bool, tint _: Color) -> some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? Color.white.opacity(0.20) : Color.white.opacity(0.10))
                .frame(width: 34, height: 18)

            Circle()
                .fill(isOn ? Color.white.opacity(0.86) : Color.white.opacity(0.38))
                .frame(width: 14, height: 14)
                .padding(.horizontal, 2)
        }
        .frame(width: 34, height: 18)
    }

    private func workflowIconButton(
        systemImage: String,
        label: String,
        tint _: Color,
        isProminent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(isProminent ? .black.opacity(0.82) : .white.opacity(0.78))
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(isProminent ? Color.white.opacity(0.82) : Color.white.opacity(0.08))
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(isProminent ? 0.24 : 0.16), lineWidth: 0.7)
                )
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .help(label)
    }

    private func workflowDetailBullets(for workflow: AgentWorkflowFolder) -> [String] {
        switch workflow.item {
        case .preCallBrief:
            return ["Checks the next calendar call and attendees.", "Finds useful customer context in HubSpot.", "Sends a 3-bullet brief before the call."]
        case .logCall:
            return ["Reads the latest meeting notes.", "Updates the right HubSpot contact or deal.", "Drafts a follow-up email from the action items."]
        case .processMeeting:
            return ["Turns meeting notes into owners and next steps.", "Files the summary in Notion.", "Prepares follow-up messages for loose ends."]
        case .proposalDraft:
            return ["Reads the brief and recent account context.", "Builds the proposal outline and key terms.", "Creates a Gmail draft ready for review."]
        case .invoiceChase:
            return ["Checks invoice status and related customer context.", "Writes a polite payment nudge.", "Keeps the tone firm without escalating too early."]
        case .scopeGuardian:
            return ["Looks for scope drift in client messages.", "Compares the ask with the current brief.", "Drafts a clear boundary response."]
        }
    }

    private func workflowToolStepText(for workflow: AgentWorkflowFolder, index: Int) -> String {
        let steps: [String]
        switch workflow.item {
        case .preCallBrief:
            steps = ["Finds the upcoming call", "Pulls customer notes", "Delivers the brief"]
        case .logCall:
            steps = ["Reads call notes", "Finds the CRM record", "Drafts follow-up"]
        case .processMeeting:
            steps = ["Reads the meeting", "Stores action items", "Sends next steps"]
        case .proposalDraft:
            steps = ["Reads the brief", "Adds CRM context", "Drafts proposal email"]
        case .invoiceChase:
            steps = ["Checks payment state", "Finds account owner", "Drafts payment chase"]
        case .scopeGuardian:
            steps = ["Reads client ask", "Checks the brief", "Drafts response"]
        }
        return steps.indices.contains(index) ? steps[index] : "Workflow step"
    }

    private func workflowTriggerText(for workflow: AgentWorkflowFolder) -> String {
        switch workflow.item {
        case .preCallBrief:
            return "5 min before each calendar call"
        case .logCall:
            return "When new meeting notes are ready"
        case .processMeeting:
            return "After a recorded meeting ends"
        case .proposalDraft:
            return "When you add a client brief"
        case .invoiceChase:
            return "On the configured invoice follow-up date"
        case .scopeGuardian:
            return "When a client asks for extra work"
        }
    }

    private func workflowOutputText(for workflow: AgentWorkflowFolder) -> String {
        switch workflow.item {
        case .preCallBrief:
            return "3 bullets, sent as an email brief"
        case .logCall:
            return "CRM update plus follow-up draft"
        case .processMeeting:
            return "Action list and summary handoff"
        case .proposalDraft:
            return "Proposal draft in Gmail"
        case .invoiceChase:
            return "Payment chase email draft"
        case .scopeGuardian:
            return "Boundary response draft"
        }
    }

    private func workflowHumanReviewText(for workflow: AgentWorkflowFolder) -> String {
        switch workflow.item {
        case .preCallBrief:
            return "Ask before sending the brief"
        case .logCall:
            return "Ask before logging CRM changes"
        case .processMeeting:
            return "Ask before sharing next steps"
        case .proposalDraft:
            return "Ask before sending the proposal"
        case .invoiceChase:
            return "Ask before sending payment nudges"
        case .scopeGuardian:
            return "Ask before sending boundary replies"
        }
    }

    private func agentWorkflowEditor(_ workflow: AgentWorkflowFolder) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Folder name")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.42))

                    TextField("Workflow name", text: workflowNameBinding(for: workflow))
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.92))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(workflow.color.opacity(0.24), lineWidth: 0.7)
                        )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Tools and flow")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.42))

                    ForEach(Array(workflow.tools.enumerated()), id: \.element.id) { index, tool in
                        workflowEditableToolRow(workflow: workflow, tool: tool, index: index)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Timing and review")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.42))

                    workflowSettingRow(
                        systemImage: "clock.badge.checkmark",
                        title: "Trigger",
                        value: workflowTriggerText(for: workflow),
                        tint: workflow.color
                    )
                    workflowHumanReviewControl(workflow)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.055))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )

                Button {
                    withAnimation(Motion.focus) { agentWorkflowMode = .overview }
                } label: {
                    Text("Done")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.black.opacity(0.86))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.86))
                        )
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
    }

    private func workflowEditableToolRow(workflow: AgentWorkflowFolder, tool: WorkflowTool, index: Int) -> some View {
        HStack(spacing: 10) {
            workflowToolIcon(tool, size: 30, workflowID: workflow.id)
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.82))
                Text(workflowToolStepText(for: workflow, index: index))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.32))
            }

            Spacer()

            HStack(spacing: 7) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.28))
                Button {
                    withAnimation(Motion.reveal) {
                        cycleWorkflowToolIcon(workflow: workflow, tool: tool)
                    }
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.76))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .help("Change icon")
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func workflowToolIcon(_ tool: WorkflowTool, size: CGFloat, workflowID: String? = nil) -> some View {
        let cornerR = size * 0.22
        let overrideIcon = workflowID.flatMap {
            agentWorkflowToolIconOverrides[workflowToolIconOverrideKey(workflowID: $0, toolID: tool.id)]
        }

        return ZStack {
            RoundedRectangle(cornerRadius: cornerR, style: .continuous)
                .fill(.white.opacity(0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerR, style: .continuous)
                        .strokeBorder(.white.opacity(0.13), lineWidth: 0.5)
                )
            if let overrideIcon {
                Image(systemName: overrideIcon)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundColor(tool.color)
            } else if let iconURL = tool.iconURL {
                AsyncSVGImage(urlString: iconURL, size: size * 0.65)
            } else if let systemImage = tool.systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundColor(tool.color)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 1)
        .help(tool.name)
    }

    private func workflowToolIconOverrideKey(workflowID: String, toolID: String) -> String {
        "\(workflowID).\(toolID)"
    }

    private func cycleWorkflowToolIcon(workflow: AgentWorkflowFolder, tool: WorkflowTool) {
        let key = workflowToolIconOverrideKey(workflowID: workflow.id, toolID: tool.id)
        let choices = workflowEditableIconChoices(for: tool)
        let currentIcon = agentWorkflowToolIconOverrides[key]
        let currentIndex = currentIcon.flatMap { choices.firstIndex(of: $0) }
        let nextIndex = currentIndex.map { ($0 + 1) % choices.count } ?? 0
        agentWorkflowToolIconOverrides[key] = choices[nextIndex]
    }

    private func workflowEditableIconChoices(for tool: WorkflowTool) -> [String] {
        switch tool.id {
        case "calendar":
            return ["calendar", "calendar.badge.clock", "person.2.fill"]
        case "hubspot":
            return ["target", "person.crop.circle.badge.checkmark", "arrow.triangle.branch"]
        case "gmail":
            return ["envelope.fill", "paperplane.fill", "tray.full.fill"]
        case "granola":
            return ["waveform", "text.bubble.fill", "sparkles"]
        case "notion":
            return ["doc.text.fill", "checklist", "square.grid.2x2.fill"]
        case "docs":
            return ["doc.richtext", "doc.badge.plus", "text.alignleft"]
        case "stripe":
            return ["creditcard.fill", "dollarsign.circle.fill", "receipt.fill"]
        case "slack":
            return ["bubble.left.and.bubble.right.fill", "number.circle.fill", "at.circle.fill"]
        default:
            return [tool.systemImage ?? "app.fill", "sparkles", "gearshape.fill"]
        }
    }

    // MARK: - File drawer view

    private var automationListContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(drawerCategories) { category in
                    drawerCategorySection(category)
                }
                Spacer().frame(height: 20)
            }
        }
    }

    private func drawerCategorySection(_ category: AgentCategory) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hanging folder divider — colored tab label + full-width rule
            HStack(alignment: .center, spacing: 0) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(category.color)
                        .frame(width: 6, height: 6)
                    Text(category.name.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(category.color)
                        .tracking(1.2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(category.color.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(category.color.opacity(0.22), lineWidth: 0.5)
                )

                Rectangle()
                    .fill(category.color.opacity(0.18))
                    .frame(maxWidth: .infinity, maxHeight: 0.5)
                    .padding(.leading, 10)

                Text("\(category.agents.count)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.18))
                    .padding(.leading, 8)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 6)

            // File rows
            VStack(spacing: 0) {
                ForEach(Array(category.agents.enumerated()), id: \.element.id) { index, file in
                    fileRow(file, color: category.color)
                    if index < category.agents.count - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.04))
                            .frame(height: 0.5)
                            .padding(.leading, 68)
                            .padding(.trailing, 24)
                    }
                }
            }
        }
    }

    private func fileRow(_ file: AgentFile, color: Color) -> some View {
        Button {
            guard let item = file.automationItem else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                automationDrillIn = item
                if item != .processMeeting { onPreferredHeightChange(Self.logCallHeight) }
            }
        } label: {
            HStack(spacing: 12) {
                // Icon box
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(file.isAvailable ? color.opacity(0.12) : Color.white.opacity(0.04))
                        .frame(width: 36, height: 36)
                    Image(systemName: file.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(file.isAvailable ? color.opacity(0.9) : .white.opacity(0.18))
                }

                // Name + tagline
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(file.isAvailable ? .white.opacity(0.88) : .white.opacity(0.28))
                        .lineLimit(1)
                    Text(file.tagline)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(file.isAvailable ? 0.35 : 0.14))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                // Right indicator
                if !file.isAvailable {
                    Text("SOON")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.white.opacity(0.22))
                        .tracking(0.5)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.07)))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(color.opacity(0.45))
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .opacity(file.isAvailable ? 1.0 : 0.60)
    }

    @ViewBuilder
    private func automationDetailContent(_ item: AutomationItem) -> some View {
        switch item {
        case .logCall:
            ToolConnectionGateView(tools: [.init(name: "HubSpot", composioKey: "HUBSPOT", icon: "person.fill")]) {
                AnyView(
                    ScrollView {
                        YavenLogCallWidget(controller: logCallController)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 10)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .preCallBrief:
            PreCallBriefAutomationView(controller: preCallBriefController)

        case .processMeeting:
            MeetingExpandedView { newHeight in
                onPreferredHeightChange(newHeight + 44)
            }

        case .proposalDraft:
            ProposalDraftView()

        case .invoiceChase:
            InvoiceChaseView()

        case .scopeGuardian:
            ScopeGuardianView()
        }
    }

    // MARK: - First-run overlay

    @ViewBuilder
    private var firstRunOverlay: some View {
        switch firstRunPanelMode {
        case .hidden:
            EmptyView()
        case .firstMessage:
            YavenFirstMessageView(onYes: onFirstRunYes, onLater: onFirstRunLater)
                .padding(.horizontal, 32).padding(.vertical, 18)
        case .cleanup:
            cleanupContent(for: cleanupController.phase)
                .padding(.horizontal, 32).padding(.vertical, 18)
        }
    }

    @ViewBuilder
    private func cleanupContent(for phase: YavenCleanupPhase) -> some View {
        switch phase {
        case .idle:
            ProgressView().controlSize(.small)
        case .scanning(let lines, let visibleLineCount):
            ScanningProgressView(lines: lines, visibleLineCount: visibleLineCount)
        case .awaitingApproval(let plan, let emailsByID):
            CategoriesApprovalContainer(plan: plan, emailsByID: emailsByID, cleanupController: cleanupController, onSkip: onCleanupSkip)
        case .executing(let lines):
            CleanupExecutionView(lines: lines)
        case .done(let archived, let filed, let inbox, let needsReply):
            CleanupDoneView(archivedCount: archived, filedReceiptCount: filed, inboxCount: inbox, needsReplyItems: needsReply, onDraftReply: onDraftReply, onContinue: onCleanupContinue)
        case .skipped, .error:
            Button("Back to Yaven") { onCleanupContinue() }
                .buttonStyle(.bordered).controlSize(.small).pointerCursor()
        }
    }
}

/// Rounded trapezoid used for drawer bodies and independent tabs.
private struct WorkflowDrawerTrapezoidShape: Shape {
    var topInset: CGFloat
    var bottomInset: CGFloat
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let safeTopInset = min(max(0, topInset), rect.width * 0.42)
        let safeBottomInset = min(max(0, bottomInset), rect.width * 0.42)
        let topLeft = rect.minX + safeTopInset
        let topRight = rect.maxX - safeTopInset
        let bottomLeft = rect.minX + safeBottomInset
        let bottomRight = rect.maxX - safeBottomInset
        let maxRadius = min(
            max(0, rect.height / 2),
            max(0, (topRight - topLeft) / 2),
            max(0, (bottomRight - bottomLeft) / 2)
        )
        let radius = min(max(0, cornerRadius), maxRadius)

        var path = Path()
        path.move(to: CGPoint(x: topLeft + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: topRight - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: topRight, y: rect.minY + radius),
            control: CGPoint(x: topRight, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: bottomRight, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: bottomRight - radius, y: rect.maxY),
            control: CGPoint(x: bottomRight, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: bottomLeft + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: bottomLeft, y: rect.maxY - radius),
            control: CGPoint(x: bottomLeft, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: topLeft, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: topLeft + radius, y: rect.minY),
            control: CGPoint(x: topLeft, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

/// Drawer folder body with a full-width top edge and an inset lower edge.
private struct WorkflowDrawerBodyShape: Shape {
    var bottomInset: CGFloat
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let safeBottomInset = min(max(0, bottomInset), rect.width * 0.42)
        let topLeft = rect.minX
        let topRight = rect.maxX
        let bottomLeft = rect.minX + safeBottomInset
        let bottomRight = rect.maxX - safeBottomInset
        let maxRadius = min(
            max(0, rect.height / 2),
            max(0, (topRight - topLeft) / 2),
            max(0, (bottomRight - bottomLeft) / 2)
        )
        let radius = min(max(0, cornerRadius), maxRadius)

        var path = Path()
        path.move(to: CGPoint(x: topLeft + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: topRight - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: topRight, y: rect.minY + radius),
            control: CGPoint(x: topRight, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: bottomRight, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: bottomRight - radius, y: rect.maxY),
            control: CGPoint(x: bottomRight, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: bottomLeft + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: bottomLeft, y: rect.maxY - radius),
            control: CGPoint(x: bottomLeft, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: topLeft, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: topLeft + radius, y: rect.minY),
            control: CGPoint(x: topLeft, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

/// Open folder-body outline: top and sides only, so stacked cards do not expose bottom borders.
private struct WorkflowDrawerBodyOpenOutlineShape: Shape {
    var bottomInset: CGFloat
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let safeBottomInset = min(max(0, bottomInset), rect.width * 0.42)
        let topLeft = rect.minX
        let topRight = rect.maxX
        let bottomLeft = rect.minX + safeBottomInset
        let bottomRight = rect.maxX - safeBottomInset
        let maxRadius = min(
            max(0, rect.height / 2),
            max(0, (topRight - topLeft) / 2),
            max(0, (bottomRight - bottomLeft) / 2)
        )
        let radius = min(max(0, cornerRadius), maxRadius)

        var path = Path()
        path.move(to: CGPoint(x: bottomLeft, y: rect.maxY - radius))
        path.addLine(to: CGPoint(x: topLeft, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: topLeft + radius, y: rect.minY),
            control: CGPoint(x: topLeft, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: topRight - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: topRight, y: rect.minY + radius),
            control: CGPoint(x: topRight, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: bottomRight, y: rect.maxY - radius))
        return path
    }
}

/// Full card shape: trapezoidal tab rising from a body that can taper at the sides for drawer perspective.
private struct WorkflowFolderShape: Shape {
    var tabPosition: CGFloat = 0.3
    var tabHeight: CGFloat   = 44
    var topCorner: CGFloat   = 7   // rounded top corners of the trapezoid
    var tabBottomFraction: CGFloat = 0.52
    var tabTopFraction: CGFloat = 0.42
    var sideSlant: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let bodyTop  = rect.minY + tabHeight
        let maxSideSlant = min(rect.width * 0.16, max(0, rect.height - tabHeight) * 0.8)
        let sideInset = min(max(0, sideSlant), maxSideSlant)
        let bodyLeftTop = rect.minX + sideInset
        let bodyRightTop = rect.maxX - sideInset
        let bHalf = rect.width * tabBottomFraction / 2
        let tHalf = rect.width * tabTopFraction / 2
        let center = rect.minX + rect.width * tabPosition
        let tabBL = max(bodyLeftTop, center - bHalf)
        let tabBR = min(bodyRightTop, center + bHalf)
        let tabTL = max(rect.minX, center - tHalf)
        let tabTR = min(rect.maxX, center + tHalf)

        var path = Path()
        path.move(to: CGPoint(x: bodyLeftTop, y: bodyTop))
        // Left shoulder to tab base
        path.addLine(to: CGPoint(x: tabBL, y: bodyTop))
        // Slope up to top-left, rounded corner
        path.addArc(tangent1End: CGPoint(x: tabTL, y: rect.minY),
                    tangent2End: CGPoint(x: tabTR, y: rect.minY),
                    radius: topCorner)
        // Flat top edge; round top-right corner
        path.addArc(tangent1End: CGPoint(x: tabTR, y: rect.minY),
                    tangent2End: CGPoint(x: tabBR, y: bodyTop),
                    radius: topCorner)
        // Slope back down to body top
        path.addLine(to: CGPoint(x: tabBR, y: bodyTop))
        // Right shoulder to edge
        path.addLine(to: CGPoint(x: bodyRightTop, y: bodyTop))
        // Body sides can slant outward to sell the open-drawer perspective.
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: bodyLeftTop, y: bodyTop))
        path.closeSubpath()
        return path
    }
}

/// Top-only outline for an expanded workflow page; side and bottom borders stay open.
private struct WorkflowFolderTopOutlineShape: Shape {
    var tabPosition: CGFloat = 0.3
    var tabHeight: CGFloat = 44
    var topCorner: CGFloat = 7
    var tabBottomFraction: CGFloat = 0.52
    var tabTopFraction: CGFloat = 0.42

    func path(in rect: CGRect) -> Path {
        let bodyTop = rect.minY + tabHeight
        let bottomHalfWidth = rect.width * tabBottomFraction / 2
        let topHalfWidth = rect.width * tabTopFraction / 2
        let centerX = rect.minX + rect.width * tabPosition
        let tabBottomLeft = max(rect.minX, centerX - bottomHalfWidth)
        let tabBottomRight = min(rect.maxX, centerX + bottomHalfWidth)
        let tabTopLeft = max(rect.minX, centerX - topHalfWidth)
        let tabTopRight = min(rect.maxX, centerX + topHalfWidth)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: bodyTop))
        path.addLine(to: CGPoint(x: tabBottomLeft, y: bodyTop))
        path.addArc(
            tangent1End: CGPoint(x: tabTopLeft, y: rect.minY),
            tangent2End: CGPoint(x: tabTopRight, y: rect.minY),
            radius: topCorner
        )
        path.addArc(
            tangent1End: CGPoint(x: tabTopRight, y: rect.minY),
            tangent2End: CGPoint(x: tabBottomRight, y: bodyTop),
            radius: topCorner
        )
        path.addLine(to: CGPoint(x: tabBottomRight, y: bodyTop))
        path.addLine(to: CGPoint(x: rect.maxX, y: bodyTop))
        return path
    }
}

/// Open-path tab outline — traces left slope + top + right slope only (no bottom line).
/// Used for stroking so stacked cards have no visible separator at the tab base.
private struct WorkflowTabOutlineShape: Shape {
    var tabPosition: CGFloat = 0.3
    var tabHeight: CGFloat   = 44
    var topCorner: CGFloat   = 7
    var tabBottomFraction: CGFloat = 0.52
    var tabTopFraction: CGFloat = 0.42

    func path(in rect: CGRect) -> Path {
        let bodyTop = rect.minY + tabHeight
        let bHalf = rect.width * tabBottomFraction / 2
        let tHalf = rect.width * tabTopFraction / 2
        let center = rect.minX + rect.width * tabPosition
        let tabBL = max(rect.minX, center - bHalf)
        let tabBR = min(rect.maxX, center + bHalf)
        let tabTL = max(rect.minX, center - tHalf)
        let tabTR = min(rect.maxX, center + tHalf)

        var path = Path()
        // Open path: start at base-left, go UP and over the top, end at base-right. No bottom line.
        path.move(to: CGPoint(x: tabBL, y: bodyTop))
        path.addArc(tangent1End: CGPoint(x: tabTL, y: rect.minY),
                    tangent2End: CGPoint(x: tabTR, y: rect.minY),
                    radius: topCorner)
        path.addArc(tangent1End: CGPoint(x: tabTR, y: rect.minY),
                    tangent2End: CGPoint(x: tabBR, y: bodyTop),
                    radius: topCorner)
        path.addLine(to: CGPoint(x: tabBR, y: bodyTop))
        // No closeSubpath — open path, no bottom line drawn
        return path
    }
}

/// Tab-only shape (same trapezoid) for independent fill colour.
private struct WorkflowTabShape: Shape {
    var tabPosition: CGFloat = 0.3
    var tabHeight: CGFloat   = 44
    var topCorner: CGFloat   = 7
    var tabBottomFraction: CGFloat = 0.52
    var tabTopFraction: CGFloat = 0.42

    func path(in rect: CGRect) -> Path {
        let bodyTop = rect.minY + tabHeight
        let bHalf = rect.width * tabBottomFraction / 2
        let tHalf = rect.width * tabTopFraction / 2
        let center = rect.minX + rect.width * tabPosition
        let tabBL = max(rect.minX, center - bHalf)
        let tabBR = min(rect.maxX, center + bHalf)
        let tabTL = max(rect.minX, center - tHalf)
        let tabTR = min(rect.maxX, center + tHalf)

        var path = Path()
        path.move(to: CGPoint(x: tabBL, y: bodyTop))
        path.addArc(tangent1End: CGPoint(x: tabTL, y: rect.minY),
                    tangent2End: CGPoint(x: tabTR, y: rect.minY),
                    radius: topCorner)
        path.addArc(tangent1End: CGPoint(x: tabTR, y: rect.minY),
                    tangent2End: CGPoint(x: tabBR, y: bodyTop),
                    radius: topCorner)
        path.addLine(to: CGPoint(x: tabBR, y: bodyTop))
        path.closeSubpath()
        return path
    }
}

/// Front tray of the file drawer — trapezoidal with wider bottom for the 3D depth illusion.
private struct AgentDrawerFrontShape: Shape {
    func path(in rect: CGRect) -> Path {
        let topSlope: CGFloat  = 22  // inward notch at the top edge
        let cR: CGFloat        = 10  // bottom corner radius

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + topSlope, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topSlope, y: rect.minY))
        // Angled top-right corner
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + topSlope))
        // Right side straight down
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cR))
        // Round bottom-right
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.maxX - cR, y: rect.maxY),
                    radius: cR)
        path.addLine(to: CGPoint(x: rect.minX + cR, y: rect.maxY))
        // Round bottom-left
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.minX, y: rect.maxY - cR),
                    radius: cR)
        // Left side straight up
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topSlope))
        path.closeSubpath()
        return path
    }
}

// MARK: - Compact cards

private struct ChatCompactCard: View {
    @ObservedObject var agentController: YavenAgentController
    let onTap: () -> Void

    var body: some View {
        CompactCard(icon: "bubble.left.fill", title: "Chat", onTap: onTap) {
            if let last = agentController.chatMessages.last {
                Text(last.text)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.50))
                    .lineLimit(3)
                    .lineSpacing(2)
            } else if agentController.isWorking {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini)
                    Text("Working…")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Ask anything…")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.25))
            }
        }
    }
}

private struct ActivityCompactCard: View {
    @ObservedObject var agentController: YavenAgentController
    let onTap: () -> Void

    var body: some View {
        CompactCard(icon: "bolt.fill", title: "Activity", onTap: onTap) {
            let approvals = agentController.needsApprovalThreads.count
            let running   = agentController.runningThreads.count
            let recent    = agentController.recentThreads.count

            VStack(alignment: .leading, spacing: 3) {
                if approvals > 0 {
                    statRow(label: "Needs approval", count: approvals, color: .orange)
                }
                if running > 0 {
                    statRow(label: "Running", count: running, color: .cyan)
                }
                statRow(label: "Recent", count: recent, color: .secondary)
            }
        }
    }

    private func statRow(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text("\(count) \(label)")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.50))
        }
    }
}

private struct NotificationsCompactCard: View {
    let onTap: () -> Void

    var body: some View {
        CompactCard(icon: "bell.fill", title: "Alerts", onTap: onTap) {
            Text("No new alerts")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.25))
        }
    }
}

private struct AutomationsCompactCard: View {
    @ObservedObject var logCallController: LogCallController
    @ObservedObject var briefController: PreCallBriefController
    let onTap: () -> Void

    var body: some View {
        CompactCard(icon: "sparkles", title: "Automations", onTap: onTap) {
            VStack(alignment: .leading, spacing: 3) {
                Text(logCallStatusLabel)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(logCallIsIdle ? 0.25 : 0.55))
                    .lineLimit(1)

                if briefController.lastBrief != nil || briefController.isGenerating {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.blue.opacity(0.7))
                            .frame(width: 5, height: 5)
                        Text(briefController.isGenerating ? "Brief generating…" : "Brief ready")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.45))
                    }
                }
            }
        }
    }

    private var logCallIsIdle: Bool {
        if case .idle = logCallController.phase { return true }
        return false
    }

    private var logCallStatusLabel: String {
        switch logCallController.phase {
        case .idle:                    return "12 agents · 3 workflows"
        case .collectingInput:         return "Log call: paste notes…"
        case .extracting:              return "Log call: analysing…"
        case .awaitingApproval(let a): return "Log call: \(a.count) actions ready"
        case .executing:               return "Log call: running…"
        case .done:                    return "Log call: logged ✓"
        case .failed:                  return "Log call: failed — tap to retry"
        }
    }
}

// MARK: - Pre-call brief automation view

private struct PreCallBriefAutomationView: View {
    @ObservedObject var controller: PreCallBriefController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Status card
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(Color.blue.opacity(0.15)).frame(width: 32, height: 32)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.blue.opacity(0.85))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-active")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Polls calendar every 60 s. Brief appears 5 min before each call.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineSpacing(1)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.blue.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.blue.opacity(0.15), lineWidth: 0.5))

                // Last brief preview
                if let brief = controller.lastBrief {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Last brief")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(brief.prospectName)\(brief.company.isEmpty ? "" : " · \(brief.company)")")
                                .font(.system(size: 13, weight: .medium))

                            briefBullet(label: "Rapport", text: brief.rapport, color: .blue)
                            briefBullet(label: "Lead with", text: brief.painPoint, color: .purple)
                            briefBullet(label: "Expect", text: brief.likelyObjection, color: .orange)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
                    }
                } else {
                    Text("No brief generated yet. One will appear automatically before your next external call.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineSpacing(2)
                        .padding(.top, 2)
                }

                // Test button
                Button {
                    PreCallBriefController.shared.testNow()
                } label: {
                    HStack(spacing: 6) {
                        if controller.isGenerating {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                        }
                        Text(controller.isGenerating ? "Generating…" : "Test Now")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.10)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .disabled(controller.isGenerating)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func briefBullet(label: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(color.opacity(0.7)).frame(width: 5, height: 5).padding(.top, 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.4)
                Text(text)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Chat glass details

private struct ChatInputGlassFill: View {
    let cornerRadius: CGFloat
    let isGlassMode: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return ZStack {
            if isGlassMode, #available(macOS 26.0, *) {
                Color.white.opacity(0.001)
                    .glassEffect(
                        .clear
                            .interactive(true)
                            .tint(Color.white.opacity(0.045)),
                        in: shape
                    )
            } else {
                shape
                    .fill(Color.white.opacity(0.050))
            }

            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.065),
                            Color.white.opacity(0.018),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .clipShape(shape)
    }
}

private struct CursorShineRoundedBorder: View {
    let cornerRadius: CGFloat
    let hoverPoint: CGPoint?

    var body: some View {
        GeometryReader { proxy in
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            let width = max(proxy.size.width, 1)
            let height = max(proxy.size.height, 1)
            let point = hoverPoint ?? CGPoint(x: width / 2, y: height / 2)
            let unitPoint = UnitPoint(
                x: min(max(point.x / width, 0), 1),
                y: min(max(point.y / height, 0), 1)
            )

            ZStack {
                shape
                    .strokeBorder(Color.white.opacity(0.095), lineWidth: 0.6)

                RadialGradient(
                    colors: [
                        Color.white.opacity(hoverPoint == nil ? 0 : 0.54),
                        Color.white.opacity(hoverPoint == nil ? 0 : 0.16),
                        Color.clear
                    ],
                    center: unitPoint,
                    startRadius: 0,
                    endRadius: max(width, height) * 0.62
                )
                .mask(shape.strokeBorder(lineWidth: 1.35))
                .blendMode(.plusLighter)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct ChatEmptyOrbView: View {
    let isGlassMode: Bool

    @State private var hoverPoint: CGPoint? = nil

    var body: some View {
        let size: CGFloat = 56

        return ZStack {
            if isGlassMode, #available(macOS 26.0, *) {
                Color.white.opacity(0.001)
                    .glassEffect(
                        .clear
                            .interactive(true)
                            .tint(Color.white.opacity(0.070)),
                        in: Circle()
                    )
            } else {
                Circle()
                    .fill(.ultraThinMaterial)
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.38),
                            Color.white.opacity(0.14),
                            Color.white.opacity(0.030)
                        ],
                        center: UnitPoint(x: 0.30, y: 0.22),
                        startRadius: 0,
                        endRadius: size * 0.72
                    )
                )

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.20),
                            Color.white.opacity(0.055),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .strokeBorder(Color.white.opacity(0.13), lineWidth: 0.8)

            if let hoverPoint {
                GeometryReader { proxy in
                    let width = max(proxy.size.width, 1)
                    let height = max(proxy.size.height, 1)
                    let unitPoint = UnitPoint(
                        x: min(max(hoverPoint.x / width, 0), 1),
                        y: min(max(hoverPoint.y / height, 0), 1)
                    )

                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.58),
                            Color.white.opacity(0.18),
                            Color.clear
                        ],
                        center: unitPoint,
                        startRadius: 0,
                        endRadius: size * 0.78
                    )
                    .mask(Circle().strokeBorder(lineWidth: 1.2))
                    .blendMode(.plusLighter)
                }
            }

            Ellipse()
                .fill(Color.white.opacity(0.46))
                .frame(width: size * 0.34, height: size * 0.12)
                .blur(radius: 2.4)
                .offset(x: -size * 0.17, y: -size * 0.18)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.18), radius: 9, y: 4)
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                hoverPoint = location
            case .ended:
                hoverPoint = nil
            }
        }
        .animation(.easeOut(duration: 0.16), value: hoverPoint == nil)
        .accessibilityHidden(true)
    }
}

// MARK: - Compact card shell

private struct CompactCard<Content: View>: View {
    let icon: String
    let title: String
    let onTap: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.38))
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.38))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.20))
                }
                content()
                Spacer(minLength: 0)
            }
            .padding(11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 0.75)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }
}
