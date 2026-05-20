//
//  YavenLogView.swift
//  leanring-buddy
//
//  Activity Log with 4 selectable layout options (A/B/C/D).
//  All data is static / fake for the demo.
//

import SwiftUI

// MARK: - Models

private enum LogSource: String {
    case meetingLoop = "Meeting Loop"
    case linkedIn    = "LinkedIn Outreach"
    case manual      = "Manual"
}

private enum LogArtifactKind {
    case meetingNote, actionItems, emailDraft, linkedInBatch, research, hubSpotNote

    var statusLabel: String {
        switch self {
        case .meetingNote:   return "Saved to memory"
        case .actionItems:   return "Created in Notion"
        case .emailDraft:    return "Drafted in Gmail"
        case .linkedInBatch: return "Drafted in Notion"
        case .research:      return "Saved to Notion"
        case .hubSpotNote:   return "Applied to HubSpot"
        }
    }
}

private struct LogTool: Identifiable, Equatable {
    let name: String
    let domain: String?
    let systemImage: String?
    /// When set, loads from Composio logo CDN instead of Google favicon API.
    let composioKey: String?

    init(name: String, domain: String? = nil, systemImage: String? = nil, composioKey: String? = nil) {
        self.name = name
        self.domain = domain
        self.systemImage = systemImage
        self.composioKey = composioKey
    }

    var id: String { composioKey ?? domain ?? systemImage ?? name }

    var iconURL: String? {
        if let key = composioKey {
            return "https://logos.composio.dev/api/\(key)"
        }
        guard let domain else { return nil }
        return "https://www.google.com/s2/favicons?domain=\(domain)&sz=128"
    }
}

private struct LogOutputItem: Identifiable {
    let id: String
    let title: String
    let leadingTimeLabel: String?
    let statusLabel: String?
    let destination: LogTool?
    let approvalTooltip: String?
}

private struct LogCard: Identifiable {
    let id: String
    let kind: LogArtifactKind
    let title: String
}

private struct LogNode: Identifiable {
    let id: String
    let timeLabel: String
    let source: LogSource
    let cards: [LogCard]
}

private struct LogWorkflow: Identifiable {
    let node: LogNode

    var id: String { node.id }
    var dayLabel: String {
        let rawDay = node.timeLabel.components(separatedBy: "  ").first ?? node.timeLabel
        return rawDay.hasPrefix("Mon") ? "Monday" : rawDay
    }

    var hourLabel: String {
        let parts = node.timeLabel.components(separatedBy: "  ")
        guard parts.count > 1, let hour = parts.last else { return node.timeLabel }
        return hour
    }

    var hourSortValue: Int {
        let normalizedHour = hourLabel.lowercased()
        let isPM = normalizedHour.contains("pm")
        let isAM = normalizedHour.contains("am")
        let timeOnly = normalizedHour
            .replacingOccurrences(of: "am", with: "")
            .replacingOccurrences(of: "pm", with: "")
        let timeParts = timeOnly.split(separator: ":").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard let rawHour = timeParts.first else { return 0 }
        var hour = rawHour
        if isPM && hour < 12 { hour += 12 }
        if isAM && hour == 12 { hour = 0 }
        return hour * 60 + (timeParts.dropFirst().first ?? 0)
    }

    var compactTitle: String {
        guard let firstTitle = node.cards.first?.title else { return node.source.rawValue }
        switch node.source {
        case .meetingLoop:
            return firstTitle.replacingOccurrences(of: " — meeting notes", with: "")
        case .linkedIn, .manual:
            return firstTitle
        }
    }

    var title: String {
        switch node.source {
        case .meetingLoop:
            return "\(compactTitle) — \(node.source.rawValue)"
        case .linkedIn, .manual:
            return compactTitle
        }
    }

    var workflowType: String { node.source.rawValue }
    var originTool: LogTool {
        switch node.source {
        case .meetingLoop: return .granola
        case .linkedIn:    return .linkedIn
        case .manual:      return .notion
        }
    }

