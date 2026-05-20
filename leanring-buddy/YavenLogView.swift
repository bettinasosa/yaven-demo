//
//  YavenLogView.swift
//  leanring-buddy
//
//  Activity Log audit pane for reviewing completed Yaven workflows.
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

    var id: String { domain ?? systemImage ?? name }
    var iconURL: String? {
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
                LogOutputItem(
                    id: batchCard.id,
                    title: outputTitle(for: batchCard),
                    leadingTimeLabel: nil,
                    statusLabel: batchCard.kind.statusLabel,
                    destination: .notion,
                    approvalTooltip: nil
                ),
                LogOutputItem(
                    id: "\(node.id)-approved",
                    title: "Approved",
                    leadingTimeLabel: approvalTime,
                    statusLabel: nil,
                    destination: nil,
                    approvalTooltip: "Approved by you at \(approvalTime)"
                ),
                LogOutputItem(
                    id: "\(node.id)-linkedin-sent",
                    title: "Sent to LinkedIn",
                    leadingTimeLabel: nil,
                    statusLabel: "View on LinkedIn",
                    destination: .linkedIn,
                    approvalTooltip: nil
                ),
            ]
        }

        var items = node.cards.map { card in
            LogOutputItem(
                id: card.id,
                title: outputTitle(for: card),
                leadingTimeLabel: nil,
                statusLabel: card.kind.statusLabel,
                destination: card.kind.destinationTool,
                approvalTooltip: card.kind == .emailDraft ? "Approved by you at \(approvalTime)" : nil
            )
        }

        if node.source == .meetingLoop {
            items.append(
                LogOutputItem(
                    id: "\(node.id)-hubspot-note",
                    title: "HubSpot call note",
                    leadingTimeLabel: nil,
                    statusLabel: LogArtifactKind.hubSpotNote.statusLabel,
                    destination: .hubSpot,
                    approvalTooltip: "Approved by you at \(approvalTime)"
                )
            )
        }

        return items
    }

    private func outputTitle(for card: LogCard) -> String {
        switch card.kind {
        case .meetingNote:
            return "Meeting notes"
        case .actionItems, .emailDraft, .linkedInBatch, .research, .hubSpotNote:
            return card.title
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

        let workflowFields = [
            compactTitle,
            title,
            workflowType,
            node.timeLabel,
        ] + sourceTools.map(\.name)

        let outputFields = outputs.flatMap { output in
            [
                output.title,
                output.statusLabel ?? "",
                output.destination?.name ?? "",
                output.approvalTooltip ?? "",
            ]
        }

        return (workflowFields + outputFields).contains {
            $0.localizedCaseInsensitiveContains(query)
        }
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
    static let calendar = LogTool(name: "Calendar", domain: "calendar.google.com", systemImage: nil)
    static let gmail = LogTool(name: "Gmail", domain: "mail.google.com", systemImage: nil)
    static let granola = LogTool(name: "Granola", domain: "granola.so", systemImage: nil)
    static let hubSpot = LogTool(name: "HubSpot", domain: "hubspot.com", systemImage: nil)
    static let linkedIn = LogTool(name: "LinkedIn", domain: "linkedin.com", systemImage: nil)
    static let memory = LogTool(name: "Memory", domain: nil, systemImage: "archivebox.fill")
    static let notion = LogTool(name: "Notion", domain: "notion.so", systemImage: nil)
}

// MARK: - Fake data

private let fakeNodes: [LogNode] = [
    LogNode(id: "n1", timeLabel: "Today  9:34am", source: .meetingLoop, cards: [
        LogCard(id: "n1c1", kind: .meetingNote, title: "Product sync — meeting notes"),
        LogCard(id: "n1c2", kind: .actionItems, title: "Action items (3)"),
        LogCard(id: "n1c3", kind: .emailDraft,  title: "Follow-up to Jamie Chen"),
    ]),
    LogNode(id: "n2", timeLabel: "Today  8:00am", source: .linkedIn, cards: [
        LogCard(id: "n2c1", kind: .linkedInBatch, title: "Outreach batch — 10 drafts"),
    ]),
    LogNode(id: "n3", timeLabel: "Yesterday  3:12pm", source: .meetingLoop, cards: [
        LogCard(id: "n3c1", kind: .meetingNote, title: "Design review — meeting notes"),
        LogCard(id: "n3c2", kind: .actionItems, title: "Action items (2)"),
        LogCard(id: "n3c3", kind: .emailDraft,  title: "Follow-up to Priya Mehta"),
    ]),
    LogNode(id: "n4", timeLabel: "Yesterday  8:00am", source: .linkedIn, cards: [
        LogCard(id: "n4c1", kind: .linkedInBatch, title: "Outreach batch — 8 drafts"),
    ]),
    LogNode(id: "n5", timeLabel: "Mon 19 May  2:45pm", source: .meetingLoop, cards: [
        LogCard(id: "n5c1", kind: .meetingNote, title: "Investor update prep"),
        LogCard(id: "n5c2", kind: .actionItems, title: "Action items (1)"),
    ]),
    LogNode(id: "n6", timeLabel: "Mon 19 May  8:00am", source: .linkedIn, cards: [
        LogCard(id: "n6c1", kind: .linkedInBatch, title: "Outreach batch — 10 drafts"),
    ]),
    LogNode(id: "n7", timeLabel: "Mon 19 May  11:20am", source: .manual, cards: [
        LogCard(id: "n7c1", kind: .research, title: "Research summary — Notion AI vs Yaven positioning"),
    ]),
]

private let fakeWorkflows = fakeNodes.map { LogWorkflow(node: $0) }

private struct LogWorkflowSection: Identifiable {
    let dayLabel: String
    var workflows: [LogWorkflow]

    var id: String { dayLabel }
}

private let fakeWorkflowSections: [LogWorkflowSection] = {
    var sections: [LogWorkflowSection] = []

    for workflow in fakeWorkflows {
        if let sectionIndex = sections.firstIndex(where: { $0.dayLabel == workflow.dayLabel }) {
            sections[sectionIndex].workflows.append(workflow)
        } else {
            sections.append(LogWorkflowSection(dayLabel: workflow.dayLabel, workflows: [workflow]))
        }
    }

    for sectionIndex in sections.indices {
        sections[sectionIndex].workflows.sort { $0.hourSortValue > $1.hourSortValue }
    }

    return sections
}()

// MARK: - Root view

struct YavenLogView: View {
    private let onOpenFlow: (String) -> Void

    @State private var searchText = ""
    @State private var expandedWorkflowIDs: Set<String> = Set(fakeWorkflows.prefix(1).map(\.id))

    init(onOpenFlow: @escaping (String) -> Void = { _ in }) {
        self.onOpenFlow = onOpenFlow
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, 28)
                .padding(.top, 10)
                .padding(.bottom, 8)

            Divider().opacity(0.08)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Flat timeline — no section headers; day separators appear inline
                    ForEach(Array(fakeWorkflowSections.enumerated()), id: \.element.id) { sectionIndex, section in
                        // Day separator chip before each section (except the first)
                        if sectionIndex > 0 {
                            LogDaySeparator(label: section.dayLabel)
                                .padding(.vertical, 6)
                        } else {
                            // First section: small date badge at very top
                            LogDayBadge(label: section.dayLabel)
                                .padding(.bottom, 6)
                        }

                        ForEach(Array(section.workflows.enumerated()), id: \.element.id) { index, workflow in
                            let isLastInSection = index == section.workflows.count - 1
                            let isLastOverall = sectionIndex == fakeWorkflowSections.count - 1 && isLastInSection
                            LogTimelineWorkflowRow(
                                workflow: workflow,
                                isLast: isLastOverall,
                                isExpanded: expandedWorkflowIDs.contains(workflow.id),
                                matchesSearch: workflow.matchesSearch(searchText),
                                onOpenFlow: onOpenFlow,
                                onToggleExpansion: {
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                        if expandedWorkflowIDs.contains(workflow.id) {
                                            expandedWorkflowIDs.remove(workflow.id)
                                        } else {
                                            expandedWorkflowIDs.insert(workflow.id)
                                        }
                                    }
                                }
                            )
                            .animation(.easeOut(duration: 0.15).delay(Double(index) * 0.012), value: searchText)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 10)
                .padding(.bottom, 28)
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
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 0.5))
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: searchText.isEmpty)
    }
}

