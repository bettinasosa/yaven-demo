//
//  YavenGateway.swift
//  leanring-buddy
//

import Foundation

enum YavenGatewayIntent: String, Codable, Equatable {
    case directOpen
    case mailCleanup
    case crmUpdate
    case operatorPlan
    case research
    case chat
}

struct YavenGatewayRoute: Equatable {
    let intent: YavenGatewayIntent
    let threadKind: YavenThreadKind
    let title: String
    let requiresScreenCapture: Bool
    let openTarget: YavenOpenTarget?
}

struct YavenGateway {
    func route(command: String) -> YavenGatewayRoute {
        if shouldRunMailCleanup(for: command) {
            return YavenGatewayRoute(
                intent: .mailCleanup,
                threadKind: .cleanup,
                title: title(for: command),
                requiresScreenCapture: false,
                openTarget: nil
            )
        }

        if shouldGenerateCRMPlan(for: command) {
            return YavenGatewayRoute(
                intent: .crmUpdate,
                threadKind: .crm,
                title: title(for: command),
                requiresScreenCapture: true,
                openTarget: nil
            )
        }

        if let openTarget = YavenOpenCommandResolver.openTarget(from: command) {
            return YavenGatewayRoute(
                intent: .directOpen,
                threadKind: .automation,
                title: title(for: command),
                requiresScreenCapture: false,
                openTarget: openTarget
            )
        }

        if shouldGenerateResearchArtifact(for: command) {
            return YavenGatewayRoute(
                intent: .research,
                threadKind: .research,
                title: title(for: command),
                requiresScreenCapture: false,
                openTarget: nil
            )
        }

        if shouldGenerateOperatorPlan(for: command) {
            return YavenGatewayRoute(
                intent: .operatorPlan,
                threadKind: fallbackThreadKind(for: command),
                title: title(for: command),
                requiresScreenCapture: true,
                openTarget: nil
            )
        }

        return YavenGatewayRoute(
            intent: .chat,
            threadKind: fallbackThreadKind(for: command),
            title: title(for: command),
            requiresScreenCapture: true,
            openTarget: nil
        )
    }

    func blockedSensitiveActionMessage(for text: String) -> String? {
        containsBlockedSensitiveInstruction(text)
            ? "Yaven cannot enter passwords, payment details, or system security prompts."
            : nil
    }

    func isApprovalCommand(_ command: String) -> Bool {
        let normalizedCommand = command.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let approvalCommands = ["yes", "y", "approve", "approved", "go ahead", "do it", "run it", "execute", "looks good"]
        return approvalCommands.contains(normalizedCommand)
    }

    func isCancelCommand(_ command: String) -> Bool {
        let normalizedCommand = command.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let cancelCommands = ["no", "n", "cancel", "stop", "never mind", "nevermind", "don't", "do not"]
        return cancelCommands.contains(normalizedCommand)
    }

    func shouldExecuteWithoutApproval(plan: YavenActionPlan, command: String) -> Bool {
        let normalizedCommand = command
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if isSimpleOpenCommand(normalizedCommand),
           plan.steps.allSatisfy({ $0.type == .activateApp || $0.type == .wait || $0.type == .notify }) {
            return true
        }

        if normalizedCommand.hasPrefix("send ") || normalizedCommand.contains(" send ") {
            return !containsBlockedSensitiveInstruction(plan.draftText ?? "") && plan.risk != .high
        }

        return false
    }

    func validate(plan: YavenActionPlan, context: YavenComputerContext) throws {
        guard !plan.steps.isEmpty else {
            throw validationError("Claude returned a plan with no executable steps.")
        }

        for step in plan.steps {
            switch step.type {
            case .activateApp:
                guard step.appName != nil || step.bundleIdentifier != nil else {
                    throw validationError("An activate-app step is missing the app name or bundle identifier.")
                }
            case .keyboardShortcut:
                guard step.key != nil else {
                    throw validationError("A keyboard shortcut step is missing its key.")
                }
            case .click:
                guard let screenIndex = step.screenIndex,
                      context.screens.indices.contains(screenIndex),
                      step.x != nil,
                      step.y != nil else {
                    throw validationError("A click step is missing valid screen coordinates.")
                }
            case .typeText, .pasteText:
                guard let text = step.text, !text.isEmpty else {
                    throw validationError("A text step is missing text.")
                }
                guard !containsBlockedSensitiveInstruction(text) else {
                    throw validationError("Yaven cannot type passwords, payment details, or security codes.")
                }
            case .wait:
                guard step.milliseconds != nil else {
                    throw validationError("A wait step is missing a duration.")
                }
            case .notify:
                guard step.message != nil else {
                    throw validationError("A notification step is missing a message.")
                }
            }
        }
    }