    var sourceTools: [LogTool] {
        switch node.source {
        case .meetingLoop:
            return [.granola, .calendar, .gmail, .hubSpot]
        case .linkedIn:
            return [.linkedIn, .gmail]
        case .manual:
            return [.notion]
        }
    }

    var outputs: [LogOutputItem] {
        if node.source == .linkedIn, let batchCard = node.cards.first {
            return [
                LogOutputItem(id: batchCard.id, title: outputTitle(for: batchCard),
                              leadingTimeLabel: nil, statusLabel: batchCard.kind.statusLabel,
                              destination: .notion, approvalTooltip: nil),
                LogOutputItem(id: "\(node.id)-approved", title: "Approved",
                              leadingTimeLabel: approvalTime, statusLabel: nil,
                              destination: nil, approvalTooltip: "Approved by you at \(approvalTime)"),
                LogOutputItem(id: "\(node.id)-linkedin-sent", title: "Sent to LinkedIn",
                              leadingTimeLabel: nil, statusLabel: "View on LinkedIn",
                              destination: .linkedIn, approvalTooltip: nil),
            ]
        }
        var items = node.cards.map { card in
            LogOutputItem(id: card.id, title: outputTitle(for: card),
                          leadingTimeLabel: nil, statusLabel: card.kind.statusLabel,
                          destination: card.kind.destinationTool,
                          approvalTooltip: card.kind == .emailDraft ? "Approved by you at \(approvalTime)" : nil)
        }
        if node.source == .meetingLoop {
            items.append(LogOutputItem(
                id: "\(node.id)-hubspot-note", title: "HubSpot call note",
                leadingTimeLabel: nil, statusLabel: LogArtifactKind.hubSpotNote.statusLabel,
                destination: .hubSpot, approvalTooltip: "Approved by you at \(approvalTime)"
            ))
        }
        return items
    }

    private func outputTitle(for card: LogCard) -> String {
        switch card.kind {
        case .meetingNote:   return "Meeting notes"
        default:             return card.title
        }
    }

    private var approvalTime: String {
        switch node.id {
        case "n1": return "9:48am"
        case "n2": return "8:04am"
        case "n3": return "3:16pm"
        case "n4": return "8:05am"
        case "n5": return "2:49pm"
        case "n6": return "8:06am"
        default:   return "11:24am"
        }
    }

