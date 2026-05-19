//
//  SpaceYHotkeyMonitor.swift
//  leanring-buddy
//

import AppKit
import ApplicationServices

final class SpaceYHotkeyMonitor {
    private let spaceKeyCode: UInt16 = 49
    private let yKeyCode: UInt16 = 16
    private let duplicateTriggerInterval: TimeInterval = 0.35
    private let onHotkeyPressed: @Sendable () -> Void

    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var isSpaceKeyPressed = false
    private var didTriggerForCurrentSpacePress = false
    private var lastTriggerTime: TimeInterval = 0

    init(onHotkeyPressed: @escaping @Sendable () -> Void) {
        self.onHotkeyPressed = onHotkeyPressed
        start()
    }

    deinit {
        stop()
    }

    private func start() {
        requestAccessibilityAccessIfNeeded()

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            _ = self?.handle(event)
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func stop() {
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }

        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }

    private func requestAccessibilityAccessIfNeeded() {
        guard !AXIsProcessTrusted() else { return }

        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary

        if !AXIsProcessTrustedWithOptions(options) {
            print("Yaven: Space+Y needs Accessibility access. Grant it in System Settings, then relaunch Yaven if macOS asks you to.")
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        switch event.type {
        case .keyDown:
            return handleKeyDown(keyCode: event.keyCode)
        case .keyUp:
            handleKeyUp(keyCode: event.keyCode)
            return false
        default:
            return false
        }
    }

    private func handleKeyDown(keyCode: UInt16) -> Bool {
        if keyCode == spaceKeyCode {
            isSpaceKeyPressed = true
            return false
        }

        guard keyCode == yKeyCode, isSpaceKeyPressed, !didTriggerForCurrentSpacePress else { return false }
        guard canTriggerNow() else { return true }

        didTriggerForCurrentSpacePress = true
        onHotkeyPressed()

        // Local monitors can suppress the Y key while Yaven's input is focused.
        // Global monitors are observe-only, so other apps may still receive it.
        return true
    }

    private func canTriggerNow() -> Bool {
        let currentTime = Date.timeIntervalSinceReferenceDate
        guard currentTime - lastTriggerTime >= duplicateTriggerInterval else { return false }

        lastTriggerTime = currentTime
        return true
    }

    private func handleKeyUp(keyCode: UInt16) {
        guard keyCode == spaceKeyCode else { return }
        isSpaceKeyPressed = false
        didTriggerForCurrentSpacePress = false
    }
}
