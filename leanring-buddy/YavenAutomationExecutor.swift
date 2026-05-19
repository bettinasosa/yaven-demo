//
//  YavenAutomationExecutor.swift
//  leanring-buddy
//

import AppKit
import ApplicationServices
import Foundation

@MainActor
final class YavenAutomationExecutor {
    private let context: YavenComputerContext
    private let notificationManager: YavenNotificationManager

    init(context: YavenComputerContext, notificationManager: YavenNotificationManager) {
        self.context = context
        self.notificationManager = notificationManager
    }

    func execute(_ plan: YavenActionPlan) async -> YavenExecutionResult {
        if plan.requiresAccessibility, !WindowPositionManager.hasAccessibilityPermission() {
            WindowPositionManager.requestAccessibilityPermission()
            return .failure("Accessibility permission is required before Yaven can execute UI actions.")
        }

        for step in plan.steps {
            if Task.isCancelled {
                return .failure("Execution was cancelled.", failedStepDescription: step.description)
            }

            let stepResult = await execute(step)
            guard stepResult.succeeded else { return stepResult }
        }

        return .success("Actions completed.")
    }

    private func execute(_ step: YavenActionStep) async -> YavenExecutionResult {
        switch step.type {
        case .activateApp:
            return activateApp(step)
        case .keyboardShortcut:
            return keyboardShortcut(step)
        case .click:
            return click(step)
        case .typeText, .pasteText:
            return pasteText(step)
        case .wait:
            return await wait(step)
        case .notify:
            await notificationManager.send(
                title: "Yaven",
                body: step.message ?? step.description
            )
            return .success()
        }
    }

    private func activateApp(_ step: YavenActionStep) -> YavenExecutionResult {
        let runningApplication = runningApplication(for: step)

        guard let runningApplication else {
            return launchApp(step)
        }

        if #available(macOS 14, *) {
            runningApplication.activate()
        } else {
            runningApplication.activate(options: [.activateIgnoringOtherApps])
        }
        return .success()
    }

    private func launchApp(_ step: YavenActionStep) -> YavenExecutionResult {
        if let bundleIdentifier = step.bundleIdentifier {
            guard YavenOpenCommandResolver.launch(bundleIdentifier: bundleIdentifier) else {
                return .failure("Could not launch the requested app.", failedStepDescription: step.description)
            }
            return .success()
        }

        guard let appName = step.appName,
              YavenOpenCommandResolver.launch(appName: appName) != nil else {
            return .failure("Could not find the requested app to open.", failedStepDescription: step.description)
        }

        return .success()
    }

    private func runningApplication(for step: YavenActionStep) -> NSRunningApplication? {
        if let bundleIdentifier = step.bundleIdentifier,
           let runningApplication = NSWorkspace.shared.runningApplications.first(where: { application in
               application.bundleIdentifier == bundleIdentifier
           }) {
            return runningApplication
        }

        guard let appName = step.appName else { return nil }
        return YavenOpenCommandResolver.runningApplication(matching: appName)
    }

    private func keyboardShortcut(_ step: YavenActionStep) -> YavenExecutionResult {
        guard let key = step.key,
              let keyCode = keyCode(for: key) else {
            return .failure("Keyboard shortcut is missing a supported key.", failedStepDescription: step.description)
        }

        let flags = eventFlags(for: step.modifiers ?? [])
        postKeyboardEvent(keyCode: keyCode, keyDown: true, flags: flags)
        postKeyboardEvent(keyCode: keyCode, keyDown: false, flags: flags)
        return .success()
    }

    private func click(_ step: YavenActionStep) -> YavenExecutionResult {
        guard let screenIndex = step.screenIndex,
              let x = step.x,
              let y = step.y,
              context.screens.indices.contains(screenIndex) else {
            return .failure("Click step is missing valid screen coordinates.", failedStepDescription: step.description)
        }

        let screen = context.screens[screenIndex]
        let point = convertScreenshotPointToGlobalPoint(x: x, y: y, screen: screen)

        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)

        return .success()
    }

    private func pasteText(_ step: YavenActionStep) -> YavenExecutionResult {
        guard let text = step.text, !text.isEmpty else {
            return .failure("Text step is missing text.", failedStepDescription: step.description)
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        postKeyboardEvent(keyCode: 9, keyDown: true, flags: .maskCommand)
        postKeyboardEvent(keyCode: 9, keyDown: false, flags: .maskCommand)
        return .success()
    }

    private func wait(_ step: YavenActionStep) async -> YavenExecutionResult {
        let milliseconds = max(0, min(step.milliseconds ?? 300, 10_000))
        do {
            try await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
            return .success()
        } catch {
            return .failure("Wait step was cancelled.", failedStepDescription: step.description)
        }
    }

    private func convertScreenshotPointToGlobalPoint(
        x: Double,
        y: Double,
        screen: YavenScreenContext
    ) -> CGPoint {
        let displayFrame = screen.displayFrame
        let normalizedX = CGFloat(x) / CGFloat(max(screen.screenshotWidthInPixels, 1))
        let normalizedY = CGFloat(y) / CGFloat(max(screen.screenshotHeightInPixels, 1))

        return CGPoint(
            x: displayFrame.minX + normalizedX * displayFrame.width,
            y: displayFrame.maxY - normalizedY * displayFrame.height
        )
    }

    private func postKeyboardEvent(keyCode: CGKeyCode, keyDown: Bool, flags: CGEventFlags) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: keyDown)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
    }

    private func eventFlags(for modifiers: [String]) -> CGEventFlags {
        modifiers.reduce(CGEventFlags()) { flags, modifier in
            switch modifier.lowercased() {
            case "command", "cmd":
                return flags.union(.maskCommand)
            case "option", "alt":
                return flags.union(.maskAlternate)
            case "control", "ctrl":
                return flags.union(.maskControl)
            case "shift":
                return flags.union(.maskShift)
            default:
                return flags
            }
        }
    }

    private func keyCode(for key: String) -> CGKeyCode? {
        let normalizedKey = key.lowercased()
        let letterCodes: [String: CGKeyCode] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
            "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
            "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37,
            "j": 38, "k": 40, "n": 45, "m": 46
        ]

        if let code = letterCodes[normalizedKey] { return code }

        switch normalizedKey {
        case "return", "enter": return 36
        case "tab": return 48
        case "space": return 49
        case "delete", "backspace": return 51
        case "escape", "esc": return 53
        case "left": return 123
        case "right": return 124
        case "down": return 125
        case "up": return 126
        default: return nil
        }
    }
}
