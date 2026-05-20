//
//  OnboardingConnectorsView.swift
//  leanring-buddy
//
//  Stage 3 of onboarding — choose Yaven's shell surface.
//

import AppKit
import SwiftUI

struct OnboardingConnectorsView: View {
    @ObservedObject var onboardingManager: OnboardingManager

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 34)
                .padding(.horizontal, 34)

            Spacer(minLength: 18)

            appearanceGrid
                .padding(.horizontal, 32)
                .padding(.top, 24)

            Spacer(minLength: 18)

            Button {
                onboardingManager.proceedFromConnectors(clickOrigin: NSEvent.mouseLocation)
            } label: {
                Text("Continue")
                    .font(OnboardingDS.Fonts.body(size: 14))
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(OnboardingDS.Colors.skyBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .padding(.horizontal, 34)
            .padding(.bottom, 30)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose your surface")
                .font(OnboardingDS.Fonts.heading(size: 33))
                .foregroundStyle(OnboardingDS.Colors.cloudCream)

            Text("You can change this later.")
                .font(OnboardingDS.Fonts.body(size: 14))
                .foregroundStyle(OnboardingDS.Colors.steelHaze)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var appearanceGrid: some View {
        HStack(spacing: 72) {
            ForEach(OnboardingAppearance.allCases) { appearance in
                AppearanceCard(
                    appearance: appearance,
                    isSelected: onboardingManager.selectedAppearance == appearance
                ) {
                    onboardingManager.selectAppearance(appearance)
                }
            }
        }
    }
}

private struct AppearanceCard: View {
    let appearance: OnboardingAppearance
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        cardButton
            .buttonStyle(PopGlassCardStyle())
            .zIndex(isHovering ? 1 : 0)
    }

    private var cardButton: some View {
        Button(action: onSelect) {
            VStack(spacing: 12) {
                let orbSize: CGFloat = isHovering || isSelected ? 96 : 84
                AppearanceOrb(appearance: appearance, size: orbSize)
                    // Spec: X 0, Y 8, blur 40, #000000 12% — amplified on hover
                    .shadow(
                        color: .black.opacity(isHovering ? 0.22 : (isSelected ? 0.17 : 0.12)),
                        radius: isHovering ? 32 : 20,
                        x: 0,
                        y: isHovering ? 14 : 8
                    )

                Text(optionTitle)
                    .font(OnboardingDS.Fonts.body(size: 14))
                    .fontWeight(.semibold)
                    .foregroundStyle(titleColor)
            }
            .frame(width: 132, height: 152)
            .contentShape(Rectangle())
            .offset(y: isHovering ? -5 : 0)
            .scaleEffect(isHovering ? 1.06 : (isSelected ? 1.02 : 1))
            .animation(.spring(response: 0.30, dampingFraction: 0.70), value: isHovering)
            .animation(OnboardingDS.Animation.standard, value: isSelected)
        }
        .pointerCursor()
        .onHover { isHovering = $0 }
    }

    private var optionTitle: String {
        switch appearance {
        case .black: return "Dark"
        case .glass: return "Light"
        }
    }

    private var titleColor: Color {
        switch appearance {
        case .black:
            return OnboardingDS.Colors.cloudCream.opacity(isSelected || isHovering ? 1 : 0.72)
        case .glass:
            return Color.white.opacity(isSelected || isHovering ? 0.96 : 0.68)
        }
    }

}

// Presses the orb down on tap, then springs back with overshoot (pop).
private struct PopGlassCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(
                configuration.isPressed
                    ? .spring(response: 0.12, dampingFraction: 0.80)   // fast compress
                    : .spring(response: 0.40, dampingFraction: 0.52),  // slow underdamped pop
                value: configuration.isPressed
            )
    }
}

// MARK: - Appearance orbs

private struct AppearanceOrb: View {
    let appearance: OnboardingAppearance
    let size: CGFloat

    var body: some View {
        if #available(macOS 26.0, *) {
            switch appearance {
            case .black: NativeDarkOrb(size: size)
            case .glass: NativeLightOrb(size: size)
            }
        } else {
            switch appearance {
            case .black: LegacyDarkOrb(size: size)
            case .glass: LegacyLightOrb(size: size)
            }
        }
    }
}

// Native Apple Liquid Glass orbs — macOS 26+

@available(macOS 26.0, *)
private struct NativeDarkOrb: View {
    let size: CGFloat

    var body: some View {
        Color.white.opacity(0.001)
            .glassEffect(
                .clear
                    .interactive(true)
                    .tint(Color.black.opacity(0.72)),
                in: Circle()
            )
            .frame(width: size, height: size)
    }
}

@available(macOS 26.0, *)
private struct NativeLightOrb: View {
    let size: CGFloat

    var body: some View {
        Color.white.opacity(0.001)
            .glassEffect(
                .clear
                    .interactive(true),
                in: Circle()
            )
            .frame(width: size, height: size)
    }
}

// MARK: - Legacy orbs (macOS 25 and below)

/// Glossy black sphere fallback.
private struct LegacyDarkOrb: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.80).opacity(0.50))
            Circle().fill(Color.black.opacity(0.60))
            Circle().fill(Color.white.opacity(0.06))
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.67), .clear],
                        center: UnitPoint(x: 0.36, y: 0.26),
                        startRadius: 0,
                        endRadius: size * 0.34
                    )
                )
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.18), .clear, .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
        }
        .frame(width: size, height: size)
    }
}

/// Pearl-glass sphere fallback.
private struct LegacyLightOrb: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.20))
            Circle().fill(Color.white.opacity(0.50))
            Circle().fill(Color(white: 0.97).opacity(0.88))
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.67), .clear],
                        center: UnitPoint(x: 0.36, y: 0.26),
                        startRadius: 0,
                        endRadius: size * 0.30
                    )
                )
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.28), .clear, .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
        }
        .frame(width: size, height: size)
    }
}
