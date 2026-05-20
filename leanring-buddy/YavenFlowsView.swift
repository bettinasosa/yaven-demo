//
//  YavenFlowsView.swift
//  leanring-buddy
//
//  Flows tab — saved automation workflow cards with step chain visualization.
//  All data is static / fake for the demo.
//

import SwiftUI

// MARK: - Design tokens

private let notifyStepColor = Color(red: 0.95, green: 0.75, blue: 0.30)
private let activeStatusColor = Color(red: 0.35, green: 0.88, blue: 0.58)

// MARK: - Models

private enum StepLogo {
    case favicon(String)
    case sfSymbol(String)
    case yaven
}

private struct FlowStep: Identifiable {
    let id: String
    let logo: StepLogo
    let toolName: String
    let description: String
    var notifyMe: Bool

    init(id: String, logo: StepLogo, toolName: String, description: String,
         notifyMe: Bool = false) {
        self.id = id; self.logo = logo; self.toolName = toolName
        self.description = description; self.notifyMe = notifyMe
    }
}

private enum FlowStatus { case active, paused }

private struct SavedFlow: Identifiable {
    let id: String
    var name: String
    var status: FlowStatus
    var steps: [FlowStep]
    let lastRun: String?
    let suggestedDescription: String?
    var hasNotifySteps: Bool { steps.contains { $0.notifyMe } }

    init(id: String, name: String, status: FlowStatus, steps: [FlowStep],
         lastRun: String?, suggestedDescription: String? = nil) {
        self.id = id; self.name = name; self.status = status
        self.steps = steps; self.lastRun = lastRun
        self.suggestedDescription = suggestedDescription
    }
}

// MARK: - Step picker options

private struct AddableStep {
    let logo: StepLogo
    let toolName: String
    let description: String
}

private let addableStepOptions: [AddableStep] = [
    AddableStep(logo: .favicon(clogo("gmail")),            toolName: "Gmail",           description: "Send or receive email"),
    AddableStep(logo: .favicon(clogo("googlecalendar")),   toolName: "Google Calendar", description: "Calendar event trigger"),
    AddableStep(logo: .favicon(clogo("slack")),            toolName: "Slack",           description: "Send notification"),
    AddableStep(logo: .favicon(clogo("notion")),           toolName: "Notion",          description: "Write or update page"),
    AddableStep(logo: .favicon(clogo("linkedin")),         toolName: "LinkedIn",        description: "Research or message"),
    AddableStep(logo: .favicon(clogo("granola_mcp")),      toolName: "Granola",         description: "Meeting notes"),
    AddableStep(logo: .sfSymbol("globe"),                  toolName: "Web",             description: "Browse or scrape web"),
    AddableStep(logo: .yaven,                              toolName: "Yaven",           description: "AI processing step"),
]

// MARK: - Logo helpers

private func clogo(_ key: String) -> String {
    "https://logos.composio.dev/api/\(key)"
}

// MARK: - Fake data

