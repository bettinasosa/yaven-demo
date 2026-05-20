//
//  OnboardingToolsView.swift
//  leanring-buddy
//
//  Step 4 of onboarding — Yaven asks which tools it should know about.
//  Loads the Composio tool catalog from the worker; falls back to a curated
//  list when offline. Tool connections are faked for the demo (no real OAuth).
//

import SwiftUI

// MARK: - Fallback tool list
// Ordered by everyday workplace frequency. Used when the worker is unreachable.
// Logo URLs use Google's favicon service (PNG, no auth, sz=128).

private let fallbackTools: [ComposioTool] = [
    ComposioTool(key: "gmail",           name: "Gmail",             logo: favicon("gmail.com")),
    ComposioTool(key: "googlecalendar",  name: "Google Calendar",   logo: favicon("calendar.google.com")),
    ComposioTool(key: "slack",           name: "Slack",             logo: favicon("slack.com")),
    ComposioTool(key: "microsoft-teams", name: "Microsoft Teams",   logo: favicon("teams.microsoft.com")),
    ComposioTool(key: "outlook",         name: "Outlook",           logo: favicon("outlook.com")),
    ComposioTool(key: "zoom",            name: "Zoom",              logo: favicon("zoom.us")),
    ComposioTool(key: "googledrive",     name: "Google Drive",      logo: favicon("drive.google.com")),
    ComposioTool(key: "googledocs",      name: "Google Docs",       logo: favicon("docs.google.com")),
    ComposioTool(key: "googlesheets",    name: "Google Sheets",     logo: favicon("sheets.google.com")),
    ComposioTool(key: "microsoft-excel", name: "Microsoft Excel",   logo: favicon("excel.office.com")),
    ComposioTool(key: "hubspot",         name: "HubSpot",           logo: favicon("hubspot.com")),
    ComposioTool(key: "notion",          name: "Notion",            logo: favicon("notion.so")),
    ComposioTool(key: "granola",         name: "Granola",           logo: favicon("granola.so")),
    ComposioTool(key: "github",          name: "GitHub",            logo: favicon("github.com")),
    ComposioTool(key: "figma",           name: "Figma",             logo: favicon("figma.com")),
    ComposioTool(key: "jira",            name: "Jira",              logo: favicon("atlassian.com")),
    ComposioTool(key: "salesforce",      name: "Salesforce",        logo: favicon("salesforce.com")),
    ComposioTool(key: "linear",          name: "Linear",            logo: favicon("linear.app")),
    ComposioTool(key: "airtable",        name: "Airtable",          logo: favicon("airtable.com")),
    ComposioTool(key: "asana",           name: "Asana",             logo: favicon("asana.com")),
]

private func favicon(_ domain: String) -> String {
    "https://www.google.com/s2/favicons?domain=\(domain)&sz=128"
}

// MARK: - View

struct OnboardingToolsView: View {
    @ObservedObject var onboardingManager: OnboardingManager

    @State private var allTools: [ComposioTool] = []
    @State private var isLoading = true
    @State private var searchText = ""

    private var currentSuggestedKeys: Set<String> {
        suggestedKeys(for: onboardingManager.userRole)
    }

    private var suggested: [ComposioTool] {
        allTools.filter { currentSuggestedKeys.contains($0.key) && matchesSearch($0) }
    }

    private var others: [ComposioTool] {
        allTools.filter { !currentSuggestedKeys.contains($0.key) && matchesSearch($0) }
    }

