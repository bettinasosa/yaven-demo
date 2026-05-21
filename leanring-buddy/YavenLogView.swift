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

private enum LogLayout: String, CaseIterable, Identifiable, Hashable {
    case timeline = "A"
    case table    = "B"
    case segment  = "C"
    case pulse    = "D"

    var id: String { rawValue }
    var description: String {
        switch self {
        case .timeline: return "Timeline"
        case .table:    return "Table"
        case .segment:  return "Segment"
        case .pulse:    return "Pulse"
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

// MARK: - Day filter

private enum LogDayFilter: Hashable {
    case all
    case today
    case thisWeek
    case thisMonth
    case specificDay(String)   // matches a LogSection dayLabel exactly
}

private enum LogDayFilterStyle: Int, CaseIterable { case pills, strip, stepper }

private enum TimelineStyle: Int, CaseIterable {
    case trunk, journal, dots
    var label: String {
        switch self {
        case .trunk:   return "Trunk"
        case .journal: return "Journal"
        case .dots:    return "Dots"
        }
    }
}

// MARK: - Root view

struct YavenLogView: View {
    private let onOpenFlow: (String) -> Void

    @State private var searchText = ""
    @State private var layout: LogLayout = .timeline
    @State private var expandedIDs: Set<String> = Set(fakeWorkflows.prefix(1).map(\.id))
    @State private var logDayFilter: LogDayFilter = .all
    @State private var logDayFilterStyle: LogDayFilterStyle = .pills
    @State private var timelineStyle: TimelineStyle = .trunk
    @State private var listAppeared = false

    init(onOpenFlow: @escaping (String) -> Void = { _ in }) {
        self.onOpenFlow = onOpenFlow
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search + layout picker + day filter
            VStack(spacing: 8) {
                searchBar
                layoutPicker
                dayFilterRow
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
                    .opacity(listAppeared ? 1 : 0)
                    .offset(y: listAppeared ? 0 : 7)
                    .animation(.spring(response: 0.34, dampingFraction: 0.84), value: listAppeared)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: layout) { _, _ in
            listAppeared = false
            withAnimation(.spring(response: 0.34, dampingFraction: 0.84).delay(0.06)) {
                listAppeared = true
            }
        }
        .onChange(of: logDayFilter) { _, _ in
            listAppeared = false
            withAnimation(.spring(response: 0.34, dampingFraction: 0.84).delay(0.04)) {
                listAppeared = true
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.84).delay(0.10)) {
                listAppeared = true
            }
        }
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

    private var totalCount: Int { filteredWorkflows.count }

    private var filteredSections: [LogSection] {
        switch logDayFilter {
        case .all, .thisWeek, .thisMonth:
            return fakeLogSections
        case .today:
            return fakeLogSections.filter { $0.dayLabel == "Today" }
        case .specificDay(let label):
            return fakeLogSections.filter { $0.dayLabel == label }
        }
    }

    private var filteredWorkflows: [LogWorkflow] {
        filteredSections.flatMap(\.workflows)
    }

    // MARK: Layout dispatcher

    @ViewBuilder
    private var layoutContent: some View {
        switch layout {
        case .timeline: layoutA
        case .table:    layoutB
        case .segment:  layoutC
        case .pulse:    layoutD
        }
    }

    // ──────────────────────────────────────────────
    // LAYOUT A — Timeline (3 sub-styles)
    // Sub-picker at top. Each style has a different
    // visual density and interaction model.
    // ──────────────────────────────────────────────

    private var layoutA: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Timeline style sub-picker
            HStack(spacing: 4) {
                ForEach(TimelineStyle.allCases, id: \.rawValue) { style in
                    let isSelected = timelineStyle == style
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { timelineStyle = style }
                    } label: {
                        Text(style.label)
                            .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(isSelected ? .white.opacity(0.88) : .white.opacity(0.28))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule()
                                .fill(isSelected ? Color.white.opacity(0.12) : Color.clear))
                            .overlay(Capsule()
                                .stroke(isSelected ? Color.white.opacity(0.18) : Color.clear,
                                        lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                    .animation(.easeOut(duration: 0.18), value: isSelected)
                }
            }
            .padding(.bottom, 10)

            switch timelineStyle {
            case .trunk:   layoutA_trunk
            case .journal: layoutA_journal
            case .dots:    layoutA_dots
            }
        }
    }

    // Sub-style A1 — original trunk
    @ViewBuilder private var layoutA_trunk: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(filteredSections.enumerated()), id: \.element.id) { si, section in
                if si > 0 {
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
                    let isLast = si == filteredSections.count - 1 && wi == section.workflows.count - 1
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

    // Sub-style A2 — editorial journal: large day headers, titled entries
    @ViewBuilder private var layoutA_journal: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(filteredSections.enumerated()), id: \.element.id) { si, section in
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.dayLabel)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white.opacity(0.80))
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
                }
                .padding(.top, si == 0 ? 0 : 22)
                .padding(.bottom, 8)

