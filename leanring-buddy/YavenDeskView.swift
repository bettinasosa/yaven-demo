//
//  YavenDeskView.swift
//  leanring-buddy
//
//  Approval inbox — "Desk". Everything Yaven needs the user to sign off on.
//  All data static / fake for the demo.
//

import SwiftUI

// MARK: - Models

private enum DeskSource: String {
    case meetingLoop = "Meeting Loop"
    case linkedIn    = "LinkedIn Outreach"
    case manual      = "Manual"

    var color: Color {
        switch self {
        case .meetingLoop: return Color.cyan.opacity(0.85)
        case .linkedIn:    return Color.orange.opacity(0.85)
        case .manual:      return Color(red: 0.60, green: 0.50, blue: 1.00)
        }
    }
}

private enum DeskUrgency {
    case overdue
    case dueHours(Int)
    case dueToday
    case dueDay(String)

    var label: String {
        switch self {
        case .overdue:         return "Overdue"
        case .dueHours(let h): return "Due in \(h) hours"
        case .dueToday:        return "Due today"
        case .dueDay(let d):   return "Due \(d)"
        }
    }

    var color: Color {
        switch self {
        case .overdue:   return .red.opacity(0.85)
        case .dueHours:  return .orange.opacity(0.80)
        case .dueToday:  return .orange.opacity(0.80)
        case .dueDay:    return Color.secondary
        }
    }
}

private enum DeskItemKind {
    case emailDraft, meetingNote, actionItems, linkedInBatch

    var iconURL: String {
        switch self {
        case .emailDraft:    return "https://www.google.com/s2/favicons?domain=gmail.com&sz=128"
        case .meetingNote:   return "https://www.google.com/s2/favicons?domain=granola.so&sz=128"
        case .actionItems:   return "https://www.google.com/s2/favicons?domain=linear.app&sz=128"
        case .linkedInBatch: return "https://www.google.com/s2/favicons?domain=linkedin.com&sz=128"
        }
    }
}

private enum ArtifactContent {
    case email(subject: String, body: String)
    case meetingNote(summary: String, actionItems: [String])
    case actionItems([String])
    case linkedInBatch([LinkedInDraft])
}

private struct LinkedInDraft: Identifiable {
    let id: String
    let recipientName: String
    var message: String
}

private struct DeskItem: Identifiable {
    let id: String
    let kind: DeskItemKind
    let title: String
    let source: DeskSource
    let urgency: DeskUrgency
    let isBatch: Bool
    let batchCount: Int?
    let artifact: ArtifactContent
}

// MARK: - Fake data

