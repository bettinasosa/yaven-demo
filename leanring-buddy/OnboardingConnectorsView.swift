//
//  OnboardingConnectorsView.swift
//  leanring-buddy
//
//  Step 5 of onboarding — choose Yaven's dock style.
//  Both options are selectable; the demo always uses Black under the hood.
//

import SwiftUI

struct OnboardingConnectorsView: View {
    @ObservedObject var onboardingManager: OnboardingManager
    @State private var selectedStyle: DockStyle = .black

    enum DockStyle { case black, glass }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 34)
                .padding(.horizontal, 34)

            Spacer(minLength: 18)

            styleGrid
                .padding(.horizontal, 32)

            Spacer(minLength: 18)

            Button {
                onboardingManager.proceedFromConnectors()
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
            Text("Choose your style")
                .font(OnboardingDS.Fonts.heading(size: 33))
                .foregroundStyle(OnboardingDS.Colors.cloudCream)

            Text("How should Yaven sit on your screen?")
                .font(OnboardingDS.Fonts.body(size: 14))
                .foregroundStyle(OnboardingDS.Colors.steelHaze)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var styleGrid: some View {
        HStack(spacing: 12) {
            StyleCard(
                label: "Black",
                description: "Clean, dark, minimal.",
                isSelected: selectedStyle == .black,
                preview: blackPreview
            ) { selectedStyle = .black }

            StyleCard(
                label: "Glass",
                description: "Translucent, light, airy.",
                isSelected: selectedStyle == .glass,
                preview: glassPreview
            ) { selectedStyle = .glass }
        }
    }

    private var blackPreview: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.black)
            .frame(height: 36)
            .overlay(
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.white.opacity(0.6))
                        .frame(width: 8, height: 8)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 28, height: 5)
                }
            )
            .padding(.horizontal, 10)
    }

    private var glassPreview: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.ultraThinMaterial)
            .frame(height: 36)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
            )
            .overlay(
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 8, height: 8)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 28, height: 5)
                }
            )
            .padding(.horizontal, 10)
    }
}

// MARK: - Style Card

private struct StyleCard<Preview: View>: View {
    let label: String
    let description: String
    let isSelected: Bool
    let preview: Preview
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 12) {
                preview

                VStack(spacing: 4) {
                    Text(label)
                        .font(OnboardingDS.Fonts.body(size: 13))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.black.opacity(0.82))

                    Text(description)
                        .font(OnboardingDS.Fonts.caption(size: 10))
                        .foregroundStyle(Color.black.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .padding(.vertical, 14)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.55) : Color.white.opacity(0.28))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? OnboardingDS.Colors.cloudCream.opacity(0.34)
                            : OnboardingDS.Colors.glassBorder,
                        lineWidth: isSelected ? 1.2 : 0.7
                    )
            )
            .animation(OnboardingDS.Animation.standard, value: isSelected)
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }
}
