//
//  OnboardingNameView.swift
//  leanring-buddy
//
//  Step 2 of onboarding — Yaven asks for your name.
//

import SwiftUI

struct OnboardingNameView: View {
    @ObservedObject var onboardingManager: OnboardingManager

    @State private var name: String = ""
    @FocusState private var focused: Bool

    var canContinue: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 28) {
                Text("What should\nYaven call you?")
                    .font(OnboardingDS.Fonts.display(size: 38))
                    .foregroundStyle(OnboardingDS.Colors.cloudCream)

                TextField("Your name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .foregroundStyle(OnboardingDS.Colors.cloudCream)
                    .tint(OnboardingDS.Colors.skyBlue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(OnboardingDS.Colors.glassFill)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                focused
                                    ? OnboardingDS.Colors.skyBlue.opacity(0.5)
                                    : OnboardingDS.Colors.glassBorder,
                                lineWidth: 1
                            )
                    )
                    .focused($focused)
                    .onSubmit { proceed() }
            }
            .padding(.horizontal, 40)

            Spacer()

            Button(action: proceed) {
                Text("Continue")
                    .font(OnboardingDS.Fonts.body(size: 14))
                    .fontWeight(.semibold)
                    .foregroundStyle(canContinue ? .white : OnboardingDS.Colors.steelHaze)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(canContinue ? OnboardingDS.Colors.skyBlue : OnboardingDS.Colors.glassFill)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                canContinue ? Color.clear : OnboardingDS.Colors.glassBorder,
                                lineWidth: 0.5
                            )
                    )
                    .animation(OnboardingDS.Animation.standard, value: canContinue)
            }
            .buttonStyle(.plain)
            .disabled(!canContinue)
            .pointerCursor(isEnabled: canContinue)
            .padding(.horizontal, 34)
            .padding(.bottom, 30)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { focused = true }
        }
    }

    private func proceed() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onboardingManager.submitName(trimmed)
    }
}