                VStack(spacing: 2) {
                    ForEach(section.workflows) { wf in
                        LogRowA_Journal(
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
    }

    // Sub-style A3 — compact dots: ultra-dense, great for months of history
    @ViewBuilder private var layoutA_dots: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(filteredSections.enumerated()), id: \.element.id) { si, section in
                HStack(spacing: 6) {
                    if si > 0 { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 0.5) }
                    Text(section.dayLabel.uppercased())
                        .font(.system(size: 8, weight: .bold)).tracking(1.0)
                        .foregroundColor(.white.opacity(0.22)).fixedSize()
                    Rectangle().fill(Color.white.opacity(0.07)).frame(height: 0.5)
                }
                .padding(.top, si == 0 ? 0 : 10)
                .padding(.bottom, 4)

                VStack(spacing: 0) {
                    ForEach(section.workflows) { wf in
                        LogRowA_Dots(
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
            ForEach(filteredSections) { section in
                // Date header row
                HStack(spacing: 0) {
                    Text(section.dayLabel.uppercased())
                        .font(.system(size: 9.5, weight: .bold))
                        .tracking(0.8)
                        .foregroundColor(.white.opacity(0.42))
                        .frame(width: 72, alignment: .leading)
                    Rectangle().fill(Color.white.opacity(0.10)).frame(height: 0.5)
                }
                .padding(.bottom, 4)
                .padding(.top, 12)

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
    // LAYOUT C — Floating segments
    // Dates: section header rule (same as B)
    // Micro: double-bezel stroke, source strip height-
    //        spring on hover, icon scale, accent glow
    //        shadow, row lifts -1.5px on hover
    // ──────────────────────────────────────────────

    private var layoutC: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(filteredSections) { section in
                HStack(spacing: 0) {
                    Text(section.dayLabel.uppercased())
                        .font(.system(size: 9.5, weight: .bold))
                        .tracking(0.8)
                        .foregroundColor(.white.opacity(0.42))
                        .frame(width: 72, alignment: .leading)
                    Rectangle().fill(Color.white.opacity(0.10)).frame(height: 0.5)
                }
                .padding(.bottom, 6).padding(.top, 12)

                VStack(spacing: 4) {
                    ForEach(section.workflows) { wf in
                        LogRowC_Segment(
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
    }

    // ──────────────────────────────────────────────
    // LAYOUT D — Hairline Pulse
    // Dates: section header rule (same as B/C)
    // Times: monospaced, spring-animate to accent
    // Micro: left colored rule grows from 0 on hover,
    //        gradient sweep fills row from leading,
    //        hairline separator animates to accent tint
    // ──────────────────────────────────────────────

    private var layoutD: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(filteredSections) { section in
                HStack(spacing: 0) {
                    Text(section.dayLabel.uppercased())
                        .font(.system(size: 9.5, weight: .bold))
                        .tracking(0.8)
                        .foregroundColor(.white.opacity(0.42))
                        .frame(width: 72, alignment: .leading)
                    Rectangle().fill(Color.white.opacity(0.10)).frame(height: 0.5)
                }
                .padding(.bottom, 2).padding(.top, 14)

                VStack(spacing: 0) {
                    ForEach(section.workflows) { wf in
                        LogRowD_Pulse(
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
    }

    // MARK: - Day filter row

    private var dayFilterRow: some View {
        HStack(alignment: .center, spacing: 0) {
            Group {
                switch logDayFilterStyle {
                case .pills:   dayFilterPills
                case .strip:   dayFilterStrip
                case .stepper: dayFilterStepper
                }
            }
            Spacer(minLength: 6)
            // Three-dot style switcher
            HStack(spacing: 6) {
                ForEach(LogDayFilterStyle.allCases, id: \.rawValue) { style in
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.80)) {
                            logDayFilterStyle = style
                        }
                    } label: {
                        Circle()
                            .fill(logDayFilterStyle == style
                                  ? Color.white.opacity(0.60)
                                  : Color.white.opacity(0.18))
                            .frame(width: 5, height: 5)
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                }
            }
        }
    }

    // Style 1 — time-range pills: All · Today · Week · Month
    private var dayFilterPills: some View {
        HStack(spacing: 4) {
            logDayFilterButton(.all, label: "All")
            logDayFilterButton(.today, label: "Today")
            logDayFilterButton(.thisWeek, label: "Week")
            logDayFilterButton(.thisMonth, label: "Month")
        }
    }

    private func logDayFilterButton(_ filter: LogDayFilter, label: String) -> some View {
        let isSelected = logDayFilter == filter
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.80)) {
                logDayFilter = filter
            }
        } label: {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .white.opacity(0.32))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.16) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isSelected ? Color.white.opacity(0.24) : Color.clear, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    // Style 2 — scrollable 14-day calendar strip with data-presence dots
    private var dayFilterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                dayStripAllCircle
                // oldest on left, newest (today) on right
                ForEach(Array((0..<14).reversed()), id: \.self) { daysAgo in
                    dayStripDayCircle(daysAgo: daysAgo)
                }
            }
        }
    }

    private var dayStripAllCircle: some View {
        let isSelected = logDayFilter == .all
        let accentBlue = Color(red: 0.22, green: 0.55, blue: 1.0)
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.80)) {
                logDayFilter = .all
            }
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .fill(isSelected ? accentBlue : Color.white.opacity(0.08))
                        .frame(width: 28, height: 28)
                    Text("∞")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(isSelected ? .white : Color.white.opacity(0.45))
                }
                Text("\(fakeWorkflows.count)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(isSelected ? .white.opacity(0.85) : .white.opacity(0.25))
            }
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    private func dayStripDayCircle(daysAgo: Int) -> some View {
        let filter: LogDayFilter = daysAgo == 0 ? .today : .specificDay(sectionLabel(daysAgo: daysAgo))
        let isSelected = logDayFilter == filter
        let count = workflowCountForFilter(filter)
        let letter = weekdayLetter(daysAgo: daysAgo)
        let num = calendarDayNumber(daysAgo: daysAgo)
        let accentBlue = Color(red: 0.22, green: 0.55, blue: 1.0)

        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.80)) {
                logDayFilter = filter
            }
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .fill(isSelected ? accentBlue : Color.white.opacity(0.06))
                        .frame(width: 28, height: 28)
                    VStack(spacing: 0) {
                        Text(letter)
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(isSelected ? .white.opacity(0.80) : .white.opacity(0.28))
                        Text(num)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(isSelected ? .white : .white.opacity(count > 0 ? 0.72 : 0.22))
                    }
                }
                Circle()
                    .fill(count > 0
                          ? Color(red: 0.24, green: 0.88, blue: 0.62).opacity(0.65)
                          : Color.clear)
                    .frame(width: 4, height: 4)
            }
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    // Maps daysAgo offset to the LogSection.dayLabel used in fake data
    private func sectionLabel(daysAgo: Int) -> String {
        switch daysAgo {
        case 0: return "Today"
        case 1: return "Yesterday"
        case 2: return "Monday"    // May 19 in fake data
        default: return "Day-\(daysAgo)"
        }
    }

    private func workflowCountForFilter(_ filter: LogDayFilter) -> Int {
        switch filter {
        case .all: return fakeWorkflows.count
        case .today: return fakeLogSections.first { $0.dayLabel == "Today" }?.workflows.count ?? 0
        case .thisWeek, .thisMonth: return fakeWorkflows.count
        case .specificDay(let label): return fakeLogSections.first { $0.dayLabel == label }?.workflows.count ?? 0
        }
    }

    // Today is Thu May 21 2026 — Thursday = weekday index 5 (Sun=0)
    private func weekdayLetter(daysAgo: Int) -> String {
        let letters = ["S", "M", "T", "W", "T", "F", "S"]
        let weekday = ((5 - daysAgo) % 7 + 7) % 7
        return letters[weekday]
    }

    private func calendarDayNumber(daysAgo: Int) -> String {
        "\(21 - daysAgo)"  // window is May 8–21
    }

    // Style 3 — stepper: ‹ Today (2) ›
    private var dayFilterStepper: some View {
        let allFilters: [LogDayFilter] = [.all, .today, .thisWeek, .thisMonth]
        let currentIndex = allFilters.firstIndex(of: logDayFilter) ?? 0
        let label: String = {
            switch logDayFilter {
            case .all:
                return "All (\(fakeWorkflows.count))"
            case .today:
                let n = fakeLogSections.first { $0.dayLabel == "Today" }?.workflows.count ?? 0
                return "Today (\(n))"
            case .thisWeek:
                return "This Week (\(fakeWorkflows.count))"
            case .thisMonth:
                return "This Month (\(fakeWorkflows.count))"
            case .specificDay(let d):
                let n = fakeLogSections.first { $0.dayLabel == d }?.workflows.count ?? 0
                return "\(d) (\(n))"
            }
        }()
        return HStack(spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.80)) {
                    if currentIndex > 0 { logDayFilter = allFilters[currentIndex - 1] }
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(currentIndex > 0 ? 0.55 : 0.18))
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .disabled(currentIndex == 0)

            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .frame(minWidth: 110, alignment: .center)
                .animation(.none, value: logDayFilter)

            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.80)) {
                    if currentIndex < allFilters.count - 1 { logDayFilter = allFilters[currentIndex + 1] }
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(currentIndex < allFilters.count - 1 ? 0.55 : 0.18))
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .disabled(currentIndex >= allFilters.count - 1)
        }
    }

    private func toggleExpand(_ id: String) {
        withAnimation(.easeOut(duration: 0.26)) {
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

                LogExpandedDetail(workflow: workflow)
                    .frame(height: isExpanded ? nil : 0)
                    .clipped()
                    .opacity(isExpanded ? 1 : 0)
                    .animation(.easeOut(duration: 0.24), value: isExpanded)
            }
            .padding(.leading, 10)
            .padding(.bottom, isExpanded ? 14 : 8)
        }
    }
}

