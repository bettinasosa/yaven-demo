//
//  OnboardingFormView.swift
//  leanring-buddy
//
//  5-step structured onboarding form. Replaces the Claude interview.
//
//  Step 1 — Preferred name
//  Step 2 — Work context (company / freelance / building / personal) + name field
//  Step 3 — Role (skipped for personal)
//  Step 4 — Tools (Composio catalog, searchable, icon + name)
//  Step 5 — Time sinks (role-filtered chips)
//

import AppKit
import SwiftUI

// MARK: - SVG Image Cache

// AsyncImage can't render SVG on macOS, but NSImage(data:) handles it natively.
// Cache fetched images by URL so the grid doesn't re-fetch on scroll.
actor SVGImageCache {
    static let shared = SVGImageCache()
    private var cache: [String: NSImage] = [:]
    func get(_ key: String) -> NSImage? { cache[key] }
    func set(_ key: String, image: NSImage) { cache[key] = image }
}

struct AsyncSVGImage: View {
    let urlString: String
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                Color.clear.frame(width: size, height: size)
            }
        }
        .task(id: urlString) {
            guard !urlString.isEmpty else { return }
            if let cached = await SVGImageCache.shared.get(urlString) {
                image = cached
                return
            }
            guard let url = URL(string: urlString),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let img = NSImage(data: data) else { return }
            await SVGImageCache.shared.set(urlString, image: img)
            image = img
        }
    }
}

// MARK: - Step Enum

private enum FormStep: Int, CaseIterable {
    case name, workContext, role, tools, timeSinks
}

// MARK: - Root View

struct OnboardingFormView: View {
    @ObservedObject var onboardingManager: OnboardingManager

    // Navigation
    @State private var stepIndex = 0
    @State private var goingForward = true

    // Form data
    @State private var preferredName: String
    @State private var workContext: WorkContext?
    @State private var contextName = ""   // company name or project name
    @State private var selectedRole = ""
    @State private var selectedToolKeys: Set<String> = []
    @State private var selectedTimeSinks: Set<String> = []
    @State private var customTimeSink = ""

    // Tool catalog
    @State private var toolCatalog: [ComposioTool] = []
    @State private var toolSearch = ""
    @State private var isLoadingTools = false

    init(onboardingManager: OnboardingManager, googleName: String) {
        self.onboardingManager = onboardingManager
        let first = googleName.components(separatedBy: " ").first ?? googleName
        self._preferredName = State(initialValue: first)
    }

    // Steps change if personal (no role step)
    private var orderedSteps: [FormStep] {
        workContext == .personal
            ? [.name, .workContext, .tools, .timeSinks]
            : [.name, .workContext, .role, .tools, .timeSinks]
    }

    private var currentStep: FormStep { orderedSteps[stepIndex] }
    private var isLastStep: Bool { stepIndex == orderedSteps.count - 1 }

