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
            VStack(spacing: 10) {
                let orbSize: CGFloat = isHovering || isSelected ? 96 : 84
                ZStack(alignment: .topTrailing) {
                    AppearanceOrb(appearance: appearance, size: orbSize)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    Color.white.opacity(isSelected ? 0.62 : (isHovering ? 0.22 : 0)),
                                    lineWidth: isSelected ? 1.2 : 0.7
                                )
                        )
                        // Spec: X 0, Y 8, blur 40, #000000 12% — amplified on hover
                        .shadow(
                            color: .black.opacity(isHovering ? 0.22 : (isSelected ? 0.17 : 0.12)),
                            radius: isHovering ? 32 : 20,
                            x: 0,
                            y: isHovering ? 14 : 8
                        )

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.82))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.white.opacity(0.92)))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.7))
                            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                            .offset(x: 2, y: -2)
                            .transition(.scale(scale: 0.72).combined(with: .opacity))
                    }
                }
                .frame(height: 102)

                Text(optionTitle)
                    .font(OnboardingDS.Fonts.body(size: 14))
                    .fontWeight(.semibold)
                    .foregroundStyle(titleColor)

                Text(isSelected ? "Selected" : " ")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(isSelected ? 0.72 : 0))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(isSelected ? 0.10 : 0)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(isSelected ? 0.14 : 0), lineWidth: 0.5))
            }
            .frame(width: 154, height: 178)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.095 : (isHovering ? 0.045 : 0.018)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(isSelected ? 0.42 : (isHovering ? 0.16 : 0.055)),
                        lineWidth: isSelected ? 1.1 : 0.6
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .offset(y: isHovering ? -5 : 0)
            .scaleEffect(isHovering ? 1.035 : (isSelected ? 1.015 : 1))
            .animation(.spring(response: 0.30, dampingFraction: 0.70), value: isHovering)
            .animation(OnboardingDS.Animation.standard, value: isSelected)
        }
        .pointerCursor()
        .onHover { isHovering = $0 }
        .accessibilityLabel("\(optionTitle), \(isSelected ? "selected" : "not selected")")
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

struct AppearanceOrb: View {
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
