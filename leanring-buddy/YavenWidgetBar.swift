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

private let homeNeedsYouFakeData: [HomeNeedsYouItem] = [
    HomeNeedsYouItem(logo: .composio("gmail"),       title: "Follow-up to Jamie Chen",    source: "Meeting Loop",      due: "Overdue",   urgency: .overdue),
    HomeNeedsYouItem(logo: .composio("linkedin"),    title: "LinkedIn batch — 10 drafts", source: "LinkedIn Outreach", due: "Due today",  urgency: .today),
    HomeNeedsYouItem(logo: .composio("granola_mcp"), title: "Product sync — notes",        source: "Meeting Loop",      due: "Due today",  urgency: .today),
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
    @State private var isApprovalsReviewing = false
    @State private var approvalsReviewCloseRequestID = UUID()
    @State private var showingChatHistory = false
    @State private var command: String = ""
    @State private var homeNeedsYouItems: [HomeNeedsYouItem] = homeNeedsYouFakeData
    @FocusState private var isCommandFocused: Bool

    @State private var iconNavHovered: Int = -1
    @Environment(\.colorScheme) private var colorScheme

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
            if focus != .approvals { isApprovalsReviewing = false }
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
                    iconNavButton(0, systemImage: "arrow.triangle.branch", label: "Log", focus: .automations)
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
                    homeHeader
                    homeQuickWinsSection
                    homeNeedsYouSection
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
        VStack(alignment: .leading, spacing: 5) {
            Text(greetingText)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
            Text("Tuesday 20 May · 4 meetings today · \(homeNeedsYouItems.count + 3) things need you")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.32))
        }
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
                Circle().fill(tint.opacity(0.14)).frame(width: 32, height: 32)
                Image(systemName: name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(tint.opacity(0.90))
            }
        case .composio(let key):
            ZStack {
                Circle().fill(Color.white).frame(width: 32, height: 32)
                AsyncSVGImage(urlString: "https://logos.composio.dev/api/\(key)", size: 18)
            }
        }
    }

    private func homeActionButton(_ label: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(filled ? .white.opacity(0.88) : homePrimaryBlue.opacity(0.90))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(filled ? Color.white.opacity(0.14) : homePrimaryBlue.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(filled ? Color.white.opacity(0.16) : homePrimaryBlue.opacity(0.28), lineWidth: 0.5)
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
                    .foregroundColor(Color(red: 0.40, green: 0.88, blue: 0.60).opacity(0.90))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color(red: 0.40, green: 0.88, blue: 0.60).opacity(0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color(red: 0.40, green: 0.88, blue: 0.60).opacity(0.28), lineWidth: 0.5)
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

    // MARK: - Icon nav button (Style F — expanding pill)

    private static let navColors: [Color] = [
        Color(red: 1.00, green: 0.65, blue: 0.20),  // Log   — orange
        Color(red: 0.45, green: 0.70, blue: 1.00),  // Flows — blue
        Color(red: 0.40, green: 0.85, blue: 0.75),  // Chat  — teal
        Color(red: 1.00, green: 0.40, blue: 0.40),  // Desk  — red
    ]

    private func iconNavButton(
        _ index: Int,
        systemImage: String,
        label: String,
        focus: WidgetFocus,
        badgeCount: Int = 0
    ) -> some View {
        let itemColor = index < Self.navColors.count ? Self.navColors[index] : Color.white
        let isActive  = widgetFocus == focus
        let isHovered = iconNavHovered == index
        let expanded  = isActive || isHovered

        return Button { setWidgetFocus(focus) } label: {
            HStack(spacing: expanded ? 5 : 0) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isActive ? itemColor : .white.opacity(0.55))
                    if badgeCount > 0 {
                        Text("\(badgeCount)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 3).padding(.vertical, 1)
                            .background(Capsule().fill(isActive ? itemColor : .orange))
                            .offset(x: 6, y: -4)
                    }
                }
                if expanded {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isActive ? itemColor : .white.opacity(0.75))
                        .fixedSize()
                        .transition(.opacity.combined(with: .scale(scale: 0.7, anchor: .leading)))
                }
            }
            .padding(.horizontal, expanded ? 10 : 8)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isActive
                          ? itemColor.opacity(0.18)
                          : (isHovered ? .white.opacity(0.09) : .white.opacity(0.04)))
                    .overlay(
                        Capsule().strokeBorder(
                            isActive ? itemColor.opacity(0.35) : .white.opacity(0.07),
                            lineWidth: 0.5
                        )
                    )
            )
            .animation(.spring(response: 0.30, dampingFraction: 0.68), value: expanded)
            .animation(.spring(response: 0.30, dampingFraction: 0.68), value: isActive)
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .help(label)
        .onHover { h in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                iconNavHovered = h ? index : -1
            }
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
                if widgetFocus == .approvals && isApprovalsReviewing {
                    approvalsReviewCloseRequestID = UUID()
                } else if widgetFocus == .agents,
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
                closeReviewRequestID: approvalsReviewCloseRequestID,
                onReviewStateChange: { isReviewing in
                    guard isApprovalsReviewing != isReviewing else { return }
                    isApprovalsReviewing = isReviewing
                },
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
            YavenOnboardingMascotView(appearance: .black, size: 48)
                .opacity(0.80)

            Text("What do you need?")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.32))

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
        HStack(spacing: 8) {
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
        .padding(.horizontal, 32)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.055))
        .overlay(Rectangle().frame(height: 0.5).foregroundColor(.white.opacity(0.09)), alignment: .top)
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
        let domain: String?         // if set, loads favicon via Google Favicon API
        let systemImage: String?    // fallback SF Symbol when no domain
        let color: Color

        var iconURL: String? {
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
                WorkflowTool(id: "gmail", name: "Gmail", domain: "mail.google.com", systemImage: nil, color: Color(red: 1.0, green: 0.40, blue: 0.40))
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
                WorkflowTool(id: "gmail", name: "Gmail", domain: "mail.google.com", systemImage: nil, color: Color(red: 1.0, green: 0.40, blue: 0.40))
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
                WorkflowTool(id: "gmail", name: "Gmail", domain: "mail.google.com", systemImage: nil, color: Color(red: 1.0, green: 0.40, blue: 0.40))
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
                WorkflowTool(id: "gmail", name: "Gmail", domain: "mail.google.com", systemImage: nil, color: Color(red: 1.0, green: 0.40, blue: 0.40))
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
                WorkflowTool(id: "gmail", name: "Gmail", domain: "mail.google.com", systemImage: nil, color: Color(red: 1.0, green: 0.40, blue: 0.40)),
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
                    Text("Agents")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(.white.opacity(0.82))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.white.opacity(0.045))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .help("Back")
                .offset(x: 28, y: 12)

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
                            .rotation3DEffect(
                                .degrees(agentWorkflowFolderTilt(for: index, isHovered: isHovered, isPushed: isPushed)),
                                axis: (x: 1.0, y: 0.0, z: 0.0),
                                anchor: .top,
                                perspective: 0.52
                            )
                            .offset(x: centeredX, y: yOff)
                            .zIndex(Double(index) + (isHovered || isPushed ? 100 : 0))
                            .animation(Motion.focus, value: isHovered)
                            .animation(Motion.focus, value: isPushed)
                            .animation(Motion.focus, value: flickY)
                    }

                    agentDrawerFront(activeWorkflow: activeWorkflow, drawerWidth: drawerWidth)
                        .frame(
                            width: drawerWidth + AgentWorkflowDrawerLayout.drawerFrontExtraWidth,
                            height: AgentWorkflowDrawerLayout.drawerFrontHeight
                        )
                        .offset(
                            x: -AgentWorkflowDrawerLayout.drawerFrontExtraWidth / 2,
                            y: drawerHeight - AgentWorkflowDrawerLayout.drawerFrontHeight
                        )
                        .shadow(color: .black.opacity(0.28), radius: 14, x: 0, y: 8)
                        .zIndex(Double(agentWorkflowFolders.count) + 1)
                }
                .frame(width: drawerWidth, height: drawerHeight, alignment: .topLeading)
                .offset(x: drawerX, y: AgentWorkflowDrawerLayout.drawerTopOffset)
            }
            .frame(width: proxy.size.width, height: AgentWorkflowDrawerLayout.totalHeight(for: agentWorkflowFolders.count), alignment: .topLeading)
        }
        .frame(height: AgentWorkflowDrawerLayout.totalHeight(for: agentWorkflowFolders.count))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Folder drawer geometry + layout

    private enum AgentWorkflowDrawerLayout {
        static let drawerTopOffset: CGFloat       = 58
        static let drawerBottomPadding: CGFloat   = 12
        static let maxDrawerWidth: CGFloat        = 540
        static let minDrawerWidth: CGFloat        = 390
        static let horizontalMargin: CGFloat      = 108
        static let tabHeight: CGFloat             = 32
        static let tabBottomWidthFraction: CGFloat = 0.46
        static let tabTopWidthFraction: CGFloat   = 0.36
        static let folderHeight: CGFloat          = 76
        static let folderStep: CGFloat            = 39
        static let stackTopPadding: CGFloat       = 20
        static let hoverLift: CGFloat             = 10
        static let pushLift: CGFloat              = 18
        static let drawerFrontHeight: CGFloat     = 78
        static let drawerFrontOverlap: CGFloat    = 36
        static let drawerFrontExtraWidth: CGFloat = 62
        static let folderHInset: CGFloat          = 50
        static let perspectiveNarrowing: CGFloat  = 68

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
        let base: CGFloat = 9.0
        let factor = max(0.0, 1.0 - CGFloat(abs(dist) - 1) * 0.45)
        return CGFloat(dist > 0 ? 1 : -1) * base * factor
    }

    private func agentWorkflowFolderYOffset(for index: Int) -> CGFloat {
        AgentWorkflowDrawerLayout.stackTopPadding + CGFloat(index) * AgentWorkflowDrawerLayout.folderStep
    }

    private func agentWorkflowFolderWidth(for index: Int, total: Int, availableWidth: CGFloat) -> CGFloat {
        let depth = total <= 1 ? 1 : CGFloat(index) / CGFloat(total - 1)
        let base = availableWidth - AgentWorkflowDrawerLayout.folderHInset * 2
        return base - AgentWorkflowDrawerLayout.perspectiveNarrowing * (1 - depth)
    }

    private func agentWorkflowFolderTilt(for index: Int, isHovered: Bool, isPushed: Bool) -> Double {
        guard agentWorkflowFolders.count > 1 else { return 0 }
        let depth = Double(index) / Double(agentWorkflowFolders.count - 1)
        let baseTilt = -2.0 + depth * 1.1
        if isPushed { return baseTilt + 2.2 }
        return isHovered ? baseTilt + 0.8 : baseTilt
    }

    private func agentDrawerPerspectiveRails(folderCount _: Int, drawerHeight: CGFloat) -> some View {
        GeometryReader { proxy in
            let topY     = agentWorkflowFolderYOffset(for: 0) + AgentWorkflowDrawerLayout.tabHeight
            let bottomY  = drawerHeight - AgentWorkflowDrawerLayout.drawerFrontHeight + 22
            let topInset = AgentWorkflowDrawerLayout.folderHInset + AgentWorkflowDrawerLayout.perspectiveNarrowing / 2
            let bottomInset = -AgentWorkflowDrawerLayout.drawerFrontExtraWidth / 2 + 7
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

    private func agentDrawerFront(activeWorkflow: AgentWorkflowFolder?, drawerWidth _: CGFloat) -> some View {
        let trayBorder: Color = colorScheme == .dark ? .white : .black
        let trayFill = colorScheme == .dark
            ? Color(red: 0.08, green: 0.08, blue: 0.10)
            : Color(red: 0.90, green: 0.90, blue: 0.93)
        let activeName = activeWorkflow.map { agentWorkflowName($0) } ?? "Select workflow"

        return ZStack(alignment: .topLeading) {
            AgentDrawerFrontShape()
                .fill(trayFill)
                .overlay(
                    AgentDrawerFrontShape()
                        .stroke(trayBorder.opacity(colorScheme == .dark ? 0.28 : 0.22), lineWidth: 1.0)
                )

            HStack(alignment: .center, spacing: 10) {
                if let activeWorkflow {
                    HStack(spacing: 5) {
                        ForEach(Array(activeWorkflow.tools.prefix(3))) { tool in
                            workflowToolIcon(tool, size: 19, workflowID: activeWorkflow.id)
                        }
                    }
                }

                Spacer(minLength: 12)

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

            Text("Betts interns")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color(red: 0.13, green: 0.10, blue: 0.02))
                .padding(.horizontal, 16)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color(red: 0.98, green: 0.90, blue: 0.42))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 11)
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
            ? Color(red: 0.07, green: 0.07, blue: 0.09)
            : Color(red: 0.87, green: 0.87, blue: 0.90)
        let folderBorder = colorScheme == .dark ? Color.white : Color.black
        let bodyRule = colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.10)

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
                WorkflowFolderShape(
                    tabPosition: workflow.tabPosition,
                    tabHeight: tabH,
                    tabBottomFraction: AgentWorkflowDrawerLayout.tabBottomWidthFraction,
                    tabTopFraction: AgentWorkflowDrawerLayout.tabTopWidthFraction
                )
                    .fill(folderFill)
                    .overlay(
                        WorkflowFolderShape(
                            tabPosition: workflow.tabPosition,
                            tabHeight: tabH,
                            tabBottomFraction: AgentWorkflowDrawerLayout.tabBottomWidthFraction,
                            tabTopFraction: AgentWorkflowDrawerLayout.tabTopWidthFraction
                        )
                            .stroke(folderBorder.opacity((isHovered || isPushed) ? 0.40 : 0.22), lineWidth: (isHovered || isPushed) ? 1.15 : 0.85)
                    )

                Rectangle()
                    .fill(bodyRule)
                    .frame(height: 0.7)
                    .offset(y: tabH)

                WorkflowTabShape(
                    tabPosition: workflow.tabPosition,
                    tabHeight: tabH,
                    tabBottomFraction: AgentWorkflowDrawerLayout.tabBottomWidthFraction,
                    tabTopFraction: AgentWorkflowDrawerLayout.tabTopWidthFraction
                )
                    .fill(workflow.lightTab
                          ? (colorScheme == .dark ? Color.white : Color(red: 0.12, green: 0.12, blue: 0.14))
                          : (colorScheme == .dark ? Color(red: 0.18, green: 0.18, blue: 0.22) : Color(red: 0.76, green: 0.76, blue: 0.80)))
                WorkflowTabOutlineShape(
                    tabPosition: workflow.tabPosition,
                    tabHeight: tabH,
                    tabBottomFraction: AgentWorkflowDrawerLayout.tabBottomWidthFraction,
                    tabTopFraction: AgentWorkflowDrawerLayout.tabTopWidthFraction
                )
                    .stroke(tabBorderColor.opacity(borderOpacity), lineWidth: 1.0)

                let tabBW = folderWidth * AgentWorkflowDrawerLayout.tabBottomWidthFraction
                let tabCenter = folderWidth * workflow.tabPosition
                let tabLeft = min(max(tabCenter - tabBW / 2, 8), folderWidth - tabBW - 8)
                let onLight = workflow.lightTab ? (colorScheme == .dark) : (colorScheme == .light)
                let idColor: Color   = onLight ? .black.opacity(0.42) : .white.opacity(0.40)
                let nameColor: Color = onLight ? .black.opacity(0.86) : .white.opacity(0.90)
                HStack(spacing: 8) {
                    Text(workflow.folderID)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(idColor)
                    Text(agentWorkflowName(workflow))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(nameColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(width: tabBW * 0.88, alignment: .leading)
                .offset(x: tabLeft + tabBW * 0.06, y: (tabH - 14) / 2)
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

    private func workflowSettingRow(systemImage: String, title: String, value: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(tint.opacity(0.85))
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tint.opacity(0.12)))

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
                    .foregroundColor(workflow.color.opacity(0.85))
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(workflow.color.opacity(0.12)))

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

    private func workflowSwitch(isOn: Bool, tint: Color) -> some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? tint.opacity(0.34) : Color.white.opacity(0.10))
                .frame(width: 34, height: 18)

            Circle()
                .fill(isOn ? tint : Color.white.opacity(0.38))
                .frame(width: 14, height: 14)
                .padding(.horizontal, 2)
        }
        .frame(width: 34, height: 18)
    }

    private func workflowIconButton(
        systemImage: String,
        label: String,
        tint: Color,
        isProminent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(isProminent ? .black.opacity(0.82) : tint)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(isProminent ? tint.opacity(0.95) : Color.white.opacity(0.08))
                )
                .overlay(
                    Circle()
                        .strokeBorder(isProminent ? Color.white.opacity(0.18) : tint.opacity(0.24), lineWidth: 0.7)
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
                        .foregroundColor(workflow.color.opacity(0.85))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(workflow.color.opacity(0.12)))
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

/// Full card shape: trapezoidal tab (wider at base, narrower at top) rising from the body.
/// Body is a flat rectangle with no corner rounding — just like a physical file card.
private struct WorkflowFolderShape: Shape {
    var tabPosition: CGFloat = 0.3
    var tabHeight: CGFloat   = 44
    var topCorner: CGFloat   = 7   // rounded top corners of the trapezoid
    var tabBottomFraction: CGFloat = 0.52
    var tabTopFraction: CGFloat = 0.42

    func path(in rect: CGRect) -> Path {
        let bodyTop  = rect.minY + tabHeight
        let bHalf = rect.width * tabBottomFraction / 2
        let tHalf = rect.width * tabTopFraction / 2
        let center = rect.minX + rect.width * tabPosition
        let tabBL = max(rect.minX, center - bHalf)
        let tabBR = min(rect.maxX, center + bHalf)
        let tabTL = max(rect.minX, center - tHalf)
        let tabTR = min(rect.maxX, center + tHalf)

        var path = Path()
        // Start at far-left of body top
        path.move(to: CGPoint(x: rect.minX, y: bodyTop))
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
        path.addLine(to: CGPoint(x: rect.maxX, y: bodyTop))
        // Body — flat rectangle, zero rounding
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: bodyTop))
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