// ═══════════════════════════════════════════════════════
// MARK: - Layout A2 rows (Journal)
// ═══════════════════════════════════════════════════════

// Editorial feel: prominent title, source accent left strip
// that springs in height on hover, detail reveals via smooth
// height clip (no bounce, no sibling jiggle).

private struct LogRowA_Journal: View {
    let workflow: LogWorkflow
    let isExpanded: Bool
    let matchesSearch: Bool
    let onToggle: () -> Void

    @State private var isHovered = false
    private var accent: Color { LogSourceStyle.accentColor(workflow.node.source) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                // Source accent strip — springs taller on hover/expand
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(accent.opacity(isExpanded ? 0.88 : (isHovered ? 0.60 : 0.30)))
                    .frame(width: 2.5)
                    .padding(.vertical, 8)
                    .padding(.trailing, 12)
                    .animation(.easeOut(duration: 0.14), value: isHovered)
                    .animation(.easeOut(duration: 0.14), value: isExpanded)

                VStack(alignment: .leading, spacing: 4) {
                    // Timestamp above title
                    Text(workflow.hourLabel)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundColor(accent.opacity(0.55))

                    HStack(spacing: 8) {
                        Text(workflow.compactTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white.opacity(isHovered ? 0.96 : 0.84))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .animation(.easeOut(duration: 0.10), value: isHovered)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(isExpanded ? 0.50 : 0.22))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .animation(.spring(response: 0.28, dampingFraction: 0.76), value: isExpanded)
                    }

                    // Source icons + flow tag in a single compact row
                    HStack(spacing: 5) {
                        ForEach(workflow.sourceTools.prefix(3)) { tool in
                            LogToolIcon(tool: tool, size: 10, bgSize: 18)
                        }
                        Text(workflow.workflowType.uppercased())
                            .font(.system(size: 8, weight: .bold))
                            .tracking(0.5)
                            .foregroundColor(accent.opacity(0.50))
                            .padding(.leading, 2)
                    }
                    .opacity(isExpanded ? 0.5 : 1.0)
                    .animation(.easeOut(duration: 0.12), value: isExpanded)
                }
                .padding(.top, 8).padding(.bottom, 10)
            }

            // Height-reveal expanded detail — no layout jiggle
            LogExpandedDetail(workflow: workflow)
                .padding(.leading, 14 + 12)
                .padding(.bottom, isExpanded ? 12 : 0)
                .frame(height: isExpanded ? nil : 0)
                .clipped()
                .opacity(isExpanded ? 1 : 0)
                .animation(.easeOut(duration: 0.24), value: isExpanded)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered || isExpanded ? Color.white.opacity(0.042) : Color.clear)
        )
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture(perform: onToggle)
        .onHover { isHovered = $0 }
        .pointerCursor()
    }
}