private let fakeDeskItems: [DeskItem] = [
    DeskItem(
        id: "d1", kind: .emailDraft,
        title: "Follow-up email to Jamie Chen",
        source: .meetingLoop, urgency: .overdue,
        isBatch: false, batchCount: nil,
        artifact: .email(
            subject: "Following up — next steps from today's sync",
            body: "Hi Jamie,\n\nThanks for the time today. Just wanted to confirm the key things we landed on — moving to 3-week sprints, feature C pushed to Q4, and you're leading the design handoff.\n\nI'll get the updated roadmap doc over to the team by Thursday. Let me know if anything looks off.\n\nCheers"
        )
    ),
    DeskItem(
        id: "d2", kind: .linkedInBatch,
        title: "LinkedIn outreach batch — 10 drafts",
        source: .linkedIn, urgency: .dueHours(2),
        isBatch: true, batchCount: 10,
        artifact: .linkedInBatch([
            LinkedInDraft(id: "li1", recipientName: "Sarah Park",
                message: "Hi Sarah, I came across your work on AI-assisted sales and wanted to connect — we're building something closely aligned at Yaven."),
            LinkedInDraft(id: "li2", recipientName: "Tom Whitfield",
                message: "Hi Tom, following up on your post about outbound automation. We'd love to show you how Yaven handles this end-to-end."),
            LinkedInDraft(id: "li3", recipientName: "Maya Osei",
                message: "Hi Maya, your article on product-led growth caught my eye — the parallels with what we're doing at Yaven are striking."),
            LinkedInDraft(id: "li4", recipientName: "James Howell",
                message: "Hi James, noticed you've been building in the CRM automation space. Would love to share what we've learned about AI-native workflows."),
            LinkedInDraft(id: "li5", recipientName: "Priya Kapoor",
                message: "Hi Priya, came across your profile through mutual connections in the AI tools space — think there's a lot of overlap with what we're working on."),
            LinkedInDraft(id: "li6", recipientName: "Alex Novak",
                message: "Hi Alex, your post on founder productivity last week resonated — we built Yaven exactly for that problem."),
            LinkedInDraft(id: "li7", recipientName: "Lily Chen",
                message: "Hi Lily, I see you're scaling the RevOps function at Stripe — Yaven was built for teams moving at exactly this speed."),
            LinkedInDraft(id: "li8", recipientName: "Marcus Webb",
                message: "Hi Marcus, saw your comment on the AI tools thread from last week. Would love to show you how Yaven approaches the automation layer."),
            LinkedInDraft(id: "li9", recipientName: "Fatima Hassan",
                message: "Hi Fatima, your post on AI-assisted workflows caught my attention — we're solving the same problem from the OS layer up."),
            LinkedInDraft(id: "li10", recipientName: "Dan Reeve",
                message: "Hi Dan, noticed you're building in the enterprise sales space. Yaven is doing something adjacent — think you'd find the approach interesting."),
        ])
    ),
    DeskItem(
        id: "d3", kind: .meetingNote,
        title: "Product sync — meeting notes",
        source: .meetingLoop, urgency: .dueToday,
        isBatch: false, batchCount: nil,
        artifact: .meetingNote(
            summary: "Meeting: Product Sync\nDate: Tuesday 20 May · 9:34am\nAttendees: Nick, Jamie Chen, Priya Mehta\n\nKey decisions:\n• Moving to 3-week sprint cycles from next week\n• Feature C deprioritised and pushed to Q4\n• Jamie leading design handoff for the new onboarding flow",
            actionItems: [
                "Nick → Send updated roadmap doc to the team by Thursday",
                "Jamie → Kick off design handoff, share first draft by EOW",
                "Priya → Update Linear tickets to reflect new sprint structure"
            ]
        )
    ),
    DeskItem(
        id: "d4", kind: .actionItems,
        title: "Action items — Design review",
        source: .meetingLoop, urgency: .dueDay("Thursday"),
        isBatch: false, batchCount: nil,
        artifact: .actionItems([
            "Priya → Share updated Figma screens with the team",
            "Nick → Review and leave comments by Wednesday EOD"
        ])
    ),
]

// MARK: - Main view

struct YavenDeskView: View {
    let onClose: () -> Void
    let onPreferredHeightChange: (CGFloat) -> Void

    @State private var approvedIDs: Set<String> = []
    @State private var viewingArtifact: DeskItem? = nil

    private enum Layout {
        static let listHeight: CGFloat = 420
        static let reviewHeight: CGFloat = 680
    }

