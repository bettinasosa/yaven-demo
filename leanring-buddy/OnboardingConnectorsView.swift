//
//  OnboardingConnectorsView.swift
//  leanring-buddy
//
//  Stage 3 of onboarding — choose Yaven's on-screen form.
//

import SwiftUI

struct OnboardingConnectorsView: View {
    @ObservedObject var onboardingManager: OnboardingManager

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 34)
                .padding(.horizontal, 34)

            Spacer(minLength: 18)

            YavenOnboardingMascotView(
                appearance: onboardingManager.selectedAppearance,
                size: 148
            )
            .animation(OnboardingDS.Animation.standard, value: onboardingManager.selectedAppearance)

            Text("Pick how Yaven should live on your screen.")
                .font(OnboardingDS.Fonts.body(size: 15))
                .foregroundStyle(OnboardingDS.Colors.steelHaze)
                .padding(.top, 12)

            appearanceGrid
                .padding(.horizontal, 32)
                .padding(.top, 24)

            Spacer(minLength: 18)

            Button {
                onboardingManager.proceedFromConnectors(clickOrigin: NSEvent.mouseLocation)
            } label: {
                Text("Bring Yaven to life")
                    .font(OnboardingDS.Fonts.body(size: 14))
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(OnboardingDS.Colors.cloudCream)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .padding(.horizontal, 34)
            .padding(.bottom, 30)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose your Yaven")
                .font(OnboardingDS.Fonts.heading(size: 33))
                .foregroundStyle(OnboardingDS.Colors.cloudCream)

            Text("You can change this later. For now, choose the vibe.")
                .font(OnboardingDS.Fonts.body(size: 14))
                .foregroundStyle(OnboardingDS.Colors.steelHaze)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var appearanceGrid: some View {
        HStack(spacing: 10) {
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

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 10) {
                YavenOnboardingMascotView(appearance: appearance, size: 56)

                VStack(spacing: 3) {
                    Text(appearance.displayName)
                        .font(OnboardingDS.Fonts.body(size: 13))
                        .fontWeight(.semibold)
                        .foregroundStyle(OnboardingDS.Colors.cloudCream)

                    Text(appearance.tagline)
                        .font(OnboardingDS.Fonts.caption(size: 10))
                        .foregroundStyle(OnboardingDS.Colors.steelHaze)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 130)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? OnboardingDS.Colors.cloudCream.opacity(0.34)
                            : OnboardingDS.Colors.glassBorder,
                        lineWidth: isSelected ? 1.2 : 0.7
                    )
            )
            .shadow(
                color: isSelected
                    ? OnboardingDS.Colors.blushPink.opacity(0.18)
                    : Color.clear,
                radius: 18,
                y: 8
            )
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                isSelected
                    ? Color.white.opacity(0.62)
                    : Color.white.opacity(0.34)
            )
    }
}