// ═══════════════════════════════════════════════════════
// MARK: - Layout A3 rows (Dots — compact)
// ═══════════════════════════════════════════════════════

// Ultra-dense single-line rows — ideal for scanning months
// of history. Source dot pulses on hover. Detail reveals
// inline without shifting siblings.

private struct LogRowA_Dots: View {
    let workflow: LogWorkflow
    let isExpanded: Bool
    let matchesSearch: Bool
    let onToggle: () -> Void

    @State private var isHovered = false
    private var accent: Color { LogSourceStyle.accentColor(workflow.node.source) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                // Source dot — scales on hover (magnetic pulse)
                Circle()
                    .fill(accent.opacity(isHovered || isExpanded ? 0.90 : 0.45))
                    .frame(width: 6, height: 6)
                    .scaleEffect(isHovered ? 1.25 : 1.0)
                    .animation(.spring(response: 0.18, dampingFraction: 0.56), value: isHovered)
                    .padding(.leading, 4).padding(.trailing, 10)

                // Time
                Text(workflow.hourLabel)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundColor(isExpanded ? accent : .white.opacity(0.36))
                    .frame(width: 52, alignment: .leading)
                    .animation(.easeOut(duration: 0.10), value: isExpanded)

                Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1, height: 14)
                    .padding(.horizontal, 8)

