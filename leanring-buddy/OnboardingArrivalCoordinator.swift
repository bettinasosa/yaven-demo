//
//  OnboardingArrivalCoordinator.swift
//  leanring-buddy
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class OnboardingArrivalCoordinator: ObservableObject {
    @Published private(set) var state: OnboardingArrivalState = .fadingOutOnboarding
    @Published var washOpacity: Double = 0
    @Published var onboardingContentOpacity: Double = 1
    @Published var glowRingRadius: CGFloat = 0
    @Published var glowRingOpacity: Double = 0
    @Published var orbScale: CGFloat = 1
    @Published var orbOpacity: Double = 1
    @Published var innerLightOpacity: Double = 0
    @Published var isBreathingEnabled = false
    @Published var breathingRingOpacity: Double = 1

    // Flying appearance orb animation — travels from click origin to notch position.
    @Published var mascotOpacity: Double = 0
    @Published var mascotScale: CGFloat = 0.5
    @Published var mascotAtOrb: Bool = false

    /// Screen-coordinate origin of the tap that triggered the arrival sequence.
    var clickOrigin: CGPoint = .zero
    /// Appearance selected by the user; used to render the correct mascot.
    var selectedAppearance: OnboardingAppearance = .defaultAppearance

    var onPanelSummon: (() -> Void)?
    var onSequenceFinished: (() -> Void)?

    private var sequenceTask: Task<Void, Never>?

    static let arrivalEase = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.6)

    func startTransitionOut() {
        sequenceTask?.cancel()
        state = .fadingOutOnboarding
        onboardingContentOpacity = 1
        washOpacity = 0

        withAnimation(.easeOut(duration: 0.28)) {
            onboardingContentOpacity = 0
        }

        sequenceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.28)) {
                washOpacity = 0.72
            }
            try? await Task.sleep(nanoseconds: 360_000_000)
            guard !Task.isCancelled else { return }
            state = .waitingInDarkness
        }
    }

    func startOrbBloom() {
        sequenceTask?.cancel()
        state = .bloomingOrb
        washOpacity = max(washOpacity, 0.72)
        glowRingRadius = 0
        glowRingOpacity = 0.34
        orbScale = 0.5
        orbOpacity = 0
        innerLightOpacity = 0
        mascotAtOrb = false
        mascotOpacity = 0
        mascotScale = 0.82
        isBreathingEnabled = false

        sequenceTask = Task { @MainActor in
            // Fade the selected orb in at the click origin.
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.12)) {
                mascotOpacity = 1
            }

            // Launch the selected orb toward the notch with a short focus pull.
            try? await Task.sleep(nanoseconds: 70_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.58)) {
                mascotAtOrb = true
                mascotScale = 0.52
                glowRingRadius = 108
                innerLightOpacity = 0.24
            }

            // Give the notch position a brief bloom, then open the main panel.
            try? await Task.sleep(nanoseconds: 430_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                glowRingOpacity = 0.12
                orbScale = 1
                orbOpacity = 1
                innerLightOpacity = 0.42
            }

            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            state = .panelOpen
            onPanelSummon?()

            withAnimation(.easeOut(duration: 0.34)) {
                washOpacity = 0
                mascotOpacity = 0
                glowRingOpacity = 0
                innerLightOpacity = 0
            }

            try? await Task.sleep(nanoseconds: 340_000_000)
            guard !Task.isCancelled else { return }
            isBreathingEnabled = true
            startBreathingAnimation()
            onSequenceFinished?()
        }
    }

    func userChoseCleanup() {
        state = .yesPath
    }

    func userChoseLater() {
        state = .laterPath
    }

    private func startBreathingAnimation() {
        withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
            breathingRingOpacity = 0.92
        }
    }

    func cancel() {
        sequenceTask?.cancel()
    }
}