    private var visibleItems: [DeskItem] {
        fakeDeskItems.filter { !approvedIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            deskHeader

            ZStack {
                mainList

                if let item = viewingArtifact {
                    ArtifactView(
                        item: item,
                        onApprove: { approve(item) }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(1)
                }
            }
        }
        .animation(.easeInOut(duration: 0.22), value: viewingArtifact?.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { reportPreferredHeight() }
        .onChange(of: viewingArtifact?.id) { _, _ in
            reportPreferredHeight()
        }
    }

    private var deskHeader: some View {
        HStack(spacing: 0) {
            Button(action: handleBack) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Desk")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.60))
                .contentShape(Rectangle())
            }
            .buttonStyle(DeskHeaderButtonStyle())
            .pointerCursor()
            .help(viewingArtifact == nil ? "Back to home" : "Back to Desk")

            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 10)
    }

    private var mainList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !visibleItems.isEmpty {
                Text("\(visibleItems.count) \(visibleItems.count == 1 ? "item" : "items")")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 32)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 7) {
                    if visibleItems.isEmpty {
                        emptyState
                    } else {
                        ForEach(visibleItems) { item in
                            DeskCardView(
                                item: item,
                                onView: {
                                    withAnimation(.easeInOut(duration: 0.22)) { viewingArtifact = item }
                                },
                                onApprove: { approve(item) }
                            )
                            .transition(.asymmetric(
                                insertion: .identity,
                                removal: .opacity.combined(with: .offset(x: -12))
                            ))
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
                .animation(.easeInOut(duration: 0.20), value: approvedIDs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 34, weight: .ultraLight))
                .foregroundColor(.white.opacity(0.18))
            Text("Your desk is clear.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.28))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func approve(_ item: DeskItem) {
        withAnimation(.easeInOut(duration: 0.20)) {
            approvedIDs.insert(item.id)
            if viewingArtifact?.id == item.id {
                viewingArtifact = nil
            }
        }
    }

    private func closeReviewIfNeeded() {
        guard viewingArtifact != nil else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            viewingArtifact = nil
        }
    }

    private func handleBack() {
        if viewingArtifact != nil {
            closeReviewIfNeeded()
        } else {
            onClose()
        }
    }

    private func reportPreferredHeight() {
        let isReviewing = viewingArtifact != nil
        onPreferredHeightChange(isReviewing ? Layout.reviewHeight : Layout.listHeight)
    }
}

private struct DeskHeaderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

private struct DeskActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.84 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.74), value: configuration.isPressed)
    }
}

// MARK: - Desk card

private struct DeskCardView: View {
    let item: DeskItem
    let onView: () -> Void
    let onApprove: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(item.source.color.opacity(0.14))
                    .frame(width: 34, height: 34)
                AsyncSVGImage(urlString: item.kind.iconURL, size: 20)
            }

            // Labels
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.88))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(item.source.rawValue)
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                    Text("·")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(item.urgency.label)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(item.urgency.color)
                }
            }

            Spacer(minLength: 4)

            // Actions
            HStack(spacing: 5) {
                Button(action: onView) {
                    Text("View")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.50))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.07)))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 0.5))
                }
                .buttonStyle(DeskActionButtonStyle())
                .pointerCursor()

                Button(action: onApprove) {
                    Text(item.isBatch ? "Approve all" : "Approve")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.90))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.14)))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 0.5))
                }
                .buttonStyle(DeskActionButtonStyle())
                .pointerCursor()
            }
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
    }
}

// MARK: - Artefact view

private struct ArtifactView: View {
    let item: DeskItem
    let onApprove: () -> Void

    @State private var hasEdited = false
    @State private var showLearnToast = false