                LogToolIcon(tool: workflow.originTool, size: 14, bgSize: 20)
                    .padding(.trailing, 7)

                Text(workflow.compactTitle)
                    .font(.system(size: 12, weight: isHovered || isExpanded ? .medium : .regular))
                    .foregroundColor(.white.opacity(isHovered || isExpanded ? 0.90 : 0.62))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.easeOut(duration: 0.09), value: isHovered)

                // Output count badge
                let count = workflow.outputs.count
                Text("\(count)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.24))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.07)))
                    .padding(.trailing, 5)

                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white.opacity(isExpanded ? 0.50 : 0.14))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.spring(response: 0.24, dampingFraction: 0.72), value: isExpanded)
                    .padding(.trailing, 3)
            }
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHovered || isExpanded ? Color.white.opacity(0.05) : Color.clear)
            )
            .animation(.easeOut(duration: 0.09), value: isHovered)
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)
            .onHover { isHovered = $0 }
            .pointerCursor()

            // Height-reveal — expands inline without shifting siblings
            LogExpandedDetail(workflow: workflow)
                .padding(.leading, 30)
                .padding(.bottom, isExpanded ? 6 : 0)
                .frame(height: isExpanded ? nil : 0)
                .clipped()
                .opacity(isExpanded ? 1 : 0)
                .animation(.easeOut(duration: 0.22), value: isExpanded)
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
                                         : (isHovered
                                            ? LogSourceStyle.accentColor(workflow.node.source).opacity(0.65)
                                            : .white.opacity(0.42)))
                        .animation(.easeOut(duration: 0.12), value: isHovered)
                        .animation(.easeOut(duration: 0.12), value: isExpanded)
                    let count = workflow.outputs.count
                    Text("\(count) output\(count == 1 ? "" : "s")")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.88))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Flow tag
                Text(workflow.workflowType.uppercased())
                    .font(.system(size: 8.5, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(LogSourceStyle.accentColor(workflow.node.source).opacity(0.80))
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

            LogExpandedDetail(workflow: workflow)
                .padding(.leading, 76)
                .padding(.bottom, isExpanded ? 8 : 0)
                .frame(height: isExpanded ? nil : 0)
                .clipped()
                .opacity(isExpanded ? 1 : 0)
                .animation(.easeOut(duration: 0.24), value: isExpanded)

            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
        }
    }
}