    private var canAdvance: Bool {
        switch currentStep {
        case .name:        return !preferredName.trimmingCharacters(in: .whitespaces).isEmpty
        case .workContext:
            guard let ctx = workContext else { return false }
            return ctx.needsName ? !contextName.trimmingCharacters(in: .whitespaces).isEmpty : true
        case .role:        return !selectedRole.isEmpty
        case .tools:       return true   // optional
        case .timeSinks:   return true   // optional
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            progressDots
                .padding(.top, 28)
                .padding(.bottom, 20)

            ZStack {
                ForEach(Array(orderedSteps.enumerated()), id: \.offset) { index, step in
                    if index == stepIndex {
                        stepContent(for: step)
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: goingForward ? .trailing : .leading)
                                        .combined(with: .opacity),
                                    removal: .move(edge: goingForward ? .leading : .trailing)
                                        .combined(with: .opacity)
                                )
                            )
                    }
                }
            }
            .animation(OnboardingDS.Animation.standard, value: stepIndex)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            navBar
                .padding(.horizontal, OnboardingDS.Layout.cardPadding)
                .padding(.bottom, 28)
        }
        .task {
            guard toolCatalog.isEmpty else { return }
            isLoadingTools = true
            toolCatalog = await ToolCatalog.load()
            isLoadingTools = false
        }
    }

    // MARK: - Progress Dots

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<orderedSteps.count, id: \.self) { index in
                Capsule()
                    .fill(index == stepIndex
                          ? OnboardingDS.Colors.cloudCream
                          : OnboardingDS.Colors.steelHaze.opacity(0.4))
                    .frame(width: index == stepIndex ? 20 : 6, height: 6)
                    .animation(OnboardingDS.Animation.standard, value: stepIndex)
            }
        }
    }

    // MARK: - Nav Bar

    private var navBar: some View {
        HStack {
            if stepIndex > 0 {
                Button("Back") {
                    goingForward = false
                    stepIndex -= 1
                }
                .buttonStyle(OnboardingSecondaryButtonStyle())
                .pointerCursor(isEnabled: true)
            } else {
                Spacer().frame(width: 80)
            }

            Spacer()

            Button(isLastStep ? "Let's go" : "Continue") {
                advance()
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .keyboardShortcut(.return, modifiers: [])
            .disabled(!canAdvance)
            .pointerCursor(isEnabled: canAdvance)
        }
    }

    // MARK: - Navigation

    private func advance() {
        guard canAdvance else { return }
        if isLastStep {
            submit()
        } else {
            goingForward = true
            stepIndex += 1
        }
    }

    private func submit() {
        let tools = selectedToolKeys.compactMap { key in
            toolCatalog.first { $0.key == key }.map { Tool(name: $0.name, composioKey: $0.key, logo: $0.logo) }
        }
        let sinks = Array(selectedTimeSinks) + (customTimeSink.trimmingCharacters(in: .whitespaces).isEmpty ? [] : [customTimeSink])

        let profile = UserProfile(
            name: preferredName.trimmingCharacters(in: .whitespaces),
            email: onboardingManager.googleProfile?.email ?? "",
            workContext: workContext ?? .personal,
            company: contextName.trimmingCharacters(in: .whitespaces),
            role: selectedRole,
            tools: tools,
            automations: sinks
        )
        onboardingManager.submitFormProfile(profile)
    }

    // MARK: - Step Content Router

    @ViewBuilder
    private func stepContent(for step: FormStep) -> some View {
        switch step {
        case .name:        NameStep(preferredName: $preferredName, onAdvance: advance)
        case .workContext:  WorkContextStep(workContext: $workContext, contextName: $contextName)
        case .role:        RoleStep(selectedRole: $selectedRole, workContext: workContext)
        case .tools:       ToolsStep(
            catalog: toolCatalog,
            isLoading: isLoadingTools,
            selectedRole: selectedRole,
            selectedKeys: $selectedToolKeys,
            search: $toolSearch
        )
        case .timeSinks:   TimeSinksStep(
            selectedRole: selectedRole,
            selectedSinks: $selectedTimeSinks,
            customSink: $customTimeSink
        )
        }
    }
}

// MARK: - Step 1: Name

private struct NameStep: View {
    @Binding var preferredName: String
    var onAdvance: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Hi, I'm Yaven.")
                    .font(OnboardingDS.Fonts.display(size: 34))
                    .foregroundStyle(OnboardingDS.Colors.cloudCream)

                Text("What should I call you?")
                    .font(OnboardingDS.Fonts.body(size: 15))
                    .foregroundStyle(OnboardingDS.Colors.steelHaze)
            }

            TextField("Your name", text: $preferredName)
                .textFieldStyle(.plain)
                .font(OnboardingDS.Fonts.body(size: 16))
                .foregroundStyle(OnboardingDS.Colors.cloudCream)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(OnboardingDS.Colors.glassFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(focused
                            ? OnboardingDS.Colors.skyBlue.opacity(0.6)
                            : OnboardingDS.Colors.glassBorder)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .focused($focused)
                .onSubmit { onAdvance() }

            Spacer()
        }
        .padding(.horizontal, OnboardingDS.Layout.cardPadding)
        .onAppear { focused = true }
    }
}

// MARK: - Step 2: Work Context

private struct WorkContextStep: View {
    @Binding var workContext: WorkContext?
    @Binding var contextName: String
    @FocusState private var nameFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A bit about you.")
                        .font(OnboardingDS.Fonts.display(size: 34))
                        .foregroundStyle(OnboardingDS.Colors.cloudCream)

