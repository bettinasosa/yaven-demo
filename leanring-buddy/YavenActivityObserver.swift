//
//  YavenActivityObserver.swift
//  leanring-buddy
//

import AppKit
import ApplicationServices
import Combine
import Foundation

@MainActor
final class YavenActivityObserver: ObservableObject {
    static let shared = YavenActivityObserver()

    private enum Constants {
        static let defaultsKey = "com.yaven.activityLoggingEnabled"
    }

    @Published private(set) var isEnabled: Bool

    private let store: YavenThreadStore
    private var observer: NSObjectProtocol?
    private var currentEvent: YavenActivityEvent?

    init(store: YavenThreadStore? = nil) {
        self.store = store ?? .shared
        isEnabled = UserDefaults.standard.bool(forKey: Constants.defaultsKey)
    }

    func setEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: Constants.defaultsKey)

        if isEnabled {
            start()
            recordCurrentFrontmostApplication()
        } else {
            stop()
        }
    }

    func startIfEnabled() {
        guard isEnabled else { return }
        start()
        recordCurrentFrontmostApplication()
    }

    func recordActivityEventForTesting(
        appName: String,
        bundleIdentifier: String?,
        windowTitle: String?,
        at date: Date = Date()
    ) {
        guard isEnabled else { return }
        appendCompletedEvent(
            YavenActivityEvent(
                id: UUID(),
                startedAt: date,
                endedAt: nil,
                appName: appName,
                bundleIdentifier: bundleIdentifier,
                windowTitle: windowTitle
            )
        )
    }

    private func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor [self] in
                guard let app else { return }
                self.startEvent(for: app, at: Date())
            }
        }
    }

    private func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
        finishCurrentEvent(at: Date())
    }

    private func recordCurrentFrontmostApplication() {
        guard let application = NSWorkspace.shared.frontmostApplication else { return }
        startEvent(for: application, at: Date())
    }

    private func recordActivation(_ notification: Notification) {
        guard isEnabled,
              let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        startEvent(for: application, at: Date())
    }

    private func startEvent(for application: NSRunningApplication, at date: Date) {
        finishCurrentEvent(at: date)

        currentEvent = YavenActivityEvent(
            id: UUID(),
            startedAt: date,
            endedAt: nil,
            appName: application.localizedName ?? "Unknown",
            bundleIdentifier: application.bundleIdentifier,
            windowTitle: focusedWindowTitle(for: application.processIdentifier)
        )
    }

    private func finishCurrentEvent(at date: Date) {
        guard var event = currentEvent else { return }
        event.endedAt = date
        appendCompletedEvent(event)
        currentEvent = nil
    }

    private func appendCompletedEvent(_ event: YavenActivityEvent) {
        do {
            try store.appendActivityEvent(event)
        } catch {
            print("YavenActivityObserver: could not write activity event: \(error)")
        }
    }

    private func focusedWindowTitle(for processIdentifier: pid_t) -> String? {
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