private let initialFlows: [SavedFlow] = [

    SavedFlow(
        id: "f1", name: "Morning Briefing", status: .active,
        steps: [
            FlowStep(id: "f1s1", logo: .favicon(clogo("gmail")),            toolName: "Gmail",           description: "Scans overnight emails, flags anything urgent"),
            FlowStep(id: "f1s2", logo: .favicon(clogo("googlecalendar")),   toolName: "Google Calendar", description: "Pulls today's meetings"),
            FlowStep(id: "f1s3", logo: .yaven,                              toolName: "Yaven",           description: "Compiles into a single morning brief"),
            FlowStep(id: "f1s4", logo: .yaven,                              toolName: "Yaven Desk",      description: "Delivers to your desk at 7:30am", notifyMe: true),
        ],
        lastRun: "Today 7:30am"
    ),

    SavedFlow(
        id: "f2", name: "Meeting Loop", status: .active,
        steps: [
            FlowStep(id: "f2s1", logo: .favicon(clogo("googlecalendar")),   toolName: "Google Calendar", description: "Triggers on upcoming meeting"),
            FlowStep(id: "f2s2", logo: .yaven,                              toolName: "Yaven",           description: "Builds pre-meeting brief from email history"),
            FlowStep(id: "f2s3", logo: .favicon(clogo("granola_mcp")),      toolName: "Granola",         description: "Captures live meeting notes"),
            FlowStep(id: "f2s4", logo: .yaven,                              toolName: "Yaven",           description: "Drafts action items and follow-ups", notifyMe: true),
            FlowStep(id: "f2s5", logo: .favicon(clogo("notion")),           toolName: "Notion",          description: "Syncs notes and action items"),
        ],
        lastRun: "Today 9:34am"
    ),

    SavedFlow(
        id: "f3", name: "Job Application", status: .paused,
        steps: [
            FlowStep(id: "f3s1", logo: .sfSymbol("globe"),                  toolName: "Web",   description: "Reads and analyses the job description"),
            FlowStep(id: "f3s2", logo: .yaven,                              toolName: "Yaven", description: "Tailors your CV to match key requirements", notifyMe: true),
            FlowStep(id: "f3s3", logo: .yaven,                              toolName: "Yaven", description: "Writes a personalised cover letter",        notifyMe: true),
        ],
        lastRun: "Mon 19 May"
    ),

    SavedFlow(
        id: "f4", name: "Prospect Research & Outreach", status: .active,
        steps: [
            FlowStep(id: "f4s1", logo: .favicon(clogo("googledocs")),       toolName: "Google Docs", description: "Reads your ICP criteria"),
            FlowStep(id: "f4s2", logo: .favicon(clogo("linkedin")),         toolName: "LinkedIn",    description: "Finds 50 matching profiles"),
            FlowStep(id: "f4s3", logo: .sfSymbol("globe"),                  toolName: "Web",         description: "Researches each company for recent milestones"),
            FlowStep(id: "f4s4", logo: .favicon(clogo("apollo")),           toolName: "Apollo",      description: "Enriches profiles with contact data"),
            FlowStep(id: "f4s5", logo: .yaven,                              toolName: "Yaven",       description: "Drafts a personalised message for each person", notifyMe: true),
        ],
        lastRun: "Yesterday 8:00am"
    ),

    SavedFlow(
        id: "f5", name: "Weekly Update", status: .active,
        steps: [
            FlowStep(id: "f5s1", logo: .favicon(clogo("googlecalendar")),   toolName: "Google Calendar", description: "Pulls this week's meetings"),
            FlowStep(id: "f5s2", logo: .favicon(clogo("notion")),           toolName: "Notion",          description: "Gathers completed tasks and project notes"),
            FlowStep(id: "f5s3", logo: .yaven,                              toolName: "Yaven",           description: "Drafts a concise weekly update", notifyMe: true),
            FlowStep(id: "f5s4", logo: .favicon(clogo("slack")),            toolName: "Slack",           description: "Sends to your team"),
        ],
        lastRun: "Mon 19 May 4:00pm"
    ),
]

private let suggestedFlowData = SavedFlow(
    id: "suggested1",
    name: "Conference Follow-up",
    status: .paused,
    steps: [
        FlowStep(id: "sf1", logo: .favicon(clogo("linkedin")),    toolName: "LinkedIn", description: "Researches each new connection"),
        FlowStep(id: "sf2", logo: .yaven,                         toolName: "Yaven",    description: "Drafts personalised follow-up messages", notifyMe: true),
        FlowStep(id: "sf3", logo: .favicon(clogo("gmail")),       toolName: "Gmail",    description: "Sends approved messages"),
    ],
    lastRun: nil,
    suggestedDescription: "You connected with 12 people at your last event. I can research each one and draft a follow-up message for you to review."
)

// MARK: - Root view

struct YavenFlowsView: View {
    @State private var flows: [SavedFlow] = initialFlows
    @State private var viewingFlow: SavedFlow? = nil

    var body: some View {
        ZStack {
            flowList
            if let flow = viewingFlow {
                FlowDetailView(flow: flow) {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                        viewingFlow = nil
                    }
                } onSave: { updated in
                    if let idx = flows.firstIndex(where: { $0.id == updated.id }) {
                        flows[idx] = updated
                    }
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                        viewingFlow = nil
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .trailing).combined(with: .opacity)
                ))
                .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            let allSteps = initialFlows.flatMap(\.steps) + suggestedFlowData.steps
            let urls: [String] = allSteps.compactMap {
                if case .favicon(let u) = $0.logo { return u } else { return nil }
            }
            await withTaskGroup(of: Void.self) { group in
                for urlString in Set(urls) {
                    group.addTask(priority: .userInitiated) {
                        guard await SVGImageCache.shared.get(urlString) == nil,
                              let url = URL(string: urlString),
                              let (data, _) = try? await URLSession.shared.data(from: url),
                              let img = NSImage(data: data) else { return }
                        await SVGImageCache.shared.set(urlString, image: img)
                    }
                }
            }
        }
    }

    private var flowList: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach($flows) { $flow in
                    FlowCard(flow: $flow) { viewingFlow = flow }
                }

                Text("SUGGESTED")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.28))
                    .kerning(0.6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)

                SuggestedFlowCard(flow: suggestedFlowData) {
                    // visual-only in demo
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Flow card

private struct FlowCard: View {
    @Binding var flow: SavedFlow
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            headerRow
            StepChain(steps: flow.steps)
            if let lastRun = flow.lastRun {
                Text("Last run \(lastRun)")
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.28))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.07)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    flow.hasNotifySteps && flow.status == .active
                        ? notifyStepColor.opacity(0.32)
                        : Color.white.opacity(0.09),
                    lineWidth: flow.hasNotifySteps && flow.status == .active ? 1.0 : 0.5
                )
        )
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(flow.status == .active ? activeStatusColor : Color.white.opacity(0.22))
                .frame(width: 7, height: 7)
            Text(flow.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.88))
                .lineLimit(1)
            Spacer()
            HStack(spacing: 7) {
                cardButton(icon: flow.status == .active ? "pause.fill" : "play.fill") {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        flow.status = flow.status == .active ? .paused : .active
                    }
                }
                cardButton(icon: "chevron.right") { onEdit() }
            }
        }
    }

    private func cardButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.38))
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }
}