                    Text("Where does your work happen?")
                        .font(OnboardingDS.Fonts.body(size: 15))
                        .foregroundStyle(OnboardingDS.Colors.steelHaze)
                }

                VStack(spacing: 10) {
                    ForEach(WorkContext.allCases, id: \.self) { ctx in
                        contextRow(ctx)
                    }
                }

                if let ctx = workContext, ctx.needsName {
                    TextField(ctx.namePlaceholder, text: $contextName)
                        .textFieldStyle(.plain)
                        .font(OnboardingDS.Fonts.body(size: 15))
                        .foregroundStyle(OnboardingDS.Colors.cloudCream)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(OnboardingDS.Colors.glassFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(nameFocused
                                    ? OnboardingDS.Colors.skyBlue.opacity(0.6)
                                    : OnboardingDS.Colors.glassBorder)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .focused($nameFocused)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .onAppear { nameFocused = true }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, OnboardingDS.Layout.cardPadding)
            .animation(OnboardingDS.Animation.standard, value: workContext)
        }
    }

    private func contextRow(_ ctx: WorkContext) -> some View {
        let isSelected = workContext == ctx
        return Button(action: {
            withAnimation(OnboardingDS.Animation.standard) {
                if workContext != ctx {
                    contextName = ""
                }
                workContext = ctx
            }
        }) {
            HStack {
                Text(ctx.displayLabel)
                    .font(OnboardingDS.Fonts.body(size: 15))
                    .foregroundStyle(OnboardingDS.Colors.cloudCream)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(OnboardingDS.Colors.cloudCream)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(isSelected ? OnboardingDS.Colors.skyBlue : OnboardingDS.Colors.glassFill)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.clear : OnboardingDS.Colors.glassBorder)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerCursor(isEnabled: true)
    }
}

// MARK: - Step 3: Role

private struct RoleStep: View {
    @Binding var selectedRole: String
    var workContext: WorkContext?
    @State private var customRole = ""
    @FocusState private var customFocused: Bool

    private var question: String {
        switch workContext {
        case .company:   return "What do you do there?"
        case .freelance: return "What kind of work do you take on?"
        case .building:  return "What's your role?"
        default:         return "What kind of work do you do?"
        }
    }

    private var otherIsSelected: Bool {
        selectedRole == "Other" || (!onboardingRoles.dropLast().contains(selectedRole) && !selectedRole.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(question)
                    .font(OnboardingDS.Fonts.display(size: 30))
                    .foregroundStyle(OnboardingDS.Colors.cloudCream)

                Text("Pick the one that fits best.")
                    .font(OnboardingDS.Fonts.body(size: 15))
                    .foregroundStyle(OnboardingDS.Colors.steelHaze)
            }
            .padding(.horizontal, OnboardingDS.Layout.cardPadding)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    FlexibleChipLayout(spacing: 8) {
                        ForEach(onboardingRoles, id: \.self) { role in
                            let isSelected = role == "Other" ? otherIsSelected : selectedRole == role
                            Button(action: { tap(role) }) {
                                Text(role)
                                    .font(OnboardingDS.Fonts.body(size: 13))
                                    .foregroundStyle(OnboardingDS.Colors.cloudCream)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .background(isSelected ? OnboardingDS.Colors.skyBlue : OnboardingDS.Colors.glassFill)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(isSelected ? Color.clear : OnboardingDS.Colors.glassBorder)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .pointerCursor(isEnabled: true)
                        }
                    }

                    if otherIsSelected {
                        TextField("Your role...", text: $customRole)
                            .textFieldStyle(.plain)
                            .font(OnboardingDS.Fonts.body(size: 14))
                            .foregroundStyle(OnboardingDS.Colors.cloudCream)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(OnboardingDS.Colors.glassFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(OnboardingDS.Colors.glassBorder)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .focused($customFocused)
                            .onChange(of: customRole) { _, value in
                                selectedRole = value.trimmingCharacters(in: .whitespaces).isEmpty ? "Other" : value
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .onAppear { customFocused = true }
                    }
                }
                .padding(.horizontal, OnboardingDS.Layout.cardPadding)
                .padding(.bottom, 8)
            }
            .animation(OnboardingDS.Animation.standard, value: otherIsSelected)
        }
    }

    private func tap(_ role: String) {
        if role == "Other" {
            selectedRole = customRole.trimmingCharacters(in: .whitespaces).isEmpty ? "Other" : customRole
        } else {
            selectedRole = selectedRole == role ? "" : role
            customRole = ""
        }
    }
}

// MARK: - Step 4: Tools

private struct ToolsStep: View {
    let catalog: [ComposioTool]
    let isLoading: Bool
    let selectedRole: String
    @Binding var selectedKeys: Set<String>
    @Binding var search: String

    @State private var debouncedSearch = ""
    @State private var debounceTask: Task<Void, Never>? = nil

    private var suggestedTools: [ComposioTool] {
        let names = toolNamesByRole[selectedRole] ?? toolNamesByRole["Other"] ?? []
        return names.compactMap { name in
            catalog.first { $0.name.localizedCaseInsensitiveContains(name) }
        }
    }

