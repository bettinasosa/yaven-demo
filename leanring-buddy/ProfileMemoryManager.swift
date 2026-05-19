//
//  ProfileMemoryManager.swift
//  leanring-buddy
//
//  Owns the user memory layer.
//
//  Signal writes land in signals.jsonl via YavenStorage, then trigger a
//  debounced background Claude call (Haiku) that rewrites user-profile.json
//  to reflect what the signals reveal. Only one rewrite runs at a time;
//  signals that arrive during a rewrite schedule a follow-up pass.
//
//  CompanionManager reads user-profile.json directly via YavenStorage —
//  no reference to this manager is needed for reads.
//

import Foundation

@MainActor
final class ProfileMemoryManager {
    #if DEBUG
    private static let workerBaseURL = "http://localhost:8787"
    #else
    private static let workerBaseURL = "https://yaven-proxy.nickprice2000.workers.dev"
    #endif
    private static let debounceSeconds: TimeInterval = 30

    private let claudeAPI = ClaudeAPI(
        proxyURL: "\(workerBaseURL)/chat",
        model: "claude-haiku-4-5-20251001"
    )

    private var debounceTask: Task<Void, Never>?
    private var rewriteRunning = false
    private var rewriteNeededAfterCurrent = false

    // MARK: - Onboarding Bootstrap

    /// Writes the first profile from onboarding data without calling Claude.
    /// Called once when the interview stage completes.
    func initializeFromOnboardingProfile(_ profile: UserProfile) {
        let workDescription: String = {
            switch profile.workContext {
            case .company:   return "works at \(profile.company)"
            case .freelance: return "freelances / consults"
            case .building:  return "is building \(profile.company)"
            case .personal:  return "uses Yaven personally"
            }
        }()

        let roleLine = profile.role.isEmpty ? "" : "\nRole: \(profile.role)"
        let toolsSummary = profile.tools.map { $0.name }.joined(separator: ", ")
        let automationsSummary = profile.automations.joined(separator: "; ")

        let text = """
        \(profile.name) \(workDescription).\(roleLine)

        Tools: \(toolsSummary.isEmpty ? "not specified" : toolsSummary)

        Wants to automate: \(automationsSummary.isEmpty ? "not specified" : automationsSummary)
        """

        YavenStorage.writeProfileText(text)
        print("Yaven: Profile initialised from onboarding.")
    }

    // MARK: - Signal Recording

    /// Appends a signal to the log and schedules a profile rewrite.
    func recordSignal(_ signal: Signal) {
        YavenStorage.appendSignal(signal)
        if rewriteRunning {
            rewriteNeededAfterCurrent = true
        } else {
            scheduleDebounce()
        }
    }

    // MARK: - Debounced Rewrite

    private func scheduleDebounce() {
        debounceTask?.cancel()
        debounceTask = Task {
            let nanoseconds = UInt64(Self.debounceSeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await self.runRewrite()
        }
    }

    private func runRewrite() async {
        guard !rewriteRunning else { return }
        rewriteRunning = true
        rewriteNeededAfterCurrent = false

        defer {
            rewriteRunning = false
            if rewriteNeededAfterCurrent {
                scheduleDebounce()
            }
        }

        let currentProfile = YavenStorage.readProfileText() ?? ""
        let recentSignals = YavenStorage.readRecentSignals(limit: 50)
        guard !recentSignals.isEmpty else { return }

        let systemPrompt = """
        You maintain a concise profile of a Yaven user. The profile is prepended to \
        every AI call as context about who the user is and how they work.

        Rules:
        - Stay under 300 words.
        - Write in third person, plain prose.
        - Focus on what helps tailor AI outputs: role, working style, communication \
        preferences, and patterns in what the user accepts, edits, or rejects.
        - Preserve accurate existing information. Only update or add based on the \
        signals below.
        - Return only the updated profile text. No preamble, no labels, no explanation.
        """

        let userPrompt = """
        Current profile:
        \(currentProfile.isEmpty ? "(none yet)" : currentProfile)

        Recent signals:
        \(formatSignalsForPrompt(recentSignals))

        Return the updated profile.
        """

        print("Yaven: Rewriting profile from \(recentSignals.count) signal(s)...")

        do {
            let (updatedProfile, _) = try await claudeAPI.analyzeImageStreaming(
                images: [],
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                onTextChunk: { _ in }
            )
            let trimmed = updatedProfile.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                YavenStorage.writeProfileText(trimmed)
                print("Yaven: Profile rewritten.")
            }
        } catch {
            print("Yaven: Profile rewrite failed: \(error)")
        }
    }

    // MARK: - Formatting

    private func formatSignalsForPrompt(_ signals: [Signal]) -> String {
        let formatter = ISO8601DateFormatter()
        return signals.map { signal in
            var entry = "[\(formatter.string(from: signal.timestamp))] \(signal.type.rawValue) — \(signal.action.rawValue)"
            if !signal.context.isEmpty {
                entry += "\n  context: \(signal.context)"
            }
            entry += "\n  yaven: \(signal.yavenOutput)"
            if signal.action == .edited && !signal.finalOutput.isEmpty {
                entry += "\n  edited to: \(signal.finalOutput)"
            }
            return entry
        }.joined(separator: "\n\n")
    }
}
