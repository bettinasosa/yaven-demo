//
//  OnboardingWelcomeView.swift
//  leanring-buddy
//
//  Final onboarding step — Yaven introduces itself, then the selected orb
//  lifts into the notch before the main shell opens.
//

import AppKit
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
    @State private var shadeOpacity: Double = 0
    @State private var focusTrailOpacity: Double = 0

    private var firstName: String {
        let name = onboardingManager.userName
        return name.isEmpty ? "there" : name.components(separatedBy: " ").first ?? name
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(shadeOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Welcome content — fades out when departing
            VStack(spacing: 0) {
                Spacer()
                welcomeContent
                Spacer()
                showMeButton
            }
            .opacity(isDeparting ? 0 : 1)
            .animation(.easeOut(duration: 0.28), value: isDeparting)

            // Departure sequence — selected orb rising into the notch.
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

    // MARK: - Departure orb

    private var notchPill: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0),
                            Color.white.opacity(0.13 * focusTrailOpacity),
                            Color.white.opacity(0)
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: 118, height: 250)
                .blur(radius: 18)
                .offset(y: -48)
                .opacity(focusTrailOpacity)

            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 128, height: 128)
                .blur(radius: pillGlow)

            AppearanceOrb(appearance: onboardingManager.selectedAppearance, size: 82)
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.44), Color.white.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.9
                        )
                )
                .shadow(color: Color.white.opacity(0.16), radius: 18, y: 0)
                .shadow(color: Color.black.opacity(0.28), radius: 24, y: 10)

            Text("Yaven")
                .font(OnboardingDS.Fonts.body(size: 12))
                .fontWeight(.semibold)
                .foregroundStyle(Color.white.opacity(0.78))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.09)))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
                )
                .offset(y: 67)
        }
        .scaleEffect(pillScale)
        .opacity(pillOpacity)
        .offset(y: pillEntryOffset + pillExitOffset)
    }

    private var departureCaption: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.up")
                .font(.system(size: 10, weight: .medium))
            Text("Yaven is moving to your notch")
                .font(OnboardingDS.Fonts.body(size: 12))
        }
        .foregroundStyle(Color.white.opacity(0.66))
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
        let clickOrigin = NSEvent.mouseLocation
        isDeparting = true

        // Welcome text fades out (via .animation on isDeparting).
        withAnimation(.easeOut(duration: 0.24)) {
            shadeOpacity = 0.42
        }

        // Phase 1: selected orb springs in with a vertical focus trail.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(.spring(response: 0.52, dampingFraction: 0.65)) {
                pillScale = 1.0
                pillOpacity = 1
                pillEntryOffset = 0
            }
            withAnimation(.easeOut(duration: 0.45)) {
                pillGlow = 12
                focusTrailOpacity = 1
            }
        }

        // Phase 2: caption fades up into place.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.56) {
            withAnimation(.easeOut(duration: 0.32)) {
                captionOpacity = 1
                captionEntryOffset = 0
            }
        }

        // Phase 3: orb + caption float up and hand off to the full-screen arrival overlay.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.04) {
            withAnimation(.easeIn(duration: 0.38)) {
                pillOpacity = 0
                captionOpacity = 0
                pillExitOffset = -170
                pillGlow = 0
                focusTrailOpacity = 0
            }
        }

        // Phase 4: complete onboarding and pass the click origin to the arrival overlay.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.34) {
            onboardingManager.proceedFromWelcome(clickOrigin: clickOrigin)
        }
    }
}
