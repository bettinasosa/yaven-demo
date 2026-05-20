//
//  OnboardingRoleView.swift
//  leanring-buddy
//
//  Step 3 of onboarding — Yaven learns what the user does and where they work.
//

import SwiftUI

struct OnboardingRoleView: View {
    @ObservedObject var onboardingManager: OnboardingManager

    @State private var role: String = ""
    @State private var company: String = ""
    @FocusState private var focusedField: Field?
    @State private var linkedInState: LinkedInState = .idle

    enum Field { case role, company }
    enum LinkedInState { case idle, connecting, connected }

    var canContinue: Bool { !role.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 28) {
                // Heading
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tell Yaven what\nyou do")
                        .font(OnboardingDS.Fonts.display(size: 38))
                        .foregroundStyle(OnboardingDS.Colors.cloudCream)

                    Text("Yaven uses this to suggest the right tools and context.")
                        .font(OnboardingDS.Fonts.body(size: 14))
                        .foregroundStyle(OnboardingDS.Colors.steelHaze)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Fields
                VStack(spacing: 12) {
                    styledField(placeholder: "Your role or title", text: $role, field: .role)
                        .onSubmit { focusedField = .company }

                    styledField(placeholder: "Company or project (optional)", text: $company, field: .company)
                        .onSubmit { proceed() }
                }

                // Or divider + LinkedIn
                VStack(spacing: 12) {
                    orDivider

                    linkedInButton
                }
            }
            .padding(.horizontal, 40)

            Spacer()

            // Continue
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
            .padding(.horizontal, 40)
            .padding(.bottom, 30)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { focusedField = .role }
        }
    }

    // MARK: - Or divider

    private var orDivider: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(OnboardingDS.Colors.glassBorder)
                .frame(height: 0.5)
            Text("Or")
                .font(OnboardingDS.Fonts.caption(size: 11))
                .foregroundStyle(OnboardingDS.Colors.steelHaze.opacity(0.6))
            Rectangle()
                .fill(OnboardingDS.Colors.glassBorder)
                .frame(height: 0.5)
        }
    }

    // MARK: - LinkedIn button (same height/style as fields)

    @ViewBuilder
    private var linkedInButton: some View {
        switch linkedInState {
        case .idle:
            Button(action: startLinkedInConnect) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color(hex: "#0A66C2"))
                            .frame(width: 16, height: 16)
                        Text("in")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    Text("Connect LinkedIn")
                        .font(OnboardingDS.Fonts.body(size: 14))
                        .fontWeight(.medium)
                        .foregroundStyle(OnboardingDS.Colors.cloudCream)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(OnboardingDS.Colors.glassFill)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(OnboardingDS.Colors.glassBorder, lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .transition(.opacity)

        case .connecting:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(OnboardingDS.Colors.steelHaze)
                Text("Connecting to LinkedIn…")
                    .font(OnboardingDS.Fonts.body(size: 14))
                    .foregroundStyle(OnboardingDS.Colors.steelHaze)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(OnboardingDS.Colors.glassFill)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(OnboardingDS.Colors.glassBorder, lineWidth: 0.5)
            )
            .transition(.opacity)

        case .connected:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.green.opacity(0.85))
                Text("Connected")
                    .font(OnboardingDS.Fonts.body(size: 14))
                    .fontWeight(.medium)
                    .foregroundStyle(Color.green.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.green.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.green.opacity(0.3), lineWidth: 0.5)
            )
            .transition(.scale(scale: 0.94).combined(with: .opacity))
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func styledField(placeholder: String, text: Binding<String>, field: Field) -> some View {
        TextField(placeholder, text: text)
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
                        focusedField == field
                            ? OnboardingDS.Colors.skyBlue.opacity(0.5)
                            : OnboardingDS.Colors.glassBorder,
                        lineWidth: 1
                    )
            )
            .focused($focusedField, equals: field)
    }

    private func startLinkedInConnect() {
        withAnimation(OnboardingDS.Animation.standard) { linkedInState = .connecting }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { linkedInState = .connected }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                onboardingManager.submitRole(role: "", company: "")
            }
        }
    }

    private func proceed() {
        let trimmedRole = role.trimmingCharacters(in: .whitespaces)
        guard !trimmedRole.isEmpty else { return }
        onboardingManager.submitRole(
            role: trimmedRole,
            company: company.trimmingCharacters(in: .whitespaces)
        )
    }
}
