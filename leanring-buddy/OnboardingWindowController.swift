//
//  OnboardingWindowController.swift
//  leanring-buddy
//
//  Owns the OnboardingWindow and its SwiftUI hosting view. Observes
//  OnboardingManager.$stage via Combine and fades the window out when
//  onboarding reaches .complete, then fires the shell-start callback.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class OnboardingWindowController {

    private let window: OnboardingWindow
    private let onboardingManager: OnboardingManager
    private let onComplete: () -> Void
    private var stageCancellable: AnyCancellable?
    private var signingInCancellable: AnyCancellable?
    private let fullWindowLevel: NSWindow.Level = .floating

    /// - Parameters:
    ///   - onboardingManager: The shared manager driven by the backend.
    ///   - onComplete: Called once onboarding reaches .complete and the window has faded out.
    ///                 Use this to start the shell (shellController.start()).
    init(
        onboardingManager: OnboardingManager,
        arrivalCoordinator: OnboardingArrivalCoordinator,
        onComplete: @escaping () -> Void
    ) {
        self.onboardingManager = onboardingManager
        self.onComplete = onComplete
        self.window = OnboardingWindow()

        let rootView = OnboardingRootView(
            onboardingManager: onboardingManager,
            arrivalCoordinator: arrivalCoordinator
        )
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.autoresizingMask = [.width, .height]
        // Prevent NSHostingView from resizing the window to match the SwiftUI
        // view's ideal size. Without this, any SwiftUI content change (e.g.
        // isSigningInWithGoogle toggling) forces the window back to full size,
        // overriding the collapse animation.
        if #available(macOS 13, *) {
            hostingView.sizingOptions = []
        }
        window.contentView = hostingView

        observeStageCompletion()
        wireSignInCallbacks()
    }

    func show() {
        window.center()
        // Activate the app before ordering front so the window becomes the
        // key window. Required for ASWebAuthenticationSession to find a valid
        // presentation anchor via NSApp.keyWindow in GoogleAuthClient.signIn().
        // LSUIElement apps are not active by default; without this the OAuth
        // sheet silently cancels.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Stage Observation

    private func wireSignInCallbacks() {
        // Synchronous callbacks so the window moves BEFORE the OAuth sheet appears.
        onboardingManager.willStartSignIn = { [weak self] in
            self?.collapseForSignIn()
        }
        onboardingManager.didFinishSignIn = { [weak self] in
            self?.expandAfterSignIn()
        }

        // Hide the onboarding window while the user completes Composio OAuth in the browser,
        // then restore it when polling finishes (connected or timed out).
        onboardingManager.willStartConnect = { [weak self] in
            self?.collapseForSignIn()
        }
        onboardingManager.didFinishConnect = { [weak self] in
            self?.expandAfterSignIn()
        }
    }

    private func collapseForSignIn() {
        let currentFrame = window.frame
        let raisedFrame = currentFrame.offsetBy(dx: 0, dy: 60)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(raisedFrame, display: true)
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.window.orderOut(nil)
            self?.window.setFrame(currentFrame, display: false)
            self?.window.alphaValue = 1
        }
    }

    private func expandAfterSignIn() {
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }

    private func observeStageCompletion() {
        stageCancellable = onboardingManager.$stage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stage in
                guard stage == .complete else { return }
                self?.dismiss()
            }
    }

    private func dismiss() {
        let capturedWindow = window
        let capturedOnComplete = onComplete
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            capturedWindow.animator().alphaValue = 0
        } completionHandler: {
            capturedWindow.orderOut(nil)
            capturedWindow.alphaValue = 1
            capturedOnComplete()
        }
    }
}
