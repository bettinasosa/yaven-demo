//
//  YavenLogView.swift
//  leanring-buddy
//
//  Vertical git-log timeline of everything Yaven has produced.
//  All data is static / fake for the demo.
//

import SwiftUI

// MARK: - Models

private enum LogSource: String {
    case meetingLoop = "Meeting Loop"
    case linkedIn    = "LinkedIn Outreach"
    case manual      = "Manual"

    var color: Color {
        switch self {
        case .meetingLoop: return Color.cyan.opacity(0.80)
        case .linkedIn:    return Color.orange.opacity(0.80)
        case .manual:      return Color(red: 0.60, green: 0.50, blue: 1.00)
        }
    }
}

private enum LogArtifactKind {
    case meetingNote, actionItems, emailDraft, linkedInBatch, research

    private var toolDomain: String {
        switch self {
        case .meetingNote:   return "granola.so"
        case .actionItems:   return "linear.app"
        case .emailDraft:    return "gmail.com"
        case .linkedInBatch: return "linkedin.com"
        case .research:      return "notion.so"
        }
    }

    var iconURL: String {
        "https://www.google.com/s2/favicons?domain=\(toolDomain)&sz=128"
    }

    var openActionLabel: String {
        switch self {
        case .meetingNote:   return "Open in Granola"
        case .actionItems:   return "Open in Linear"
        case .emailDraft:    return "Open in Gmail"
        case .linkedInBatch: return "Open in LinkedIn"
        case .research:      return "Open in Notion"
        }
    }
}

private struct LogCard: Identifiable {
    let id: String
    let kind: LogArtifactKind
    let title: String
    let dateTime: String
    let source: LogSource
    let connectedItems: String?
}

private struct LogNode: Identifiable {
    let id: String
    let timeLabel: String
    let source: LogSource
    let cards: [LogCard]
}

// MARK: - Fake data

private let fakeNodes: [LogNode] = [
    LogNode(id: "n1", timeLabel: "Today  9:34am", source: .meetingLoop, cards: [
        LogCard(id: "n1c1", kind: .meetingNote, title: "Product sync — meeting notes",
                dateTime: "Tuesday 20 May · 9:34am", source: .meetingLoop,
                connectedItems: "3 action items · 1 follow-up email"),
        LogCard(id: "n1c2", kind: .actionItems, title: "Action items (3)",
                dateTime: "Tuesday 20 May · 9:34am", source: .meetingLoop,
                connectedItems: nil),
        LogCard(id: "n1c3", kind: .emailDraft,  title: "Follow-up to Jamie Chen",
                dateTime: "Tuesday 20 May · 9:34am", source: .meetingLoop,
                connectedItems: nil),
    ]),
    LogNode(id: "n2", timeLabel: "Today  8:00am", source: .linkedIn, cards: [
        LogCard(id: "n2c1", kind: .linkedInBatch, title: "Outreach batch — 10 drafts",
                dateTime: "Tuesday 20 May · 8:00am", source: .linkedIn,
                connectedItems: "10 draft messages"),
    ]),
    LogNode(id: "n3", timeLabel: "Yesterday  3:12pm", source: .meetingLoop, cards: [
        LogCard(id: "n3c1", kind: .meetingNote, title: "Design review — meeting notes",
                dateTime: "Monday 19 May · 3:12pm", source: .meetingLoop,
                connectedItems: "2 action items · 1 follow-up email"),
        LogCard(id: "n3c2", kind: .actionItems, title: "Action items (2)",
                dateTime: "Monday 19 May · 3:12pm", source: .meetingLoop,
                connectedItems: nil),
        LogCard(id: "n3c3", kind: .emailDraft,  title: "Follow-up to Priya Mehta",
                dateTime: "Monday 19 May · 3:12pm", source: .meetingLoop,
                connectedItems: nil),
    ]),
    LogNode(id: "n4", timeLabel: "Yesterday  8:00am", source: .linkedIn, cards: [
        LogCard(id: "n4c1", kind: .linkedInBatch, title: "Outreach batch — 8 drafts",
                dateTime: "Monday 19 May · 8:00am", source: .linkedIn,
                connectedItems: "8 draft messages"),
    ]),
    LogNode(id: "n5", timeLabel: "Mon 19 May  2:45pm", source: .meetingLoop, cards: [
        LogCard(id: "n5c1", kind: .meetingNote, title: "Investor update prep",
                dateTime: "Monday 19 May · 2:45pm", source: .meetingLoop,
                connectedItems: "1 action item"),
        LogCard(id: "n5c2", kind: .actionItems, title: "Action items (1)",
                dateTime: "Monday 19 May · 2:45pm", source: .meetingLoop,
                connectedItems: nil),
    ]),
    LogNode(id: "n6", timeLabel: "Mon 19 May  8:00am", source: .linkedIn, cards: [
        LogCard(id: "n6c1", kind: .linkedInBatch, title: "Outreach batch — 10 drafts",
                dateTime: "Monday 19 May · 8:00am", source: .linkedIn,
                connectedItems: "10 draft messages"),
    ]),
    LogNode(id: "n7", timeLabel: "Mon 19 May  11:20am", source: .manual, cards: [
        LogCard(id: "n7c1", kind: .research,
                title: "Research summary — Notion AI vs Yaven positioning",
                dateTime: "Monday 19 May · 11:20am", source: .manual,
                connectedItems: nil),
    ]),
]

