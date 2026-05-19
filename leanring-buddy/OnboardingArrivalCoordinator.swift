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

    // Flying mascot animation — travels from click origin to orb position.
    @Published var mascotOpacity: Double = 0
    @Published var mascotScale: CGFloat = 0.5
    @Published var mascotAtOrb: Bool = false

    /// Screen-coordinate origin of the tap that triggered the arrival sequence.
    var clickOrigin: CGPoint = .zero
    /// Appearance selected by the user; used to render the correct mascot.
    var selectedAppearance: OnboardingAppearance = .cloud

    var onPanelSummon: (() -> Void)?
    var onSequenceFinished: (() -> Void)?

    private var sequenceTask: Task<Void, Never>?

    static let arrivalEase = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.6)

    func startTransitionOut() {
        sequenceTask?.cancel()
        state = .fadingOutOnboarding
        onboardingContentOpacity = 1
        washOpacity = 0

        withAnimation(.easeOut(duration: 0.6)) {
            onboardingContentOpacity = 0
        }

        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            withAnimation(.easeOut(duration: 0.6)) {
                washOpacity = 0.7
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
            state = .waitingInDarkness
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
    }

    func startOrbBloom() {
        sequenceTask?.cancel()
        state = .bloomingOrb
        glowRingRadius = 0
        glowRingOpacity = 0.4
        orbScale = 0.5
        orbOpacity = 0
        innerLightOpacity = 0
        mascotAtOrb = false
        mascotOpacity = 0
        mascotScale = 0.5

        Task {
            // Fade the flying mascot in at the click origin.
            try? await Task.sleep(nanoseconds: 100_000_000)
            withAnimation(.easeIn(duration: 0.12)) {
                mascotOpacity = 1
            }

            // Launch the mascot toward the orb position with a spring-like curve.
            try? await Task.sleep(nanoseconds: 60_000_000)
            withAnimation(Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.7)) {
                mascotAtOrb = true
                mascotScale = 1.0
            }

            // Glow ring expands as the mascot arrives.
            try? await Task.sleep(nanoseconds: 500_000_000)
            withAnimation(Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.8)) {
                glowRingRadius = 120
                glowRingOpacity = 0
            }

            // Reveal the real orb and dissolve the flying mascot.
            try? await Task.sleep(nanoseconds: 200_000_000)
            withAnimation(Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.6)) {
                orbScale = 1
                orbOpacity = 1
            }
            withAnimation(.easeOut(duration: 0.25)) {
                mascotOpacity = 0
            }

            try? await Task.sleep(nanoseconds: 400_000_000)
            withAnimation(.easeInOut(duration: 0.4)) {
                innerLightOpacity = 0.6
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
            withAnimation(.easeInOut(duration: 0.2)) {
                innerLightOpacity = 0.1
            }

            try? await Task.sleep(nanoseconds: 300_000_000)
            state = .settled
            isBreathingEnabled = true
            startBreathingAnimation()

            try? await Task.sleep(nanoseconds: 400_000_000)
            withAnimation(.easeOut(duration: 0.6)) {
                washOpacity = 0
            }

            try? await Task.sleep(nanoseconds: 600_000_000)
            state = .panelOpen
            onPanelSummon?()

            try? await Task.sleep(nanoseconds: 200_000_000)
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