// MARK: - Step chain

private struct StepChain: View {
    let steps: [FlowStep]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    StepBubble(step: step)
                    if index < steps.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.white.opacity(0.20))
                            .padding(.horizontal, 1)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct StepBubble: View {
    let step: FlowStep

    private var circleFill: Color {
        switch step.logo {
        case .favicon: return .white
        case .sfSymbol, .yaven:
            return step.notifyMe ? notifyStepColor.opacity(0.18) : Color.white.opacity(0.10)
        }
    }

    private var circleStroke: Color {
        if step.notifyMe { return notifyStepColor.opacity(0.55) }
        switch step.logo {
        case .favicon:   return Color.black.opacity(0.06)
        case .sfSymbol:  return Color.white.opacity(0.12)
        case .yaven:     return Color.white.opacity(0.35)
        }
    }

    private var strokeWidth: CGFloat {
        if case .yaven = step.logo { return 1.0 }
        return step.notifyMe ? 1.0 : 0.5
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(circleFill)
                .frame(width: 28, height: 28)
                .overlay(Circle().stroke(circleStroke, lineWidth: strokeWidth))
            StepLogoView(logo: step.logo, size: 15)
        }
        .frame(width: 28, height: 28)
    }
}

// MARK: - Shared step logo renderer

private struct StepLogoView: View {
    let logo: StepLogo
    let size: CGFloat

    var body: some View {
        Group {
            switch logo {
            case .favicon(let url):
                AsyncSVGImage(urlString: url, size: size)
            case .sfSymbol(let name):
                Image(systemName: name)
                    .font(.system(size: size * 0.72, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))
            case .yaven:
                Image(systemName: "cloud.fill")
                    .font(.system(size: size * 0.72, weight: .medium))
                    .foregroundColor(.white.opacity(0.88))
            }
        }
    }
}

// MARK: - Suggested flow card

private struct SuggestedFlowCard: View {
    let flow: SavedFlow
    let onAdd: () -> Void
    @State private var added = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Text(flow.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.72))
                Spacer(minLength: 8)
                Button {
                    guard !added else { return }
                    added = true
                    onAdd()
                } label: {
                    Text(added ? "Added ✓" : "Add")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(added ? activeStatusColor.opacity(0.80) : .white.opacity(0.88))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(added ? activeStatusColor.opacity(0.10) : Color.white.opacity(0.12)))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(added ? activeStatusColor.opacity(0.25) : Color.white.opacity(0.12), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .disabled(added)
            }

            if let desc = flow.suggestedDescription {
                Text(desc)
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.40))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            StepChain(steps: flow.steps)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.07), lineWidth: 0.5))
    }
}

// MARK: - Flow detail view

private struct FlowDetailView: View {
    let flow: SavedFlow
    let onBack: () -> Void
    let onSave: (SavedFlow) -> Void

    @State private var editedName: String
    @State private var editedStatus: FlowStatus
    @State private var editedSteps: [FlowStep]
    @State private var showingStepPicker = false