    func matchesSearch(_ searchText: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let fields = [compactTitle, title, workflowType, node.timeLabel]
            + sourceTools.map(\.name)
            + outputs.flatMap { [$0.title, $0.statusLabel ?? "", $0.destination?.name ?? ""] }
        return fields.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

private extension LogArtifactKind {
    var destinationTool: LogTool {
        switch self {
        case .meetingNote:   return .memory
        case .actionItems:   return .notion
        case .emailDraft:    return .gmail
        case .linkedInBatch: return .notion
        case .research:      return .notion
        case .hubSpotNote:   return .hubSpot
        }
    }
}

private extension LogTool {
    static let calendar = LogTool(name: "Calendar",  domain: "calendar.google.com")
    // Gmail: Composio CDN gives the red envelope icon, same source used in the main dashboard
    static let gmail    = LogTool(name: "Gmail",     composioKey: "gmail")
    static let granola  = LogTool(name: "Granola",   domain: "granola.so")
    static let hubSpot  = LogTool(name: "HubSpot",   domain: "hubspot.com")
    static let linkedIn = LogTool(name: "LinkedIn",  domain: "linkedin.com")
    static let memory   = LogTool(name: "Memory",    systemImage: "archivebox.fill")
    static let notion   = LogTool(name: "Notion",    domain: "notion.so")
}

// MARK: - Fake data

private let fakeNodes: [LogNode] = [
    LogNode(id: "n1", timeLabel: "Today  9:34am", source: .meetingLoop, cards: [
        LogCard(id: "n1c1", kind: .meetingNote,  title: "Product sync — meeting notes"),
        LogCard(id: "n1c2", kind: .actionItems,  title: "Action items (3)"),
        LogCard(id: "n1c3", kind: .emailDraft,   title: "Follow-up to Jamie Chen"),
    ]),
    LogNode(id: "n2", timeLabel: "Today  8:00am", source: .linkedIn, cards: [
        LogCard(id: "n2c1", kind: .linkedInBatch, title: "Outreach batch — 10 drafts"),
    ]),
    LogNode(id: "n3", timeLabel: "Yesterday  3:12pm", source: .meetingLoop, cards: [
        LogCard(id: "n3c1", kind: .meetingNote,  title: "Design review — meeting notes"),
        LogCard(id: "n3c2", kind: .actionItems,  title: "Action items (2)"),
        LogCard(id: "n3c3", kind: .emailDraft,   title: "Follow-up to Priya Mehta"),
    ]),
    LogNode(id: "n4", timeLabel: "Yesterday  8:00am", source: .linkedIn, cards: [
        LogCard(id: "n4c1", kind: .linkedInBatch, title: "Outreach batch — 8 drafts"),
    ]),
    LogNode(id: "n5", timeLabel: "Mon 19 May  2:45pm", source: .meetingLoop, cards: [
        LogCard(id: "n5c1", kind: .meetingNote,  title: "Investor update prep"),
        LogCard(id: "n5c2", kind: .actionItems,  title: "Action items (1)"),
    ]),
    LogNode(id: "n6", timeLabel: "Mon 19 May  8:00am", source: .linkedIn, cards: [
        LogCard(id: "n6c1", kind: .linkedInBatch, title: "Outreach batch — 10 drafts"),
    ]),
    LogNode(id: "n7", timeLabel: "Mon 19 May  11:20am", source: .manual, cards: [
        LogCard(id: "n7c1", kind: .research, title: "Research summary — Notion AI vs Yaven"),
    ]),
]

private let fakeWorkflows = fakeNodes.map { LogWorkflow(node: $0) }

private struct LogSection: Identifiable {
    let dayLabel: String
    var workflows: [LogWorkflow]
    var id: String { dayLabel }
}

private let fakeLogSections: [LogSection] = {
    var sections: [LogSection] = []
    for wf in fakeWorkflows {
        if let i = sections.firstIndex(where: { $0.dayLabel == wf.dayLabel }) {
            sections[i].workflows.append(wf)
        } else {
            sections.append(LogSection(dayLabel: wf.dayLabel, workflows: [wf]))
        }
    }
    for i in sections.indices {
        sections[i].workflows.sort { $0.hourSortValue > $1.hourSortValue }
    }
    return sections
}()

// MARK: - Layout options

private enum LogLayout: String, CaseIterable, Identifiable {
    case timeline = "A"
    case table    = "B"
    case cards    = "C"
    case feed     = "D"

    var id: String { rawValue }
    var description: String {
        switch self {
        case .timeline: return "Timeline"
        case .table:    return "Table"
        case .cards:    return "Cards"
        case .feed:     return "Feed"
        }
    }
}

// MARK: - Source accent colours

private enum LogSourceStyle {
    static func accentColor(_ source: LogSource) -> Color {
        switch source {
        case .meetingLoop: return Color(red: 0.24, green: 0.88, blue: 0.62)
        case .linkedIn:    return Color(red: 0.47, green: 0.72, blue: 1.00)
        case .manual:      return Color.white.opacity(0.50)
        }
    }

    static func pillBackground(_ source: LogSource) -> Color {
        switch source {
        case .meetingLoop: return Color(red: 0.20, green: 0.88, blue: 0.60).opacity(0.13)
        case .linkedIn:    return Color(red: 0.25, green: 0.52, blue: 0.96).opacity(0.15)
        case .manual:      return Color.white.opacity(0.08)
        }
    }
}

// MARK: - Root view

struct YavenLogView: View {
    private let onOpenFlow: (String) -> Void

    @State private var searchText = ""
    @State private var layout: LogLayout = .timeline
    @State private var expandedIDs: Set<String> = Set(fakeWorkflows.prefix(1).map(\.id))

    init(onOpenFlow: @escaping (String) -> Void = { _ in }) {
        self.onOpenFlow = onOpenFlow
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search + layout picker
            VStack(spacing: 8) {
                searchBar
                layoutPicker
            }
            .padding(.horizontal, 28)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider().opacity(0.08)

            ScrollView(showsIndicators: false) {
                layoutContent
                    .padding(.horizontal, 28)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Search bar

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
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(Color.white.opacity(0.09), lineWidth: 0.5))
    }

    // MARK: Layout picker  A / B / C / D

    private var layoutPicker: some View {
        HStack(spacing: 4) {
            ForEach(LogLayout.allCases) { option in
                let isSelected = layout == option
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.74)) {
                        layout = option
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(option.rawValue)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                        if isSelected {
                            Text(option.description)
                                .font(.system(size: 10, weight: .semibold))
                                .fixedSize()
                                .transition(.opacity.combined(with: .scale(scale: 0.75, anchor: .leading)))
                        }
                    }
                    .foregroundColor(isSelected ? .white.opacity(0.92) : .white.opacity(0.30))
                    .padding(.horizontal, isSelected ? 9 : 7)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(isSelected ? Color.white.opacity(0.13) : Color.clear)
                    )
                    .overlay(
                        Capsule()
                            .stroke(isSelected ? Color.white.opacity(0.22) : Color.clear, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .animation(.spring(response: 0.28, dampingFraction: 0.74), value: isSelected)
            }
            Spacer()
            Text("\(totalCount) runs")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.22))
        }
    }

    private var totalCount: Int { fakeWorkflows.count }

    // MARK: Layout dispatcher

    @ViewBuilder
    private var layoutContent: some View {
        switch layout {
        case .timeline: layoutA
        case .table:    layoutB
        case .cards:    layoutC
        case .feed:     layoutD
        }
    }

    // ──────────────────────────────────────────────
    // LAYOUT A — Timeline trunk
    // Dates: inline day-separator rules between groups
    // Micro: rotating chevron, icon scale on hover,
    //        output items stagger-fade in on expand
    // ──────────────────────────────────────────────

    private var layoutA: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(fakeLogSections.enumerated()), id: \.element.id) { si, section in
                if si > 0 {
                    // Day-change separator — part of the trunk
                    HStack(spacing: 0) {
                        Rectangle().fill(Color.white.opacity(0.10))
                            .frame(width: 1.5, height: 16)
                            .frame(width: 22, alignment: .center)
                        Rectangle().fill(Color.white.opacity(0.09)).frame(height: 0.5)
                            .padding(.leading, 10)
                        Text(section.dayLabel.uppercased())
                            .font(.system(size: 9, weight: .bold)).tracking(0.8)
                            .foregroundColor(.white.opacity(0.28))
                            .fixedSize()
                            .padding(.horizontal, 8)
                        Rectangle().fill(Color.white.opacity(0.09)).frame(height: 0.5)
                    }
                    .padding(.vertical, 4)
                } else {
                    Text(section.dayLabel.uppercased())
                        .font(.system(size: 9, weight: .bold)).tracking(0.8)
                        .foregroundColor(.white.opacity(0.28))
                        .padding(.leading, 22 + 10)
                        .padding(.bottom, 6)
                }

                ForEach(Array(section.workflows.enumerated()), id: \.element.id) { wi, wf in
                    let isLast = si == fakeLogSections.count - 1 && wi == section.workflows.count - 1
                    LogRowA(
                        workflow: wf, isLast: isLast,
                        isExpanded: expandedIDs.contains(wf.id),
                        matchesSearch: wf.matchesSearch(searchText),
                        onToggle: { toggleExpand(wf.id) }
                    )
                    .opacity(wf.matchesSearch(searchText) ? 1 : 0.18)
                }
            }
        }
    }

    // ──────────────────────────────────────────────
    // LAYOUT B — Two-column table
    // Dates: sticky left column per day group
    // Times: shown large in left column under date
    // Micro: row highlight on hover, no backgrounds
    //        collapsed — expand replaces row in place
    // ──────────────────────────────────────────────

    private var layoutB: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(fakeLogSections) { section in
                // Date header row
                HStack(spacing: 0) {
                    Text(section.dayLabel)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.28))
                        .frame(width: 72, alignment: .leading)
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
                }
                .padding(.bottom, 4)
                .padding(.top, 10)

                ForEach(section.workflows) { wf in
                    LogRowB(
                        workflow: wf,
                        isExpanded: expandedIDs.contains(wf.id),
                        matchesSearch: wf.matchesSearch(searchText),
                        onToggle: { toggleExpand(wf.id) }
                    )
                    .opacity(wf.matchesSearch(searchText) ? 1 : 0.18)
                }
            }
        }
    }

    // ──────────────────────────────────────────────
    // LAYOUT C — Rich cards, no trunk
    // Dates: floating chip in card top-right corner
    // Times: large, inside the card header
    // Micro: card lifts on hover (shadow + slight y),
    //        source icons visible collapsed,
    //        expand slides content from within card
    // ──────────────────────────────────────────────

    private var layoutC: some View {
        VStack(spacing: 8) {
            ForEach(fakeWorkflows) { wf in
                LogRowC(
                    workflow: wf,
                    isExpanded: expandedIDs.contains(wf.id),
                    matchesSearch: wf.matchesSearch(searchText),
                    onToggle: { toggleExpand(wf.id) }
                )
                .opacity(wf.matchesSearch(searchText) ? 1 : 0.18)
            }
        }
    }

    // ──────────────────────────────────────────────
    // LAYOUT D — Activity feed, one pill per run
    // Dates: floating sticky chip above each day group
    // Times: inline at start of each pill
    // Micro: pill expands to full detail inline on tap,
    //        unselected pills dim slightly,
    //        very compact — more runs visible at once
    // ──────────────────────────────────────────────

    private var layoutD: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(fakeLogSections.enumerated()), id: \.element.id) { si, section in
                // Floating day badge
                HStack {
                    Text(section.dayLabel)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.36))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.07)))
                        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.5))
                    Spacer()
                }
                .padding(.top, si == 0 ? 0 : 12)
                .padding(.bottom, 6)

                VStack(spacing: 3) {
                    ForEach(section.workflows) { wf in
                        LogRowD(
                            workflow: wf,
                            isExpanded: expandedIDs.contains(wf.id),
                            anyExpanded: !expandedIDs.isEmpty,
                            matchesSearch: wf.matchesSearch(searchText),
                            onToggle: { toggleExpand(wf.id) }
                        )
                        .opacity(wf.matchesSearch(searchText) ? 1 : 0.18)
                    }
                }
            }
        }
    }

    private func toggleExpand(_ id: String) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            if expandedIDs.contains(id) { expandedIDs.remove(id) }
            else { expandedIDs.insert(id) }
        }
    }
}