// MARK: - Day labels

private struct LogDayBadge: View {
    let label: String
    var body: some View {
        Text(label.uppercased())
            .font(.system(size: 9.5, weight: .bold))
            .foregroundColor(.white.opacity(0.32))
            .tracking(0.8)
            .padding(.leading, 32)  // aligns past trunk column
    }
}

private struct LogDaySeparator: View {
    let label: String
    var body: some View {
        HStack(spacing: 0) {
            // Trunk-width spacer so label aligns with content column
            Rectangle().fill(Color.clear).frame(width: 22)
            Spacer().frame(width: 10)
            Text(label.uppercased())
                .font(.system(size: 9.5, weight: .bold))
                .foregroundColor(.white.opacity(0.30))
                .tracking(0.8)
            Rectangle()
                .fill(Color.white.opacity(0.09))
                .frame(height: 0.5)
                .padding(.leading, 8)
        }
    }
}

// MARK: - Workflow timeline row

private struct LogTimelineWorkflowRow: View {
    let workflow: LogWorkflow
    let isLast: Bool
    let isExpanded: Bool
    let matchesSearch: Bool
    let onOpenFlow: (String) -> Void
    let onToggleExpansion: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            trunkColumn
            contentColumn
        }
        .opacity(matchesSearch ? 1.0 : 0.18)
        .animation(.easeOut(duration: 0.12), value: matchesSearch)
    }

    private var trunkColumn: some View {
        ZStack(alignment: .top) {
            // Continuous trunk line
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 1.5)
                .frame(maxHeight: .infinity)
                .padding(.top, 20)
                .opacity(isLast ? 0 : 1)

            // Node dot — brightens when expanded
            let dotFill = isExpanded ? Color.white.opacity(0.80) : Color.white.opacity(0.25)
            let dotStroke = isExpanded ? Color.white.opacity(0.30) : Color.white.opacity(0.10)
            Circle()
                .fill(dotFill)
                .overlay(Circle().stroke(dotStroke, lineWidth: 0.5))
                .frame(width: 8, height: 8)
                .padding(.top, 14)
                .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isExpanded)
        }
        .frame(width: 22)
    }

    private var contentColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Time label — prominent, with day context on hover
            HStack(spacing: 5) {
                Text(workflow.hourLabel)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(isExpanded ? 0.55 : 0.36))
                    .animation(.easeOut(duration: 0.12), value: isExpanded)
            }
            .padding(.top, 10)

            collapsedRow

            if isExpanded {
                expandedWorkflow
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: -4)),
                            removal: .opacity.combined(with: .offset(y: -2))
                        )
                    )
            }
        }
        .padding(.leading, 10)
        .padding(.bottom, isExpanded ? 14 : 8)
    }

    private var collapsedRow: some View {
        HStack(spacing: 0) {
            // Origin icon with hover scale
            LogToolIcon(tool: workflow.originTool, size: 30, backgroundSize: 30)
                .scaleEffect(isHovered ? 1.06 : 1.0)
                .animation(.spring(response: 0.24, dampingFraction: 0.65), value: isHovered)
                .padding(.trailing, 9)

            // Title + output count badge
            HStack(spacing: 6) {
                Text(workflow.compactTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.88))
                    .lineLimit(1)

                // Output count dot
                let outputCount = workflow.outputs.count
                if outputCount > 0 {
                    Text("\(outputCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.50))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Flow type tag + chevron
            HStack(spacing: 6) {
                Button {
                    onOpenFlow(workflow.workflowType)
                } label: {
                    Text(workflow.workflowType)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(LogSourceColors.text(for: workflow.node.source))
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(LogSourceColors.background(for: workflow.node.source))
                        )
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .help("Open \(workflow.workflowType) flow")

                // Rotating chevron (not a swap)
                Button(action: onToggleExpansion) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(isExpanded ? 0.50 : 0.22))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .frame(width: 20, height: 20)
                        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isExpanded)
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered || isExpanded ? Color.white.opacity(0.082) : Color.white.opacity(0.048))
                .animation(.easeOut(duration: 0.10), value: isHovered)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isExpanded ? Color.white.opacity(0.16) : Color.white.opacity(0.07), lineWidth: 0.5)
                .animation(.easeOut(duration: 0.15), value: isExpanded)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture(perform: onToggleExpansion)
        .onHover { isHovered = $0 }
        .pointerCursor()
    }

    private var expandedWorkflow: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Sources strip
            HStack(spacing: 6) {
                Text("Sources")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.36))
                ForEach(workflow.sourceTools) { tool in
                    LogToolIconButton(tool: tool)
                }
            }

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 0.5)

            // Output rows
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(workflow.outputs.enumerated()), id: \.element.id) { index, output in
                    LogOutputTimelineRow(
                        output: output,
                        isLast: index == workflow.outputs.count - 1,
                        appearDelay: Double(index) * 0.04
                    )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.042)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 0.5))
    }
}