// ═══════════════════════════════════════════════════════
// MARK: - Layout C rows (Segment — floating glass pills)
// ═══════════════════════════════════════════════════════

// Double-bezel floating segment: source-colored left strip
// spring-animates in height, icon scales on hover, row lifts
// -1.5px with diffused glow shadow on expand.

private struct LogRowC_Segment: View {
    let workflow: LogWorkflow
    let isExpanded: Bool
    let matchesSearch: Bool
    let onToggle: () -> Void

    @State private var isHovered = false

    private var accent: Color { LogSourceStyle.accentColor(workflow.node.source) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                // Source strip — springs taller on hover/expand
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(accent.opacity(isHovered || isExpanded ? 0.88 : 0.38))
                    .frame(width: 2.5, height: isHovered || isExpanded ? 36 : 20)
                    .animation(.spring(response: 0.28, dampingFraction: 0.68), value: isHovered)
                    .animation(.spring(response: 0.28, dampingFraction: 0.68), value: isExpanded)
                    .padding(.leading, 10)
                    .padding(.trailing, 9)

                // Time column
                VStack(alignment: .leading, spacing: 1) {
                    Text(workflow.hourLabel)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(isExpanded
                                         ? accent
                                         : accent.opacity(isHovered ? 0.72 : 0.48))
                        .animation(.easeOut(duration: 0.11), value: isHovered)
                    let count = workflow.outputs.count
                    Text("\(count) out")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.20))
                }
                .frame(width: 58, alignment: .leading)

                // Hairline separator
                Rectangle().fill(Color.white.opacity(isHovered ? 0.10 : 0.06))
                    .frame(width: 1, height: 28)
                    .padding(.horizontal, 10)
                    .animation(.easeOut(duration: 0.10), value: isHovered)

                // Icon — scales on hover (magnetic feel)
                LogToolIcon(tool: workflow.originTool, size: 22, bgSize: 26)
                    .scaleEffect(isHovered ? 1.09 : 1.0)
                    .animation(.spring(response: 0.20, dampingFraction: 0.58), value: isHovered)
                    .padding(.trailing, 9)

                // Title
                Text(workflow.compactTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(isHovered ? 0.96 : 0.82))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.easeOut(duration: 0.10), value: isHovered)

                // Flow tag + chevron
                HStack(spacing: 6) {
                    Text(workflow.workflowType.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.55)
                        .foregroundColor(accent.opacity(isHovered ? 0.80 : 0.55))
                        .lineLimit(1)
                        .animation(.easeOut(duration: 0.10), value: isHovered)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(isExpanded ? 0.60 : 0.20))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.spring(response: 0.26, dampingFraction: 0.70), value: isExpanded)
                }
                .padding(.trailing, 10)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)
            .onHover { isHovered = $0 }
            .pointerCursor()

            // Height-reveal: always in hierarchy, clips to 0 when collapsed.
            // easeOut prevents sibling rows from bouncing/jiggling.
            LogExpandedDetail(workflow: workflow)
                .padding(.leading, 91)
                .padding(.trailing, 10)
                .padding(.bottom, isExpanded ? 10 : 0)
                .frame(height: isExpanded ? nil : 0)
                .clipped()
                .opacity(isExpanded ? 1 : 0)
                .animation(.easeOut(duration: 0.24), value: isExpanded)
        }
        // Outer shell — fills lightly, double-bezel gradient stroke
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isHovered ? Color.white.opacity(0.072) : Color.white.opacity(0.040))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isExpanded ? 0.20 : (isHovered ? 0.15 : 0.08)),
                            Color.white.opacity(0.03)
                        ],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
        )
        // Diffused lift shadow + source accent glow on expand
        .shadow(color: .black.opacity(isHovered ? 0.20 : 0.06),
                radius: isHovered ? 12 : 3, x: 0, y: isHovered ? 4 : 1)
        .shadow(color: accent.opacity(isExpanded ? 0.13 : 0),
                radius: 16, x: 0, y: 0)
        .offset(y: isHovered ? -1.5 : 0)
        .animation(.spring(response: 0.24, dampingFraction: 0.66), value: isHovered)
    }
}