// ═══════════════════════════════════════════════════════
// MARK: - Layout A rows (Timeline)
// ═══════════════════════════════════════════════════════

private struct LogRowA: View {
    let workflow: LogWorkflow
    let isLast: Bool
    let isExpanded: Bool
    let matchesSearch: Bool
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Trunk column
            ZStack(alignment: .top) {
                if !isLast {
                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 1.5, alignment: .center)
                        .frame(maxHeight: .infinity)
                        .padding(.top, 18)
                }
                Circle()
                    .fill(isExpanded ? Color.white.opacity(0.80) : Color.white.opacity(0.24))
                    .frame(width: 8, height: 8)
                    .padding(.top, 13)
                    .animation(.spring(response: 0.26, dampingFraction: 0.7), value: isExpanded)
            }
            .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(workflow.hourLabel)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(isExpanded ? 0.50 : 0.32))
                    .padding(.top, 9)
                    .animation(.easeOut(duration: 0.12), value: isExpanded)

                // Collapsed card
                HStack(spacing: 0) {
                    LogToolIcon(tool: workflow.originTool, size: 28, bgSize: 28)
                        .scaleEffect(isHovered ? 1.07 : 1.0)
                        .animation(.spring(response: 0.22, dampingFraction: 0.64), value: isHovered)
                        .padding(.trailing, 8)

                    HStack(spacing: 5) {
                        Text(workflow.compactTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.88))
                            .lineLimit(1)
                        let count = workflow.outputs.count
                        if count > 0 {
                            Text("\(count)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.42))
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Capsule().fill(Color.white.opacity(0.09)))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 5) {
                        Text(workflow.workflowType)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(LogSourceStyle.accentColor(workflow.node.source))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Capsule()
                                .fill(LogSourceStyle.pillBackground(workflow.node.source)))

                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(isExpanded ? 0.45 : 0.20))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .frame(width: 18, height: 18)
                            .animation(.spring(response: 0.26, dampingFraction: 0.7), value: isExpanded)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovered || isExpanded
                          ? Color.white.opacity(0.082) : Color.white.opacity(0.048))
                    .animation(.easeOut(duration: 0.10), value: isHovered))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isExpanded ? Color.white.opacity(0.15) : Color.white.opacity(0.07), lineWidth: 0.5))
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onTapGesture(perform: onToggle)
                .onHover { isHovered = $0 }
                .pointerCursor()

                if isExpanded {
                    LogExpandedDetail(workflow: workflow)
                        .transition(.opacity.combined(with: .offset(y: -6)))
                }
            }
            .padding(.leading, 10)
            .padding(.bottom, isExpanded ? 14 : 8)
        }
    }
}