// MARK: - Flow type colour tokens

private enum LogSourceColors {
    static func background(for source: LogSource) -> Color {
        switch source {
        case .meetingLoop: return Color(red: 0.20, green: 0.88, blue: 0.60).opacity(0.14)
        case .linkedIn:    return Color(red: 0.25, green: 0.52, blue: 0.96).opacity(0.16)
        case .manual:      return Color.white.opacity(0.08)
        }
    }

    static func text(for source: LogSource) -> Color {
        switch source {
        case .meetingLoop: return Color(red: 0.28, green: 0.90, blue: 0.64)
        case .linkedIn:    return Color(red: 0.47, green: 0.72, blue: 1.00)
        case .manual:      return Color.white.opacity(0.52)
        }
    }
}

// MARK: - Output timeline row

private struct LogOutputTimelineRow: View {
    let output: LogOutputItem
    let isLast: Bool
    let appearDelay: Double

    @State private var appeared = false
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            // Mini trunk
            VStack(spacing: 0) {
                outputNode
                if !isLast {
                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(maxHeight: .infinity)
                        .frame(width: 1)
                        .padding(.top, 3)
                }
            }
            .frame(width: 14)
            .padding(.top, 4)

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    // Optional approval timestamp inline
                    if let leadingTimeLabel = output.leadingTimeLabel {
                        Text(leadingTimeLabel)
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.36))
                    }

                    Text(output.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(isHovered ? 0.92 : 0.80))
                        .lineLimit(1)
                        .animation(.easeOut(duration: 0.10), value: isHovered)

                    // Hover reveal: approval detail
                    if isHovered, let approvalTooltip = output.approvalTooltip {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.green.opacity(0.85))
                            Text(approvalTooltip)
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundColor(.green.opacity(0.80))
                        }
                        .transition(.opacity.combined(with: .offset(y: 2)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let destination = output.destination, let statusLabel = output.statusLabel {
                    LogDestinationButton(destination: destination, statusLabel: statusLabel)
                        .padding(.leading, 8)
                }
            }
            .padding(.bottom, isLast ? 0 : 8)
        }
        .onHover { isHovered = $0 }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 4)
        .onAppear {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.80).delay(appearDelay)) {
                appeared = true
            }
        }
        .onDisappear { appeared = false }
    }

    private var outputNode: some View {
        ZStack {
            if output.approvalTooltip != nil {
                // Approved: solid green with checkmark
                Circle()
                    .fill(Color.green.opacity(0.82))
                    .frame(width: 9, height: 9)
            } else {
                // Pending / auto: muted white
                Circle()
                    .fill(Color.white.opacity(0.28))
                    .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 0.5))
                    .frame(width: 9, height: 9)
            }
        }
    }
}