// ═══════════════════════════════════════════════════════
// MARK: - Layout D rows (Pulse — hairline minimal)
// ═══════════════════════════════════════════════════════

// No card backgrounds. Hairline rules only. On hover a
// 2px source-color rule springs up from height 0, and a
// gradient wash sweeps in from the leading edge. The
// hairline rule itself tints to the source accent.

private struct LogRowD_Pulse: View {
    let workflow: LogWorkflow
    let isExpanded: Bool
    let matchesSearch: Bool
    let onToggle: () -> Void

    @State private var isHovered = false

    private var accent: Color { LogSourceStyle.accentColor(workflow.node.source) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .leading) {
                // Gradient sweep — enters from leading on hover/expand
                LinearGradient(
                    colors: [accent.opacity(isHovered || isExpanded ? 0.055 : 0), Color.clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .animation(.easeOut(duration: 0.18), value: isHovered)

                HStack(alignment: .center, spacing: 0) {
                    // Left colored rule — springs from zero height on hover
                    RoundedRectangle(cornerRadius: 1)
                        .fill(accent)
                        .frame(width: 2, height: isHovered || isExpanded ? 26 : 0)
                        .animation(.spring(response: 0.22, dampingFraction: 0.62), value: isHovered)
                        .animation(.spring(response: 0.22, dampingFraction: 0.62), value: isExpanded)
                        .padding(.leading, 2)
                        .padding(.trailing, 9)

                    // Time: muted → accent on hover
                    Text(workflow.hourLabel)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(isExpanded
                                         ? accent
                                         : (isHovered ? accent.opacity(0.80) : .white.opacity(0.36)))
                        .frame(width: 56, alignment: .leading)
                        .animation(.easeOut(duration: 0.11), value: isHovered)

                    // Separator
                    Rectangle().fill(Color.white.opacity(isHovered ? 0.09 : 0.05))
                        .frame(width: 1, height: 22)
                        .padding(.horizontal, 10)
                        .animation(.easeOut(duration: 0.10), value: isHovered)

                    // Icon
                    LogToolIcon(tool: workflow.originTool, size: 18, bgSize: 22)
                        .padding(.trailing, 8)

                    // Title — weight bumps on hover
                    Text(workflow.compactTitle)
                        .font(.system(size: 12.5,
                                      weight: isHovered || isExpanded ? .semibold : .regular))
                        .foregroundColor(.white.opacity(isHovered || isExpanded ? 0.94 : 0.68))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(.easeOut(duration: 0.09), value: isHovered)

                    // Flow label
                    Text(workflow.workflowType.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(accent.opacity(isHovered || isExpanded ? 0.75 : 0.28))
                        .lineLimit(1)
                        .padding(.trailing, 6)
                        .animation(.easeOut(duration: 0.10), value: isHovered)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(isExpanded ? 0.55 : 0.16))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.spring(response: 0.26, dampingFraction: 0.70), value: isExpanded)
                        .padding(.trailing, 4)
                }
                .padding(.vertical, 9)
                .contentShape(Rectangle())
                .onTapGesture(perform: onToggle)
                .onHover { isHovered = $0 }
                .pointerCursor()
            }

            LogExpandedDetail(workflow: workflow)
                .padding(.leading, 81)
                .padding(.bottom, isExpanded ? 6 : 0)
                .frame(height: isExpanded ? nil : 0)
                .clipped()
                .opacity(isExpanded ? 1 : 0)
                .animation(.easeOut(duration: 0.24), value: isExpanded)

            // Hairline — tints to source accent on hover
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            accent.opacity(isHovered || isExpanded ? 0.30 : 0),
                            Color.white.opacity(0.07)
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(height: 0.5)
                .animation(.easeOut(duration: 0.14), value: isHovered)
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
                Text("SOURCES")
                    .font(.system(size: 8.5, weight: .bold))
                    .tracking(0.7)
                    .foregroundColor(.white.opacity(0.28))
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
