//
//  YavenComputerContextProvider.swift
//  leanring-buddy
//

import AppKit
import ApplicationServices
import Foundation

@MainActor
enum YavenComputerContextProvider {
    static func makeContext(from captures: [CompanionScreenCapture]) -> YavenComputerContext {
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let bundleIdentifier = frontmostApplication?.bundleIdentifier
        let processIdentifier = frontmostApplication?.processIdentifier

        let activeWindowTitle: String?
        if let processIdentifier {
            activeWindowTitle = focusedWindowTitle(for: processIdentifier)
        } else {
            activeWindowTitle = nil
        }

        let screens = captures.enumerated().map { index, capture in
            YavenScreenContext(
                index: index,
                label: capture.label,
                isCursorScreen: capture.isCursorScreen,
                displayFrame: capture.displayFrame,
                displayWidthInPoints: capture.displayWidthInPoints,
                displayHeightInPoints: capture.displayHeightInPoints,
                screenshotWidthInPixels: capture.screenshotWidthInPixels,
                screenshotHeightInPixels: capture.screenshotHeightInPixels
            )
        }

        return YavenComputerContext(
            frontmostAppName: frontmostApplication?.localizedName ?? "Unknown",
            frontmostBundleIdentifier: bundleIdentifier,
            focusedWindowTitle: activeWindowTitle,
            screens: screens
        )
    }

    private static func focusedWindowTitle(for processIdentifier: pid_t) -> String? {
        guard WindowPositionManager.hasAccessibilityPermission() else { return nil }

        let appElement = AXUIElementCreateApplication(processIdentifier)
        var focusedWindowValue: AnyObject?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        ) == .success else {
            return nil
        }

        var titleValue: AnyObject?
        guard let focusedWindow = focusedWindowValue,
              AXUIElementCopyAttributeValue(
                focusedWindow as! AXUIElement,
                kAXTitleAttribute as CFString,
                &titleValue
              ) == .success else {
            return nil
        }

        return titleValue as? String
    }
}