// ═══════════════════════════════════════════════════════
// MARK: - Layout B rows (Table)
// ═══════════════════════════════════════════════════════

private struct LogRowB: View {
    let workflow: LogWorkflow
    let isExpanded: Bool
    let matchesSearch: Bool
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                // Time in left fixed column
                VStack(alignment: .leading, spacing: 1) {
                    Text(workflow.hourLabel)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(isExpanded
                                         ? LogSourceStyle.accentColor(workflow.node.source)
                                         : .white.opacity(0.42))
                        .animation(.easeOut(duration: 0.12), value: isExpanded)
                    let count = workflow.outputs.count
                    Text("\(count) output\(count == 1 ? "" : "s")")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.22))
                }
                .frame(width: 68, alignment: .leading)

                // Separator line
                Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1, height: 32)
                    .padding(.horizontal, 8)

                // Icon + title
                LogToolIcon(tool: workflow.originTool, size: 24, bgSize: 24)
                    .padding(.trailing, 8)

                Text(workflow.compactTitle)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.84))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Flow tag
                Text(workflow.workflowType)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(LogSourceStyle.accentColor(workflow.node.source))
                    .lineLimit(1)
                    .padding(.trailing, 6)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(isExpanded ? 0.55 : 0.18))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.spring(response: 0.26, dampingFraction: 0.7), value: isExpanded)
            }
            .padding(.horizontal, 8).padding(.vertical, 10)
            .background(isHovered || isExpanded
                        ? Color.white.opacity(0.06) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .animation(.easeOut(duration: 0.09), value: isHovered)
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)
            .onHover { isHovered = $0 }
            .pointerCursor()

            if isExpanded {
                LogExpandedDetail(workflow: workflow)
                    .padding(.leading, 76)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }

            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
        }
    }
}

