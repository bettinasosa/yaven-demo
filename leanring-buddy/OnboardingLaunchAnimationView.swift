//
//  OnboardingLaunchAnimationView.swift
//  leanring-buddy
//
//  Final onboarding beat: Yaven leaves the setup window and heads toward the
//  bottom-right corner where the floating shell orb lives.
//

import SwiftUI

struct OnboardingLaunchAnimationView: View {
    let appearance: OnboardingAppearance
    @State private var hasLaunched = false

    var body: some View {
        ZStack {
            launchGuides

            VStack(spacing: 12) {
                Text("All set.")
                    .font(OnboardingDS.Fonts.heading(size: 42))
                    .foregroundStyle(OnboardingDS.Colors.cloudCream)

                Text("Yaven is moving into place.")
                    .font(OnboardingDS.Fonts.body(size: 15))
                    .foregroundStyle(OnboardingDS.Colors.steelHaze)
            }
            .opacity(hasLaunched ? 0 : 1)
            .offset(y: -96)

            mascot
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.15)) {
                hasLaunched = true
            }
        }
    }

    private var mascot: some View {
        VStack(spacing: 10) {
            if hasLaunched {
                Text("hey! I am Yaven.")
                    .font(OnboardingDS.Fonts.body(size: 13))
                    .foregroundStyle(OnboardingDS.Colors.cloudCream)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.72))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(OnboardingDS.Colors.glassBorder, lineWidth: 0.7)
                    )
                    .transition(.scale.combined(with: .opacity))
            }

            YavenOnboardingMascotView(appearance: appearance, size: hasLaunched ? 52 : 136)
        }
        .offset(
            x: hasLaunched ? 184 : 0,
            y: hasLaunched ? 220 : 30
        )
        .scaleEffect(hasLaunched ? 0.92 : 1)
    }

    private var launchGuides: some View {
        ZStack {
            Circle()
                .stroke(OnboardingDS.Colors.cloudCream.opacity(0.06), lineWidth: 1)
                .frame(width: 260, height: 260)

            Path { path in
                path.move(to: CGPoint(x: 60, y: 110))
                path.addLine(to: CGPoint(x: 460, y: 470))
            }
            .stroke(OnboardingDS.Colors.cloudCream.opacity(0.06), lineWidth: 1)
        }
    }
}
