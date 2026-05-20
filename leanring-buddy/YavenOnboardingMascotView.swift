//
//  YavenOnboardingMascotView.swift
//  leanring-buddy
//
//  SwiftUI-only appearance previews used by onboarding and the first-run
//  arrival animation.
//

import SwiftUI

struct YavenOnboardingMascotView: View {
    let appearance: OnboardingAppearance
    var size: CGFloat = 120

    var body: some View {
        Group {
            switch appearance {
            case .black:
                blackOrb
            case .glass:
                glassOrb
            }
        }
        .frame(width: size, height: size)
    }

    private var blackOrb: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            Color(white: 0.12),
                            Color(white: 0.025),
                            Color.black
                        ],
                        center: UnitPoint(x: 0.28, y: 0.20),
                        startRadius: size * 0.02,
                        endRadius: size * 0.62
                    )
                )

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.16),
                            Color.clear,
                            Color.black.opacity(0.22)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.38),
                            Color.white.opacity(0.08),
                            Color.black.opacity(0.62)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: max(1.2, size * 0.016)
                )

            Ellipse()
                .fill(Color.white.opacity(0.24))
                .frame(width: size * 0.46, height: size * 0.17)
                .blur(radius: size * 0.030)
                .offset(x: -size * 0.17, y: -size * 0.24)

            Ellipse()
                .fill(Color.white.opacity(0.11))
                .frame(width: size * 0.24, height: size * 0.08)
                .blur(radius: size * 0.012)
                .offset(x: -size * 0.24, y: -size * 0.29)
        }
        .shadow(color: Color.black.opacity(0.40), radius: size * 0.12, y: size * 0.07)
    }

    private var glassOrb: some View {
        ZStack {
            glassOrbBase

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.58),
                            Color(red: 0.72, green: 0.67, blue: 0.55).opacity(0.52),
                            Color(red: 0.49, green: 0.45, blue: 0.35).opacity(0.36),
                            Color(red: 0.22, green: 0.21, blue: 0.18).opacity(0.18)
                        ],
                        center: UnitPoint(x: 0.25, y: 0.17),
                        startRadius: size * 0.02,
                        endRadius: size * 0.78
                    )
                )

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.22),
                            Color.clear,
                            Color.black.opacity(0.13)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.92),
                            Color.white.opacity(0.36),
                            Color(red: 0.72, green: 0.68, blue: 0.58).opacity(0.34),
                            Color(red: 0.20, green: 0.19, blue: 0.17).opacity(0.26)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: max(1.4, size * 0.018)
                )

            Ellipse()
                .fill(Color.white.opacity(0.58))
                .frame(width: size * 0.50, height: size * 0.17)
                .blur(radius: size * 0.030)
                .offset(x: -size * 0.18, y: -size * 0.25)

            Ellipse()
                .stroke(Color.white.opacity(0.46), lineWidth: max(1.1, size * 0.016))
                .frame(width: size * 0.78, height: size * 0.40)
                .rotationEffect(.degrees(-24))
                .offset(x: size * 0.08, y: size * 0.04)

            Ellipse()
                .stroke(Color.black.opacity(0.13), lineWidth: max(0.8, size * 0.010))
                .frame(width: size * 0.74, height: size * 0.36)
                .rotationEffect(.degrees(-24))
                .offset(x: size * 0.10, y: size * 0.06)
        }
        .clipShape(Circle())
        .shadow(color: Color.white.opacity(0.24), radius: size * 0.11, y: size * 0.02)
        .shadow(color: Color.black.opacity(0.18), radius: size * 0.14, y: size * 0.08)
    }

    @ViewBuilder
    private var glassOrbBase: some View {
        if #available(macOS 26.0, *) {
            Color.white.opacity(0.001)
                .glassEffect(
                    .regular
                        .interactive(true)
                        .tint(Color(red: 0.66, green: 0.60, blue: 0.48).opacity(0.20)),
                    in: Circle()
                )
        } else {
            VisualEffectBackground(material: .underWindowBackground, blendingMode: .behindWindow)
                .clipShape(Circle())
                .overlay(Circle().fill(Color.white.opacity(0.08)))
        }
    }
}
