//
//  OnboardingSignInView.swift
//  leanring-buddy
//
//  Stage 1 of onboarding — Google Sign In (faked for demo).
//

import SwiftUI

struct OnboardingSignInView: View {
    @ObservedObject var onboardingManager: OnboardingManager

    @State private var wordmarkOpacity: Double = 0
    @State private var wordmarkOffset: CGFloat = 16
    @State private var taglineOpacity: Double = 0
    @State private var buttonOpacity: Double = 0
    @State private var buttonOffset: CGFloat = 12
    @State private var isButtonHovered = false
    @State private var isButtonPressed = false

    // Fake connection states
    @State private var connectState: ConnectState = .idle

    enum ConnectState { case idle, connecting, connected }

    var body: some View {
        switch connectState {
        case .connecting:
            connectingView
        case .connected:
            connectedView
        case .idle:
            fullSignInView
                .onAppear { animateIn() }
        }
    }

    private var connectingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.regular)
                .tint(OnboardingDS.Colors.cloudCream)
                .scaleEffect(1.2)
            Text("Signing in to Google…")
                .font(OnboardingDS.Fonts.body(size: 14))
                .foregroundStyle(OnboardingDS.Colors.cloudCream.opacity(0.75))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }

    private var connectedView: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 54, height: 54)
                Image(systemName: "checkmark")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.green.opacity(0.85))
            }
            Text("Connected")
                .font(OnboardingDS.Fonts.body(size: 14))
                .foregroundStyle(OnboardingDS.Colors.cloudCream.opacity(0.75))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }

    private var fullSignInView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 14) {
                Text("yaven")
                    .font(OnboardingDS.Fonts.display(size: 52))
                    .foregroundStyle(OnboardingDS.Colors.cloudCream)
                    .opacity(wordmarkOpacity)
                    .offset(y: wordmarkOffset)

                Text("Focus in a distracted world.")
                    .font(OnboardingDS.Fonts.body(size: 15))
                    .foregroundStyle(OnboardingDS.Colors.steelHaze)
                    .opacity(taglineOpacity)
            }

            Spacer().frame(height: 52)

            Button(action: startFakeSignIn) {
                HStack(spacing: 10) {
                    Image(systemName: "globe")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(OnboardingDS.Colors.cloudCream)
                    Text("Continue with Google")
                        .font(OnboardingDS.Fonts.body(size: 14))
                        .fontWeight(.medium)
                        .foregroundStyle(OnboardingDS.Colors.cloudCream)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(
                    ZStack {
                        OnboardingDS.Colors.skyBlue
                        if isButtonHovered {
                            LinearGradient(
                                colors: [Color.white.opacity(0.15), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            isButtonHovered ? Color.white.opacity(0.35) : Color.white.opacity(0.18),
                            lineWidth: 0.5
                        )
                )
                .shadow(
                    color: OnboardingDS.Colors.morningGold.opacity(isButtonHovered ? 0.45 : 0),
                    radius: 16, x: 0, y: 4
                )
                .scaleEffect(isButtonPressed ? 0.97 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isButtonPressed)
                .animation(.easeOut(duration: 0.18), value: isButtonHovered)
            }
            .buttonStyle(.plain)
            .pointerCursor(isEnabled: true)
            .onHover { isButtonHovered = $0 }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isButtonPressed = true }
                    .onEnded   { _ in isButtonPressed = false }
            )
            .opacity(buttonOpacity)
            .offset(y: buttonOffset)

            Spacer()

            Text(OnboardingManager.privacyNotice)
                .font(OnboardingDS.Fonts.caption())
                .foregroundStyle(OnboardingDS.Colors.steelHaze.opacity(0.65))
                .padding(.bottom, 28)

            #if DEBUG
            Button("Skip onboarding") {
                onboardingManager.debugSkipOnboarding()
            }
            .font(OnboardingDS.Fonts.caption())
            .foregroundStyle(OnboardingDS.Colors.steelHaze.opacity(0.45))
            .buttonStyle(.plain)
            .pointerCursor()
            .padding(.bottom, 12)
            #endif
        }
        .padding(.horizontal, OnboardingDS.Layout.cardPadding)
    }

    private func startFakeSignIn() {
        withAnimation(OnboardingDS.Animation.standard) { connectState = .connecting }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                connectState = .connected
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                onboardingManager.fakeSignIn()
            }
        }
    }

    private func animateIn() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.1)) {
            wordmarkOpacity = 1
            wordmarkOffset = 0
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.35)) {
            taglineOpacity = 1
        }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.7).delay(0.55)) {
            buttonOpacity = 1
            buttonOffset = 0
        }
    }
}