    private var suggestedKeys: Set<String> { Set(suggestedTools.map { $0.key }) }

    // Stable sorted list of selected tools for the strip (alphabetical by name).
    private var selectedToolsSorted: [ComposioTool] {
        selectedKeys
            .compactMap { key in catalog.first { $0.key == key } }
            .sorted { $0.name < $1.name }
    }

    private var displayedTools: [ComposioTool] {
        if !debouncedSearch.isEmpty {
            // Search full catalog; put role-suggested results first.
            // Cap at 50 to avoid firing hundreds of concurrent SVG fetches.
            let filtered = catalog
                .filter { $0.name.localizedCaseInsensitiveContains(debouncedSearch) }
                .sorted { a, b in
                    let aS = suggestedKeys.contains(a.key)
                    let bS = suggestedKeys.contains(b.key)
                    if aS != bS { return aS }
                    return a.name < b.name
                }
            return Array(filtered.prefix(50))
        }
        // Default: role-relevant tools only — keeps the list short and avoids
        // firing 1000+ concurrent SVG fetches.
        return suggestedTools
    }

    private var selectedStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(selectedToolsSorted) { tool in
                    HStack(spacing: 5) {
                        Text(tool.name)
                            .font(OnboardingDS.Fonts.body(size: 12))
                            .foregroundStyle(OnboardingDS.Colors.cloudCream)
                        Button(action: { selectedKeys.remove(tool.key) }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(OnboardingDS.Colors.steelHaze)
                        }
                        .buttonStyle(.plain)
                        .pointerCursor(isEnabled: true)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(OnboardingDS.Colors.skyBlue.opacity(0.25))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(OnboardingDS.Colors.skyBlue.opacity(0.5))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .padding(.horizontal, OnboardingDS.Layout.cardPadding)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What's in your stack?")
                    .font(OnboardingDS.Fonts.display(size: 30))
                    .foregroundStyle(OnboardingDS.Colors.cloudCream)

                Text("Select all that apply.")
                    .font(OnboardingDS.Fonts.body(size: 15))
                    .foregroundStyle(OnboardingDS.Colors.steelHaze)
            }
            .padding(.horizontal, OnboardingDS.Layout.cardPadding)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(OnboardingDS.Colors.steelHaze)
                TextField("Search tools...", text: $search)
                    .textFieldStyle(.plain)
                    .font(OnboardingDS.Fonts.body(size: 14))
                    .foregroundStyle(OnboardingDS.Colors.cloudCream)
                if !search.isEmpty {
                    Button(action: {
                        search = ""
                        debouncedSearch = ""
                        debounceTask?.cancel()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(OnboardingDS.Colors.steelHaze)
                    }
                    .buttonStyle(.plain)
                    .pointerCursor(isEnabled: true)
                    .transition(.opacity)
                }
            }
            .animation(OnboardingDS.Animation.standard, value: search.isEmpty)
            .onChange(of: search) { _, value in
                debounceTask?.cancel()
                if value.isEmpty {
                    debouncedSearch = ""
                } else {
                    debounceTask = Task {
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        guard !Task.isCancelled else { return }
                        debouncedSearch = value
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(OnboardingDS.Colors.glassFill)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(OnboardingDS.Colors.glassBorder)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, OnboardingDS.Layout.cardPadding)

            if !selectedKeys.isEmpty {
                selectedStrip
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                        .tint(OnboardingDS.Colors.steelHaze)
                    Spacer()
                }
                .padding(.top, 20)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 130, maximum: 180))],
                        spacing: 8
                    ) {
                        ForEach(displayedTools) { tool in
                            ToolChip(
                                tool: tool,
                                isSelected: selectedKeys.contains(tool.key),
                                isSuggested: suggestedKeys.contains(tool.key)
                            ) {
                                if selectedKeys.contains(tool.key) {
                                    selectedKeys.remove(tool.key)
                                } else {
                                    selectedKeys.insert(tool.key)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, OnboardingDS.Layout.cardPadding)
                    .padding(.bottom, 8)
                }
            }
        }
        .animation(OnboardingDS.Animation.standard, value: selectedKeys)
    }
}

// MARK: - Tool Chip