    private func matchesSearch(_ tool: ComposioTool) -> Bool {
        searchText.isEmpty || tool.name.localizedCaseInsensitiveContains(searchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            searchBar
                .padding(.horizontal, 32)
                .padding(.bottom, 12)

            if isLoading {
                Spacer()
                ProgressView()
                    .controlSize(.regular)
                    .tint(OnboardingDS.Colors.steelHaze)
                Spacer()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        if !suggested.isEmpty {
                            sectionHeader("Suggested for you")
                            toolRows(suggested)
                        }

                        if !others.isEmpty {
                            sectionHeader(suggested.isEmpty ? "Tools" : "More tools")
                            toolRows(others)
                        }

                        if suggested.isEmpty && others.isEmpty {
                            Text("No tools found")
                                .font(OnboardingDS.Fonts.body(size: 14))
                                .foregroundStyle(OnboardingDS.Colors.steelHaze.opacity(0.6))
                                .padding(.top, 32)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 12)
                }
            }

            Button { onboardingManager.proceedFromTools() } label: {
                Text("Continue")
                    .font(OnboardingDS.Fonts.body(size: 14))
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(OnboardingDS.Colors.skyBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .padding(.horizontal, 34)
            .padding(.bottom, 30)
        }
        .task {
            let loaded = await ToolCatalog.load()
            allTools = loaded.isEmpty ? fallbackTools : loaded
            isLoading = false
            // Pre-warm the icon cache for all tools in parallel so icons are
            // ready before the user scrolls rather than loading on demand.
            let urls = allTools.map(\.logo)
            await withTaskGroup(of: Void.self) { group in
                for urlString in urls {
                    group.addTask(priority: .utility) {
                        guard !urlString.isEmpty,
                              await SVGImageCache.shared.get(urlString) == nil,
                              let url = URL(string: urlString),
                              let (data, _) = try? await URLSession.shared.data(from: url),
                              let img = NSImage(data: data) else { return }
                        await SVGImageCache.shared.set(urlString, image: img)
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(spacing: 8) {
            Text("Let Yaven help you")
                .font(OnboardingDS.Fonts.heading(size: 28))
                .foregroundStyle(OnboardingDS.Colors.cloudCream)
                .multilineTextAlignment(.center)

            Text("Connect the tools Yaven should know about.")
                .font(OnboardingDS.Fonts.body(size: 14))
                .foregroundStyle(OnboardingDS.Colors.steelHaze)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 36)
        .padding(.horizontal, 32)
        .padding(.bottom, 20)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(OnboardingDS.Colors.steelHaze.opacity(0.6))
            TextField("Search tools…", text: $searchText)
                .textFieldStyle(.plain)
                .font(OnboardingDS.Fonts.body(size: 13))
                .foregroundStyle(OnboardingDS.Colors.cloudCream)
                .tint(OnboardingDS.Colors.skyBlue)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(OnboardingDS.Colors.steelHaze.opacity(0.5))
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(OnboardingDS.Colors.glassFill)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(OnboardingDS.Colors.glassBorder, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(OnboardingDS.Colors.steelHaze.opacity(0.55))
            .kerning(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    @ViewBuilder
    private func toolRows(_ tools: [ComposioTool]) -> some View {
        VStack(spacing: 7) {
            ForEach(tools) { tool in
                ToolCard(
                    tool: tool,
                    isConnected: onboardingManager.connectedDemoTools.contains(tool.key)
                ) {
                    withAnimation(OnboardingDS.Animation.standard) {
                        onboardingManager.connectDemoTool(tool.key)
                    }
                }
            }
        }
    }

    // MARK: - Suggestion logic

    private func suggestedKeys(for role: String) -> Set<String> {
        let lower = role.lowercased()
        var keys: Set<String> = ["gmail", "googlecalendar"]

        if lower.contains("sales") || lower.contains("account") || lower.contains("revenue") || lower.contains("bd") {
            keys.formUnion(["hubspot", "salesforce", "granola"])
        }
        if lower.contains("eng") || lower.contains("dev") || lower.contains("product") || lower.contains("pm") {
            keys.formUnion(["github", "linear", "notion", "jira"])
        }
        if lower.contains("ops") || lower.contains("found") || lower.contains("ceo") || lower.contains("chief") {
            keys.formUnion(["notion", "slack", "granola"])
        }
        if lower.contains("design") || lower.contains("ux") { keys.formUnion(["figma", "notion"]) }
        if lower.contains("market") { keys.formUnion(["slack", "hubspot", "airtable"]) }

        return keys
    }
}

// MARK: - Tool Card

private struct ToolCard: View {
    let tool: ComposioTool
    let isConnected: Bool
    let onConnect: () -> Void

    @State private var successScale: CGFloat = 1

    var body: some View {
        HStack(spacing: 12) {
            // Logo
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 34, height: 34)

                AsyncSVGImage(urlString: tool.logo, size: 22)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(tool.name)
                .font(OnboardingDS.Fonts.body(size: 14))
                .fontWeight(.medium)
                .foregroundStyle(OnboardingDS.Colors.cloudCream)
                .lineLimit(1)

            Spacer()

            connectControl
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isConnected ? Color.green.opacity(0.07) : OnboardingDS.Colors.glassFill)
        .clipShape(RoundedRectangle(cornerRadius: OnboardingDS.Layout.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OnboardingDS.Layout.cardRadius, style: .continuous)
                .strokeBorder(
                    isConnected ? Color.green.opacity(0.3) : OnboardingDS.Colors.glassBorder,
                    lineWidth: isConnected ? 1 : 0.5
                )
        )
        .scaleEffect(successScale)
        .onChange(of: isConnected) { _, connected in
            guard connected else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.45)) { successScale = 1.04 }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6).delay(0.15)) { successScale = 1.0 }
        }
    }

    @ViewBuilder
    private var connectControl: some View {
        if isConnected {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.green.opacity(0.85))
                Text("Connected")
                    .font(OnboardingDS.Fonts.body(size: 12))
                    .fontWeight(.medium)
                    .foregroundStyle(Color.green.opacity(0.75))
            }
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        } else {
            Button(action: onConnect) {
                Text("Connect")
                    .font(OnboardingDS.Fonts.body(size: 12))
                    .fontWeight(.semibold)
                    .foregroundStyle(OnboardingDS.Colors.cloudCream)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 6)
                    .background(OnboardingDS.Colors.glassFill)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(OnboardingDS.Colors.glassBorder, lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        }
    }
}
