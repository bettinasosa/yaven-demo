//
//  OnboardingWelcomeView.swift
//  leanring-buddy
//
//  Final onboarding step — Yaven introduces itself, then the notch pill
//  springs in and floats up into the menu bar to show where Yaven lives.
//

import SwiftUI

struct OnboardingWelcomeView: View {
    @ObservedObject var onboardingManager: OnboardingManager

    // Entrance animation
    @State private var lineOneOpacity: Double = 0
    @State private var lineOneOffset: CGFloat = 12
    @State private var lineTwoOpacity: Double = 0
    @State private var lineTwoOffset: CGFloat = 12
    @State private var lineThreeOpacity: Double = 0
    @State private var buttonOpacity: Double = 0
    @State private var buttonOffset: CGFloat = 10
    @State private var isButtonHovered = false

    // Departure animation
    @State private var isDeparting = false
    @State private var pillScale: CGFloat = 0.65
    @State private var pillOpacity: Double = 0
    @State private var pillEntryOffset: CGFloat = 18
    @State private var pillExitOffset: CGFloat = 0
    @State private var pillGlow: CGFloat = 0
    @State private var captionOpacity: Double = 0
    @State private var captionEntryOffset: CGFloat = 6

    private var firstName: String {
        let name = onboardingManager.userName
        return name.isEmpty ? "there" : name.components(separatedBy: " ").first ?? name
    }

    var body: some View {
        ZStack {
            // Welcome content — fades out when departing
            VStack(spacing: 0) {
                Spacer()
                welcomeContent
                Spacer()
                showMeButton
            }
            .opacity(isDeparting ? 0 : 1)
            .animation(.easeOut(duration: 0.28), value: isDeparting)

            // Departure sequence — pill rising into menu bar
            VStack(spacing: 14) {
                Spacer()
                notchPill
                departureCaption
                Spacer()
                Spacer()
            }
            .allowsHitTesting(false)
        }
        .onAppear { animateIn() }
    }

    // MARK: - Welcome content

    private var welcomeContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hi, \(firstName).")
                .font(OnboardingDS.Fonts.display(size: 44))
                .foregroundStyle(OnboardingDS.Colors.cloudCream)
                .opacity(lineOneOpacity)
                .offset(y: lineOneOpacity == 0 ? lineOneOffset : 0)

            Text("I'm Yaven.")
                .font(OnboardingDS.Fonts.display(size: 44))
                .foregroundStyle(OnboardingDS.Colors.skyBlue)
                .opacity(lineTwoOpacity)
                .offset(y: lineTwoOpacity == 0 ? lineTwoOffset : 0)

            Spacer().frame(height: 12)

            Text("Let's see what we can\nachieve together.")
                .font(OnboardingDS.Fonts.body(size: 17))
                .foregroundStyle(OnboardingDS.Colors.steelHaze)
                .lineSpacing(4)
                .opacity(lineThreeOpacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 44)
    }

    private var showMeButton: some View {
        Button(action: startDeparture) {
            HStack(spacing: 8) {
                Text("Show me")
                    .font(OnboardingDS.Fonts.body(size: 15))
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                ZStack {
                    OnboardingDS.Colors.skyBlue
                    if isButtonHovered {
                        LinearGradient(
                            colors: [Color.white.opacity(0.12), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(
                color: OnboardingDS.Colors.morningGold.opacity(isButtonHovered ? 0.35 : 0),
                radius: 16, x: 0, y: 4
            )
            .animation(.easeOut(duration: 0.18), value: isButtonHovered)
        }
        .buttonStyle(.plain)
        .pointerCursor(isEnabled: true)
        .onHover { isButtonHovered = $0 }
        .opacity(buttonOpacity)
        .offset(y: buttonOffset)
        .padding(.horizontal, 34)
        .padding(.bottom, 38)
    }

    // MARK: - Departure pill

    private var notchPill: some View {
        ZStack {
            // Glow halo
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .frame(width: 224, height: 46)
                .blur(radius: pillGlow)

            // Pill body
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .fill(Color.black)
                .frame(width: 208, height: 36)
                .overlay(
                    HStack(spacing: 9) {
                        // Orb indicator
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 16, height: 16)
                            Circle()
                                .fill(Color.white.opacity(0.85))
                                .frame(width: 8, height: 8)
                        }
                        Text("Yaven")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.9))
                            .kerning(0.2)
                    }
                )
                // Subtle inner highlight
                .overlay(
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        }
        .scaleEffect(pillScale)
        .opacity(pillOpacity)
        .offset(y: pillEntryOffset + pillExitOffset)
    }

    private var departureCaption: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.up")
                .font(.system(size: 10, weight: .medium))
            Text("Yaven now lives in your menu bar")
                .font(OnboardingDS.Fonts.body(size: 12))
        }
        .foregroundStyle(OnboardingDS.Colors.steelHaze.opacity(0.65))
        .opacity(captionOpacity)
        .offset(y: captionEntryOffset + pillExitOffset * 0.5)
    }

    // MARK: - Animations

    private func animateIn() {
        withAnimation(.spring(response: 0.55, dampingFraction: 0.75).delay(0.15)) {
            lineOneOpacity = 1
            lineOneOffset = 0
        }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.75).delay(0.38)) {
            lineTwoOpacity = 1
            lineTwoOffset = 0
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.62)) {
            lineThreeOpacity = 1
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.9)) {
            buttonOpacity = 1
            buttonOffset = 0
        }
    }

    private func startDeparture() {
        guard !isDeparting else { return }
        isDeparting = true

        // Welcome text fades out (via .animation on isDeparting).
        // Phase 1 (320ms): pill springs in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            withAnimation(.spring(response: 0.52, dampingFraction: 0.65)) {
                pillScale = 1.0
                pillOpacity = 1
                pillEntryOffset = 0
            }
            // Glow blooms in sync with the spring
            withAnimation(.easeOut(duration: 0.45)) {
                pillGlow = 12
            }
        }

        // Phase 2 (750ms): caption fades up into place
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            withAnimation(.easeOut(duration: 0.32)) {
                captionOpacity = 1
                captionEntryOffset = 0
            }
        }

        // Phase 3 (1650ms): pill + caption float up and dissolve
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.65) {
            withAnimation(.easeIn(duration: 0.48)) {
                pillOpacity = 0
                captionOpacity = 0
                pillExitOffset = -140
                pillGlow = 0
            }
        }

        // Phase 4 (2150ms): complete onboarding
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) {
            onboardingManager.proceedFromWelcome()
        }
    }
}
