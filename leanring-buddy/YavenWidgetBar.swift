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
    @State private var showingChatHistory = false
    @State private var command: String = ""
    @State private var homeNeedsYouItems: [HomeNeedsYouItem] = homeNeedsYouFakeData
    @FocusState private var isCommandFocused: Bool

    private static let compactHeight: CGFloat        = 380
    private static let chatHeight: CGFloat           = 420
    private static let automationsHeight: CGFloat    = 420
    private static let notificationsHeight: CGFloat  = 220
    private static let logCallHeight: CGFloat        = 380
    private static let meetingHeight: CGFloat        = 460

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
            if focus != .logCall { automationDrillIn = nil }
        }
        // When the shell requests focus (hotkey / notification tap), focus input without switching views.
        .onChange(of: focusCoordinator.focusRequestID) { _, _ in
            DispatchQueue.main.async { isCommandFocused = true }
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
        case .agents:        return Self.automationsHeight
        case .approvals:     return Self.automationsHeight
        }
    }

    // MARK: - Compact row (home screen)

    private var compactRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Icon nav bar
            HStack {
                HStack(spacing: 24) {
                    iconNavButton(systemImage: "scroll", label: "Log", focus: .automations)
                    iconNavButton(systemImage: "bolt.fill", label: "Flows", focus: .agents)
                }
                Spacer()
                HStack(spacing: 24) {
                    iconNavButton(systemImage: "bubble.left.fill", label: "Chat", focus: .chat)
                    iconNavButton(
                        systemImage: "tray.fill",
                        label: "Desk",
                        focus: .approvals,
                        badgeCount: agentController.needsApprovalThreads.count
                    )
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, -32)

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

    private func iconNavButton(
        systemImage: String,
        label: String,
        focus: WidgetFocus,
        badgeCount: Int = 0
    ) -> some View {
        Button {
            setWidgetFocus(focus)
        } label: {
            VStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.white.opacity(0.60))
                    if badgeCount > 0 {
                        Text("\(badgeCount)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange))
                            .offset(x: 8, y: -4)
                    }
                }
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    // MARK: - Expanded wrapper

    private var expandedView: some View {
        VStack(spacing: 0) {
            expandedHeader
            Divider().opacity(0.12)
            expandedContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, -32)
    }

    private var expandedHeader: some View {
        HStack(spacing: 0) {
            Button {
                if widgetFocus == .logCall, automationDrillIn != nil {
                    withAnimation(Motion.focus) { automationDrillIn = nil }
                    onPreferredHeightChange(Self.automationsHeight)
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
            } else if widgetFocus == .agents {
                Button {
                    // New flow — no-op in demo
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("New flow")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.50))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .pointerCursor()
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
        case .agents:        return "Flows"
        case .approvals:     return "Desk"
        case .none:          return ""
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        switch widgetFocus {
        case .chat:
            chatExpandedView
        case .automations:
            YavenLogView()
        case .notifications:
            notificationsExpandedView
        case .logCall:
            automationsExpandedView2
        case .meeting:
            MeetingExpandedView { newHeight in
                onPreferredHeightChange(newHeight + 44) // +44 for the expanded header
            }
        case .agents:
            YavenFlowsView()
        case .approvals:
            YavenDeskView()
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
            YavenOnboardingMascotView(appearance: .cloud, size: 48)
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
                    YavenOnboardingMascotView(appearance: .cloud, size: 20)
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
        Group {
            if let drill = automationDrillIn {
                automationDetailContent(drill)
            } else {
                automationListContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