// MARK: - Tool icon components

private struct LogToolIconButton: View {
    let tool: LogTool
    @State private var isHovered = false

    var body: some View {
        Button {} label: {
            LogToolIcon(tool: tool, size: 14, backgroundSize: 24)
                .scaleEffect(isHovered ? 1.08 : 1.0)
                .animation(.spring(response: 0.22, dampingFraction: 0.65), value: isHovered)
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .help(tool.name)
        .onHover { isHovered = $0 }
    }
}

private struct LogDestinationButton: View {
    let destination: LogTool
    let statusLabel: String

    @State private var isHovered = false

    var body: some View {
        Button {} label: {
            HStack(spacing: 5) {
                // Icon fills the background square for max clarity
                LogToolIcon(tool: destination, size: 13, backgroundSize: 20)
                Text(statusLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(.white.opacity(isHovered ? 0.82 : 0.62))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(isHovered ? 0.10 : 0.058))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(isHovered ? 0.18 : 0.09), lineWidth: 0.5)
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.70), value: isHovered)
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .help(statusLabel)
        .onHover { isHovered = $0 }
    }
}

private struct LogToolIcon: View {
    let tool: LogTool
    let size: CGFloat
    let backgroundSize: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .frame(width: backgroundSize, height: backgroundSize)

            if let iconURL = tool.iconURL {
                AsyncSVGImage(urlString: iconURL, size: backgroundSize)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else if let systemImage = tool.systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: size, weight: .semibold))
                    .foregroundColor(.white.opacity(0.72))
            }
        }
        .frame(width: backgroundSize, height: backgroundSize)
    }
}