// ═══════════════════════════════════════════════════════
// MARK: - Layout C rows (Cards)
// ═══════════════════════════════════════════════════════

private struct LogRowC: View {
    let workflow: LogWorkflow
    let isExpanded: Bool
    let matchesSearch: Bool
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card header
            HStack(alignment: .top, spacing: 0) {
                // Left accent strip
                RoundedRectangle(cornerRadius: 2)
                    .fill(LogSourceStyle.accentColor(workflow.node.source))
                    .frame(width: 3)
                    .padding(.vertical, 10)
                    .padding(.trailing, 10)

                VStack(alignment: .leading, spacing: 6) {
                    // Top row: title + date chip
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(workflow.compactTitle)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white.opacity(0.90))
                                .lineLimit(1)
                            Text(workflow.workflowType)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(LogSourceStyle.accentColor(workflow.node.source))
                        }
                        Spacer()
                        // Date+time in corner
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(workflow.hourLabel)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.55))
                            Text(workflow.dayLabel)
                                .font(.system(size: 9.5))
                                .foregroundColor(.white.opacity(0.28))
                        }
                    }

                    // Source icons always visible
                    HStack(spacing: 5) {
                        ForEach(workflow.sourceTools) { tool in
                            LogToolIcon(tool: tool, size: 12, bgSize: 22)
                        }
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(isExpanded ? 0.50 : 0.22))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .animation(.spring(response: 0.26, dampingFraction: 0.7), value: isExpanded)
                    }
                }
                .padding(.vertical, 10)
                .padding(.trailing, 12)
            }

            if isExpanded {
                Rectangle().fill(Color.white.opacity(0.07)).frame(height: 0.5)
                    .padding(.horizontal, 12)
                LogExpandedDetail(workflow: workflow)
                    .padding(.leading, 13)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(isHovered ? Color.white.opacity(0.085) : Color.white.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(isExpanded
                        ? LogSourceStyle.accentColor(workflow.node.source).opacity(0.30)
                        : Color.white.opacity(0.08), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(isHovered ? 0.24 : 0.10),
                radius: isHovered ? 12 : 4, x: 0, y: isHovered ? 4 : 1)
        .offset(y: isHovered ? -1 : 0)
        .animation(.spring(response: 0.22, dampingFraction: 0.70), value: isHovered)
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .onTapGesture(perform: onToggle)
        .onHover { isHovered = $0 }
        .pointerCursor()
    }
}

