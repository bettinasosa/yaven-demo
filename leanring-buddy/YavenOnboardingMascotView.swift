//
//  YavenOnboardingMascotView.swift
//  leanring-buddy
//
//  Small SwiftUI-only mascots used by onboarding. These are intentionally
//  lightweight prototypes for the appearance choice, not final brand assets.
//

import SwiftUI

struct YavenOnboardingMascotView: View {
    let appearance: OnboardingAppearance
    var size: CGFloat = 120

    var body: some View {
        Group {
            switch appearance {
            case .water:
                waterMascot
            case .cloud:
                cloudMascot
            }
        }
        .frame(width: size, height: size)
    }

    private var cloudMascot: some View {
        Image("CloudMascot")
            .resizable()
            .interpolation(.none) // preserve pixel-art crispness
            .scaledToFit()
    }

    private var waterMascot: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.94),
                        OnboardingDS.Colors.inkNavy.opacity(0.76),
                        OnboardingDS.Colors.skyBlue.opacity(0.46)
                    ],
                    center: UnitPoint(x: 0.28, y: 0.20),
                    startRadius: 4,
                    endRadius: size * 0.58
                )
            )
            .shadow(color: OnboardingDS.Colors.skyBlue.opacity(0.24), radius: 16, y: 10)
            .padding(size * 0.14)
    }
}