    @State private var emailSubject = ""
    @State private var emailBody = ""
    @State private var noteText = ""
    @State private var actionItemTexts: [String] = []
    @State private var linkedInDrafts: [LinkedInDraft] = []

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                artifactContent
            }

            bottomBar

            if showLearnToast {
                learnToast
                    .padding(.bottom, 68)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .onAppear { loadContent() }
    }

    @ViewBuilder
    private var artifactContent: some View {
        if case .email = item.artifact {
            emailLayoutExpanded
        } else {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.90))

                    switch item.artifact {
                    case .meetingNote:   meetingNoteFields
                    case .actionItems:   actionItemsFields
                    case .linkedInBatch: linkedInBatchFields
                    default:             EmptyView()
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 12)
                .padding(.bottom, 80)
            }
        }
    }

    // MARK: Email — expands to fill available height

    private var emailLayoutExpanded: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.90))
                .padding(.bottom, 4)

            fieldLabel("Subject")
            TextField("Subject", text: $emailSubject)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.85))
                .padding(10)
                .background(fieldBackground)
                .overlay(fieldBorder)
                .onChange(of: emailSubject) { _, _ in hasEdited = true }

            fieldLabel("Body")
            TextEditor(text: $emailBody)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.82))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(fieldBackground)
                .overlay(fieldBorder)
                .frame(maxHeight: .infinity)
                .onChange(of: emailBody) { _, _ in hasEdited = true }
        }
        .padding(.horizontal, 32)
        .padding(.top, 12)
        .padding(.bottom, 68) // clear the approve bar
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Meeting note

    private var meetingNoteFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("Summary")
            TextEditor(text: $noteText)
                .font(.system(size: 12.5))
                .foregroundColor(.white.opacity(0.80))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 100)
                .padding(8)
                .background(fieldBackground)
                .overlay(fieldBorder)
                .onChange(of: noteText) { _, _ in hasEdited = true }

            if !actionItemTexts.isEmpty {
                fieldLabel("Action items")
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(actionItemTexts.indices, id: \.self) { i in
                        HStack(alignment: .top, spacing: 7) {
                            Circle()
                                .fill(Color.cyan.opacity(0.60))
                                .frame(width: 5, height: 5)
                                .padding(.top, 5)
                            Text(actionItemTexts[i])
                                .font(.system(size: 12.5))
                                .foregroundColor(.white.opacity(0.78))
                                .lineSpacing(2)
                        }
                    }
                }
                .padding(10)
                .background(fieldBackground)
                .overlay(fieldBorder)
            }
        }
    }

    // MARK: Action items

    private var actionItemsFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Items")
            VStack(alignment: .leading, spacing: 6) {
                ForEach(actionItemTexts.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "checkmark.square")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.30))
                        Text(actionItemTexts[i])
                            .font(.system(size: 12.5))
                            .foregroundColor(.white.opacity(0.82))
                    }
                }
            }
            .padding(10)
            .background(fieldBackground)
            .overlay(fieldBorder)
        }
    }

    // MARK: LinkedIn batch

    private var linkedInBatchFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("\(linkedInDrafts.count) drafts")
            VStack(spacing: 8) {
                ForEach($linkedInDrafts) { $draft in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(draft.recipientName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.55))
                        TextEditor(text: $draft.message)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.82))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 52)
                            .onChange(of: draft.message) { _, _ in hasEdited = true }
                    }
                    .padding(10)
                    .background(fieldBackground)
                    .overlay(fieldBorder)
                }
            }
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.10)
            Button(action: handleApprove) {
                Text(item.isBatch ? "Approve all" : "Approve")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.15))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                    )
            }
            .buttonStyle(DeskActionButtonStyle())
            .pointerCursor()
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
        }
        .background(Color.black.opacity(0.85))
    }

    private var learnToast: some View {
        Text("Got it — I'll remember this for next time.")
            .font(.system(size: 11.5))
            .foregroundColor(.white.opacity(0.78))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.11)))
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
    }

    // MARK: Helpers

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.06))
    }

    private var fieldBorder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 0.5)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundColor(.secondary)
            .tracking(0.5)
    }

    private func loadContent() {
        switch item.artifact {
        case .email(let subject, let body):
            emailSubject = subject
            emailBody    = body
        case .meetingNote(let summary, let items):
            noteText        = summary
            actionItemTexts = items
        case .actionItems(let items):
            actionItemTexts = items
        case .linkedInBatch(let drafts):
            linkedInDrafts = drafts
        }
    }

    private func handleApprove() {
        if hasEdited {
            withAnimation(.easeOut(duration: 0.18)) { showLearnToast = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) {
                withAnimation(.easeIn(duration: 0.18)) { showLearnToast = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { onApprove() }
            }
        } else {
            onApprove()
        }
    }
}