// ═══════════════════════════════════════════════════════
// MARK: - Layout D rows (Feed pills)
// ═══════════════════════════════════════════════════════

private struct LogRowD: View {
    let workflow: LogWorkflow
    let isExpanded: Bool
    let anyExpanded: Bool
    let matchesSearch: Bool
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Pill row
            HStack(spacing: 8) {
                // Time chip
                Text(workflow.hourLabel)
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(isExpanded
                                     ? LogSourceStyle.accentColor(workflow.node.source)
                                     : .white.opacity(0.38))
                    .frame(width: 52, alignment: .trailing)
                    .animation(.easeOut(duration: 0.10), value: isExpanded)

                // Icon
                LogToolIcon(tool: workflow.originTool, size: 18, bgSize: 22)

                // Title
                Text(workflow.compactTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(isExpanded ? 0.92 : 0.75))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.easeOut(duration: 0.10), value: isExpanded)

                // Status: output count dot + flow label
                HStack(spacing: 4) {
                    Circle()
                        .fill(LogSourceStyle.accentColor(workflow.node.source))
                        .frame(width: 5, height: 5)
                    Text(workflow.workflowType)
                        .font(.system(size: 9.5))
                        .foregroundColor(.white.opacity(0.30))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isExpanded
                          ? Color.white.opacity(0.08)
                          : (isHovered ? Color.white.opacity(0.06) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isExpanded ? Color.white.opacity(0.12) : Color.clear, lineWidth: 0.5)
            )
            // Dim non-expanded rows when something else is open
            .opacity(anyExpanded && !isExpanded ? 0.45 : 1.0)
            .animation(.easeOut(duration: 0.14), value: isExpanded)
            .animation(.easeOut(duration: 0.14), value: anyExpanded)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onTapGesture(perform: onToggle)
            .onHover { isHovered = $0 }
            .pointerCursor()

            if isExpanded {
                LogExpandedDetail(workflow: workflow)
                    .padding(.leading, 60)  // aligns with title column
                    .padding(.bottom, 6)
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
    }
}

