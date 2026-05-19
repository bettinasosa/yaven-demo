//
//  YavenAgentModels.swift
//  leanring-buddy
//

import CoreGraphics
import Foundation

enum YavenAgentState: Equatable {
    case idle
    case thinking
    case answering
    case planning
    case approvalRequired
    case executing
    case done
    case error
}

enum YavenChatRole: String, Codable {
    case user
    case assistant
}

struct YavenChatMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let role: YavenChatRole
    var text: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        role: YavenChatRole,
        text: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

struct YavenScreenContext: Codable {
    let index: Int
    let label: String
    let isCursorScreen: Bool
    let displayFrame: CGRect
    let displayWidthInPoints: Int
    let displayHeightInPoints: Int
    let screenshotWidthInPixels: Int
    let screenshotHeightInPixels: Int
}

struct YavenComputerContext: Codable {
    let frontmostAppName: String
    let frontmostBundleIdentifier: String?
    let focusedWindowTitle: String?
    let screens: [YavenScreenContext]

    var promptSummary: String {
        var lines = [
            "Frontmost app: \(frontmostAppName)",
            "Bundle identifier: \(frontmostBundleIdentifier ?? "unknown")",
            "Focused window: \(focusedWindowTitle ?? "unknown")"
        ]

        for screen in screens {
            lines.append(
                "Screen \(screen.index): \(screen.label), display frame \(screen.displayFrame), display points \(screen.displayWidthInPoints)x\(screen.displayHeightInPoints), screenshot pixels \(screen.screenshotWidthInPixels)x\(screen.screenshotHeightInPixels)"
            )
        }

        return lines.joined(separator: "\n")
    }
}

enum YavenActionRisk: String, Codable {
    case low
    case medium
    case high
}

enum YavenActionStepType: String, Codable {
    case activateApp
    case keyboardShortcut
    case click
    case typeText
    case pasteText
    case wait
    case notify
}

struct YavenActionStep: Codable, Identifiable {
    var id = UUID()
    let type: YavenActionStepType
    let description: String
    let appName: String?
    let bundleIdentifier: String?
    let key: String?
    let modifiers: [String]?
    let screenIndex: Int?
    let x: Double?
    let y: Double?
    let text: String?
    let milliseconds: Int?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case type
        case description
        case appName
        case bundleIdentifier
        case key
        case modifiers
        case screenIndex
        case x
        case y
        case text
        case milliseconds
        case message
    }
}

struct YavenActionPlan: Codable, Identifiable {
    var id = UUID()
    let goal: String
    let targetAppName: String?
    let targetWindowTitle: String?
    let risk: YavenActionRisk
    let draftText: String?
    let summary: String
    let followUpPrompt: String?
    let steps: [YavenActionStep]

    enum CodingKeys: String, CodingKey {
        case goal
        case targetAppName
        case targetWindowTitle
        case risk
        case draftText
        case summary
        case followUpPrompt
        case steps
    }
}

extension YavenActionPlan {
    var requiresAccessibility: Bool {
        steps.contains { step in
            switch step.type {
            case .click, .keyboardShortcut, .typeText, .pasteText:
                return true
            case .activateApp, .wait, .notify:
                return false
            }
        }
    }
}

struct YavenExecutionResult: Equatable {
    let succeeded: Bool
    let message: String
    let failedStepDescription: String?

    static func success(_ message: String = "Execution complete.") -> YavenExecutionResult {
        YavenExecutionResult(succeeded: true, message: message, failedStepDescription: nil)
    }

    static func failure(_ message: String, failedStepDescription: String? = nil) -> YavenExecutionResult {
        YavenExecutionResult(succeeded: false, message: message, failedStepDescription: failedStepDescription)
    }
}

// MARK: - Proactive suggestions

struct YavenProactiveSuggestion: Identifiable {
    enum Confidence {
        case high
        case needsReview
        case low
    }
    let id: UUID
    let title: String
    let confidence: Confidence

    init(id: UUID = UUID(), title: String, confidence: Confidence) {
        self.id = id
        self.title = title
        self.confidence = confidence
    }
}

enum YavenActionPlanParser {
    static func decodePlan(from responseText: String) throws -> YavenActionPlan {
        let jsonText = try extractJSONObject(from: responseText)
        guard let data = jsonText.data(using: .utf8) else {
            throw NSError(domain: "YavenActionPlanParser", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Claude returned a plan that could not be converted to UTF-8."
            ])
        }

        return try JSONDecoder().decode(YavenActionPlan.self, from: data)
    }

    private static func extractJSONObject(from responseText: String) throws -> String {
        if let fencedRange = responseText.range(of: #"```(?:json)?\s*(\{[\s\S]*?\})\s*```"#, options: .regularExpression) {
            var fenced = String(responseText[fencedRange])
            fenced = fenced.replacingOccurrences(of: #"^```(?:json)?\s*"#, with: "", options: .regularExpression)
            fenced = fenced.replacingOccurrences(of: #"\s*```$"#, with: "", options: .regularExpression)
            return fenced
        }

        guard let firstBrace = responseText.firstIndex(of: "{"),
              let lastBrace = responseText.lastIndex(of: "}") else {
            throw NSError(domain: "YavenActionPlanParser", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "Claude did not return a JSON action plan."
            ])
        }

        return String(responseText[firstBrace...lastBrace])
    }
}