    private func fallbackThreadKind(for command: String) -> YavenThreadKind {
        let normalizedCommand = command.lowercased()
        if normalizedCommand.contains("hubspot") ||
            normalizedCommand.contains("crm") ||
            normalizedCommand.contains("deal") ||
            normalizedCommand.contains("contact") {
            return .crm
        }
        if normalizedCommand.contains("clean up") ||
            normalizedCommand.contains("archive") ||
            normalizedCommand.contains("organize") ||
            normalizedCommand.contains("organise") {
            return .automation
        }
        if shouldGenerateResearchArtifact(for: command) { return .research }
        return shouldGenerateOperatorPlan(for: command) ? .automation : .chat
    }

    private func title(for command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 52 else { return trimmed }
        let index = trimmed.index(trimmed.startIndex, offsetBy: 49)
        return String(trimmed[..<index]) + "..."
    }

    private func shouldGenerateResearchArtifact(for command: String) -> Bool {
        let lowercased = command.lowercased()
        // These phrases signal the user wants a structured, in-depth output — worth an artifact
        let researchPhrases = [
            "research ", "deep dive", "in depth", "in-depth",
            "compare ", "comparison of", "pros and cons",
            "analyze ", "analyse ", "analysis of",
            "breakdown of", "break down ",
            "comprehensive ", "detailed overview", "full overview",
            "give me an overview", "give me a full",
            "create a report", "write a report", "create a summary",
            "write a summary", "write up on", "write up about",
            "everything about", "tell me everything",
            "look up ", "look into "
        ]
        return researchPhrases.contains { lowercased.contains($0) }
    }

    private func shouldGenerateOperatorPlan(for command: String) -> Bool {
        let lowercased = command.lowercased()

        // Fast-path: informational requests must never generate automation plans.
        // These phrases indicate the user wants a response, not computer control.
        let informationalPrefixes = [
            "what is ", "what are ", "what's ", "what were ", "what was ",
            "how do ", "how does ", "how to ", "how can ",
            "why is ", "why are ", "why does ", "why did ",
            "tell me ", "show me ", "give me ", "help me think", "help me understand",
            "explain ", "describe ", "compare ", "analyze ", "analyse ",
            "summarize ", "summarise ",
            "write me ", "draft me ", "make me ",
            "find me ", "find information", "find out ",
            "suggest ", "recommend ", "list the ", "list of "
        ]
        if informationalPrefixes.contains(where: { lowercased.hasPrefix($0) }) { return false }

        // These verbs indicate the user wants Yaven to physically control the computer
        let actionPhrases = [
            "click", "switch", "open", "launch", "bring up", "go to", "navigate",
            "press", "type", "paste", "write", "draft", "reply", "respond",
            "send", "delete", "archive", "schedule", "create", "fill", "edit",
            "accept", "execute", "do this", "do it", "take action", "run this",
            "select", "scroll", "close", "move", "organize",
            "organise", "sort", "clean up", "add ", "start",
            "next tab", "previous tab", "new tab",
            "save", "submit"
        ]
        return actionPhrases.contains { lowercased.contains($0) }
    }

    private func shouldRunMailCleanup(for command: String) -> Bool {
        let lowercasedCommand = command.lowercased()
        let mailTerms = [
            "email", "emails", "mail", "inbox", "newsletter", "newsletters",
            "promotion", "promotions", "receipt", "receipts"
        ]
        let cleanupTerms = [
            "clean", "clean up", "cleanup", "sort", "organize", "organise",
            "archive", "declutter", "file", "triage"
        ]
        return mailTerms.contains { lowercasedCommand.contains($0) } &&
            cleanupTerms.contains { lowercasedCommand.contains($0) }
    }

    private func shouldGenerateCRMPlan(for command: String) -> Bool {
        let lowercasedCommand = command.lowercased()
        guard lowercasedCommand.contains("hubspot") || lowercasedCommand.contains("crm") else {
            return false
        }
        let crmWritePhrases = [
            "update", "log", "create", "add", "note", "task", "follow up",
            "follow-up", "deal stage", "move deal", "record", "sync"
        ]
        return crmWritePhrases.contains { lowercasedCommand.contains($0) }
    }

    private func containsBlockedSensitiveInstruction(_ text: String) -> Bool {
        let lowercasedText = text.lowercased()
        let blockedTerms = [
            "password", "passcode", "security code", "2fa", "two-factor",
            "credit card", "card number", "cvv", "social security"
        ]
        return blockedTerms.contains { lowercasedText.contains($0) }
    }

    private func isSimpleOpenCommand(_ normalizedCommand: String) -> Bool {
        let openPrefixes = [
            "open ",
            "launch ",
            "start ",
            "bring up "
        ]
        return openPrefixes.contains { normalizedCommand.hasPrefix($0) }
    }

    private func validationError(_ message: String) -> NSError {
        NSError(domain: "YavenGatewayPolicy", code: 1, userInfo: [
            NSLocalizedDescriptionKey: message
        ])
    }
}