// ═══════════════════════════════════════════════════════
// MARK: - Shared expanded detail
// ═══════════════════════════════════════════════════════

private struct LogExpandedDetail: View {
    let workflow: LogWorkflow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Sources row
            HStack(spacing: 5) {
                Text("Sources")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.32))
                ForEach(workflow.sourceTools) { tool in
                    LogToolIconHoverable(tool: tool)
                }
            }

            // Output items
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(workflow.outputs.enumerated()), id: \.element.id) { idx, output in
                    LogOutputRow(output: output, isLast: idx == workflow.outputs.count - 1,
                                 delay: Double(idx) * 0.04)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color.white.opacity(0.038)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .stroke(Color.white.opacity(0.08), lineWidth: 0.5))
    }
}

private struct LogOutputRow: View {
    let output: LogOutputItem
    let isLast: Bool
    let delay: Double

    @State private var appeared = false
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Mini trunk dot
            VStack(spacing: 0) {
                Circle()
                    .fill(output.approvalTooltip != nil
                          ? Color.green.opacity(0.82)
                          : Color.white.opacity(0.26))
                    .frame(width: 8, height: 8)
                    .padding(.top, 3)
                if !isLast {
                    Rectangle()
                        .fill(Color.white.opacity(0.09))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                        .padding(.top, 3)
                }
            }
            .frame(width: 12)

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    if let time = output.leadingTimeLabel {
                        Text(time)
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    Text(output.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(isHovered ? 0.92 : 0.78))
                        .lineLimit(1)
                        .animation(.easeOut(duration: 0.10), value: isHovered)

                    if isHovered, let tooltip = output.approvalTooltip {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 9)).foregroundColor(.green.opacity(0.80))
                            Text(tooltip)
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundColor(.green.opacity(0.75))
                        }
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let dest = output.destination, let label = output.statusLabel {
                    LogDestinationPill(destination: dest, label: label)
                        .padding(.leading, 8)
                }
            }
            .padding(.bottom, isLast ? 0 : 8)
        }
        .onHover { isHovered = $0 }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 5)
        .onAppear {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.80).delay(delay)) {
                appeared = true
            }
        }
        .onDisappear { appeared = false }
    }
}

// ═══════════════════════════════════════════════════════
// MARK: - Reusable atoms
// ═══════════════════════════════════════════════════════

private struct LogDestinationPill: View {
    let destination: LogTool
    let label: String
    @State private var isHovered = false

    var body: some View {
        Button {} label: {
            HStack(spacing: 5) {
                LogToolIcon(tool: destination, size: 12, bgSize: 18)
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(.white.opacity(isHovered ? 0.86 : 0.60))
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.10 : 0.056)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(isHovered ? 0.18 : 0.08), lineWidth: 0.5))
            .scaleEffect(isHovered ? 1.025 : 1.0)
            .animation(.spring(response: 0.20, dampingFraction: 0.70), value: isHovered)
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .help(label)
        .onHover { isHovered = $0 }
    }
}

private struct LogToolIconHoverable: View {
    let tool: LogTool
    @State private var isHovered = false

    var body: some View {
        Button {} label: {
            LogToolIcon(tool: tool, size: 13, bgSize: 22)
                .scaleEffect(isHovered ? 1.10 : 1.0)
                .animation(.spring(response: 0.20, dampingFraction: 0.64), value: isHovered)
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .help(tool.name)
        .onHover { isHovered = $0 }
    }
}

private struct LogToolIcon: View {
    let tool: LogTool
    let size: CGFloat
    let bgSize: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .frame(width: bgSize, height: bgSize)

            if let url = tool.iconURL {
                AsyncSVGImage(urlString: url, size: bgSize)
                    .frame(width: bgSize, height: bgSize)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else if let sf = tool.systemImage {
                Image(systemName: sf)
                    .font(.system(size: size, weight: .semibold))
                    .foregroundColor(.white.opacity(0.70))
            }
        }
    }
}