    init(flow: SavedFlow, onBack: @escaping () -> Void, onSave: @escaping (SavedFlow) -> Void) {
        self.flow = flow; self.onBack = onBack; self.onSave = onSave
        _editedName   = State(initialValue: flow.name)
        _editedStatus = State(initialValue: flow.status)
        _editedSteps  = State(initialValue: flow.steps)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                detailHeader
                Divider().opacity(0.10)
                nameField
                stepList
            }
            .background(Color(red: 0.06, green: 0.06, blue: 0.06))

            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var detailHeader: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Flows")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.55))
            }
            .buttonStyle(.plain)
            .pointerCursor()

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    editedStatus = editedStatus == .active ? .paused : .active
                }
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(editedStatus == .active ? activeStatusColor : Color.white.opacity(0.22))
                        .frame(width: 7, height: 7)
                    Text(editedStatus == .active ? "Active" : "Paused")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.65))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .pointerCursor()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var nameField: some View {
        TextField("Flow name", text: $editedName)
            .textFieldStyle(.plain)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white.opacity(0.90))
            .tint(.white)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)
    }

    private var stepList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(Array(editedSteps.enumerated()), id: \.element.id) { index, step in
                    let sid = step.id
                    DetailStepRow(step: step) {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                            editedSteps.removeAll { $0.id == sid }
                        }
                    } onToggleNotify: {
                        if let idx = editedSteps.firstIndex(where: { $0.id == sid }) {
                            editedSteps[idx].notifyMe.toggle()
                        }
                    }

                    if index < editedSteps.count - 1 {
                        HStack {
                            Spacer().frame(width: 17)
                            Rectangle()
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 1, height: 14)
                            Spacer()
                        }
                    }
                }

                addStepSection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 84)
        }
    }

    private var addStepSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showingStepPicker.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showingStepPicker ? "minus.circle" : "plus.circle")
                        .font(.system(size: 13))
                    Text(showingStepPicker ? "Cancel" : "Add step")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.38))
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .padding(.top, 12)

            if showingStepPicker {
                stepPickerStrip
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var stepPickerStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(addableStepOptions, id: \.toolName) { option in
                    Button {
                        let newStep = FlowStep(
                            id: UUID().uuidString,
                            logo: option.logo,
                            toolName: option.toolName,
                            description: option.description
                        )
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            editedSteps.append(newStep)
                            showingStepPicker = false
                        }
                    } label: {
                        VStack(spacing: 5) {
                            ZStack {
                                Circle()
                                    .fill({
                                        switch option.logo {
                                        case .favicon:          return Color.white
                                        case .sfSymbol, .yaven: return Color.white.opacity(0.10)
                                        }
                                    }())
                                    .frame(width: 34, height: 34)
                                    .overlay(Circle().stroke(
                                        {
                                            switch option.logo {
                                            case .favicon:  return Color.black.opacity(0.06)
                                            case .sfSymbol: return Color.white.opacity(0.12)
                                            case .yaven:    return Color.white.opacity(0.35)
                                            }
                                        }(),
                                        lineWidth: { if case .yaven = option.logo { return 1.0 }; return 0.5 }()
                                    ))
                                StepLogoView(logo: option.logo, size: 18)
                            }
                            Text(option.toolName)
                                .font(.system(size: 9.5))
                                .foregroundColor(.white.opacity(0.50))
                                .lineLimit(1)
                        }
                        .frame(width: 50)
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button {
                // Run now — no-op in demo
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill").font(.system(size: 10))
                    Text("Run now").font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.70))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .pointerCursor()

            Button {
                var updated = flow
                updated.name   = editedName
                updated.status = editedStatus
                updated.steps  = editedSteps
                onSave(updated)
            } label: {
                Text("Save changes")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.18)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.20), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .pointerCursor()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Color(red: 0.06, green: 0.06, blue: 0.06)
                .overlay(Rectangle().frame(height: 0.5).foregroundColor(.white.opacity(0.08)), alignment: .top)
        )
    }
}

// MARK: - Detail step row

private struct DetailStepRow: View {
    let step: FlowStep
    let onDelete: () -> Void
    let onToggleNotify: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill({
                        switch step.logo {
                        case .favicon: return Color.white
                        case .sfSymbol, .yaven:
                            return step.notifyMe ? notifyStepColor.opacity(0.18) : Color.white.opacity(0.10)
                        }
                    }())
                    .frame(width: 34, height: 34)
                    .overlay(Circle().stroke(
                        {
                            if step.notifyMe { return notifyStepColor.opacity(0.55) }
                            switch step.logo {
                            case .favicon:  return Color.black.opacity(0.06)
                            case .sfSymbol: return Color.white.opacity(0.12)
                            case .yaven:    return Color.white.opacity(0.35)
                            }
                        }(),
                        lineWidth: {
                            if case .yaven = step.logo { return 1.0 }
                            return step.notifyMe ? 1.0 : 0.5
                        }()
                    ))
                StepLogoView(logo: step.logo, size: 20)
            }
            .frame(width: 34, height: 34)
            .animation(.easeInOut(duration: 0.18), value: step.notifyMe)

            VStack(alignment: .leading, spacing: 3) {
                Text(step.toolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                Text(step.description)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.40))
            }

            Spacer()

            HStack(spacing: 10) {
                Button(action: onToggleNotify) {
                    Image(systemName: step.notifyMe ? "bell.fill" : "bell")
                        .font(.system(size: 13))
                        .foregroundColor(step.notifyMe ? notifyStepColor : .white.opacity(0.25))
                        .animation(.easeInOut(duration: 0.18), value: step.notifyMe)
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .help("Notify me when this step runs")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.22))
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .help("Remove step")
            }
        }
        .padding(.vertical, 10)
    }
}
