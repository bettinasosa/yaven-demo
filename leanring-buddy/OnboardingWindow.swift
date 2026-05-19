//
//  OnboardingWindow.swift
//  leanring-buddy
//
//  NSWindow subclass for the three-stage onboarding flow.
//  Uses NSWindow (not NSPanel) so it reliably becomes the key window,
//  which is required by ASWebAuthenticationSession to anchor the
//  Google OAuth sheet from GoogleAuthClient.signIn().
//

import AppKit

final class OnboardingWindow: NSWindow {

    init() {
        let size = NSSize(
            width:  OnboardingDS.Layout.windowWidth,
            height: OnboardingDS.Layout.windowHeight
        )
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Hide the title bar chrome while keeping the standard shadow and
        // window dragging that fullSizeContentView provides.
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true

        // Clear background so the SwiftUI gradient fills the whole surface.
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true

        // Float above normal app windows without occupying all spaces.
        level = .floating
        collectionBehavior = [.moveToActiveSpace]

        // Prevent AppKit from deallocating when closed — we reuse and fade out.
        isReleasedWhenClosed = false
    }

    override var canBecomeKey:  Bool { true }
    override var canBecomeMain: Bool { true }
}