// MARK: - Root view

struct YavenLogView: View {
    @State private var searchText = ""
    @State private var expandedCardID: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, 32)
                .padding(.top, 10)
                .padding(.bottom, 8)

            Divider().opacity(0.08)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(fakeNodes.enumerated()), id: \.element.id) { index, node in
                        LogNodeRow(
                            node: node,
                            nodeIndex: index,
                            isLast: index == fakeNodes.count - 1,
                            expandedCardID: $expandedCardID,
                            searchText: searchText
                        )
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.28))
            TextField("Search log…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.white)
                .tint(.white)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.28))
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 0.5))
    }
}

// MARK: - Node row

private struct LogNodeRow: View {
    let node: LogNode
    let nodeIndex: Int
    let isLast: Bool
    @Binding var expandedCardID: String?
    let searchText: String

    @State private var appeared = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            trunkColumn
            contentColumn
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 6)
        .onAppear {
            withAnimation(.easeOut(duration: 0.26).delay(Double(nodeIndex) * 0.035)) {
                appeared = true
            }
        }
    }

    // Continuous vertical trunk with node dot
    private var trunkColumn: some View {
        ZStack(alignment: .top) {
            // Trunk line — full height for all nodes except last (which only gets a stub)
            Rectangle()
                .fill(Color.white.opacity(0.13))
                .frame(width: 1.5)
                .frame(maxHeight: isLast ? 10 : .infinity)

            // Node circle
            Circle()
                .fill(Color.white.opacity(0.28))
                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                .frame(width: 9, height: 9)
                .padding(.top, 4)
        }
        .frame(width: 22)
    }

    private var contentColumn: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Time + source label
            HStack(spacing: 5) {
                Text(node.timeLabel)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
                Text("·")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.20))
                Text(node.source.rawValue)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(node.source.color)
            }
            .padding(.top, 2)

            // Card stack with colored branch line
            VStack(alignment: .leading, spacing: 4) {
                ForEach(node.cards) { card in
                    LogCardView(
                        card: card,
                        color: node.source.color,
                        isExpanded: expandedCardID == card.id,
                        searchText: searchText
                    ) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            expandedCardID = expandedCardID == card.id ? nil : card.id
                        }
                    }
                }
            }
            .padding(.leading, 9)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(node.source.color.opacity(0.40))
                    .frame(width: 1.5)
                    .padding(.vertical, 3)
            }
        }
        .padding(.leading, 10)
        .padding(.bottom, 18)
    }
}

// MARK: - Card view

private struct LogCardView: View {
    let card: LogCard
    let color: Color
    let isExpanded: Bool
    let searchText: String
    let onTap: () -> Void

    private var matchesSearch: Bool {
        searchText.isEmpty || card.title.localizedCaseInsensitiveContains(searchText)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                collapsedRow
                if isExpanded {
                    Divider()
                        .background(color.opacity(0.20))
                        .padding(.horizontal, 10)
                    expandedDetail
                        .padding(10)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isExpanded ? color.opacity(0.10) : Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isExpanded ? color.opacity(0.28) : Color.white.opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .opacity(matchesSearch ? 1.0 : 0.18)
        .animation(.easeOut(duration: 0.12), value: matchesSearch)
    }

    private var collapsedRow: some View {
        HStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 20, height: 20)
                AsyncSVGImage(urlString: card.kind.iconURL, size: 13)
            }
            Text(card.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.82))
                .lineLimit(1)
            Spacer()
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.22))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private var expandedDetail: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 0) {
                Text(card.dateTime)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Text(card.source.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(color.opacity(0.85))
            }

            if let connected = card.connectedItems {
                HStack(spacing: 5) {
                    Circle()
                        .fill(color)
                        .frame(width: 4, height: 4)
                    Text(connected)
                        .font(.system(size: 11))
                        .foregroundColor(color.opacity(0.90))
                }
            }

            HStack(spacing: 6) {
                quickAction("Share")
                quickAction("Copy")
                quickAction(card.kind.openActionLabel)
            }
            .padding(.top, 2)
        }
    }

    private func quickAction(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.white.opacity(0.45))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
    }
}