private struct ToolChip: View {
    let tool: ComposioTool
    let isSelected: Bool
    let isSuggested: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 7) {
                // White background so transparent-background SVG logos render cleanly.
                ZStack {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.white)
                        .frame(width: 16, height: 16)
                    if !tool.logo.isEmpty {
                        AsyncSVGImage(urlString: tool.logo, size: 14)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

                Text(tool.name)
                    .font(OnboardingDS.Fonts.body(size: 12))
                    .foregroundStyle(OnboardingDS.Colors.cloudCream)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected
                    ? OnboardingDS.Colors.skyBlue
                    : (isSuggested
                        ? Color.white.opacity(0.1)
                        : OnboardingDS.Colors.glassFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.clear :
                        isSuggested ? OnboardingDS.Colors.steelHaze.opacity(0.35) :
                        OnboardingDS.Colors.glassBorder
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerCursor(isEnabled: true)
    }
}

// MARK: - Step 5: Time Sinks

private struct TimeSinksStep: View {
    let selectedRole: String
    @Binding var selectedSinks: Set<String>
    @Binding var customSink: String
    @State private var showCustomField = false
    @FocusState private var customFocused: Bool

    private var options: [String] {
        timeSinksByRole[selectedRole] ?? timeSinksByRole["Other"] ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What eats your time?")
                    .font(OnboardingDS.Fonts.display(size: 30))
                    .foregroundStyle(OnboardingDS.Colors.cloudCream)

                Text("Select everything that applies.")
                    .font(OnboardingDS.Fonts.body(size: 15))
                    .foregroundStyle(OnboardingDS.Colors.steelHaze)
            }
            .padding(.horizontal, OnboardingDS.Layout.cardPadding)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    FormChipGrid(
                        options: options,
                        selected: selectedSinks,
                        multiSelect: true
                    ) { sink in
                        if selectedSinks.contains(sink) {
                            selectedSinks.remove(sink)
                        } else {
                            selectedSinks.insert(sink)
                        }
                    }

                    // Other option
                    Button(action: {
                        withAnimation(OnboardingDS.Animation.standard) {
                            showCustomField.toggle()
                            if !showCustomField { customSink = "" }
                        }
                    }) {
                        Text("+ Something else")
                            .font(OnboardingDS.Fonts.body(size: 13))
                            .foregroundStyle(showCustomField
                                ? OnboardingDS.Colors.cloudCream
                                : OnboardingDS.Colors.steelHaze)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(showCustomField
                                ? OnboardingDS.Colors.glassFill
                                : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(OnboardingDS.Colors.glassBorder.opacity(showCustomField ? 1 : 0.5))
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .pointerCursor(isEnabled: true)

                    if showCustomField {
                        TextField("Describe it briefly...", text: $customSink)
                            .textFieldStyle(.plain)
                            .font(OnboardingDS.Fonts.body(size: 14))
                            .foregroundStyle(OnboardingDS.Colors.cloudCream)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(OnboardingDS.Colors.glassFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(OnboardingDS.Colors.glassBorder)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .focused($customFocused)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .onAppear { customFocused = true }
                    }
                }
                .padding(.horizontal, OnboardingDS.Layout.cardPadding)
                .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Shared Chip Grid

private struct FormChipGrid: View {
    let options: [String]
    let selected: Set<String>
    let multiSelect: Bool
    let onTap: (String) -> Void

    var body: some View {
        FlexibleChipLayout(spacing: 8) {
            ForEach(options, id: \.self) { option in
                let isSelected = selected.contains(option)
                Button(action: { onTap(option) }) {
                    Text(option)
                        .font(OnboardingDS.Fonts.body(size: 13))
                        .foregroundStyle(OnboardingDS.Colors.cloudCream)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(isSelected ? OnboardingDS.Colors.skyBlue : OnboardingDS.Colors.glassFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(isSelected ? Color.clear : OnboardingDS.Colors.glassBorder)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .pointerCursor(isEnabled: true)
            }
        }
    }
}

// MARK: - Flexible Chip Layout

/// A layout that wraps chips onto new rows, left-aligned, like CSS flexbox wrap.
private struct FlexibleChipLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > width, rowWidth > 0 {
                height += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Button Styles

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OnboardingDS.Fonts.body(size: 14).weight(.medium))
            .foregroundStyle(OnboardingDS.Colors.cloudCream)
            .padding(.horizontal, 32)
            .padding(.vertical, 11)
            .background(OnboardingDS.Colors.skyBlue.opacity(configuration.isPressed ? 0.8 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
            )
    }
}

private struct OnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OnboardingDS.Fonts.body(size: 14))
            .foregroundStyle(OnboardingDS.Colors.steelHaze)
            .padding(.horizontal, 32)
            .padding(.vertical, 11)
            .background(OnboardingDS.Colors.glassFill.opacity(configuration.isPressed ? 0.5 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
