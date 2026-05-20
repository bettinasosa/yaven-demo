//
//  OnboardingRootView.swift
//  leanring-buddy
//
//  Top-level SwiftUI container for the onboarding window. Switches between
//  stage views with a cross-fade transition over the animated gradient.
//

import SwiftUI

struct OnboardingRootView: View {
    @ObservedObject var onboardingManager: OnboardingManager
    @ObservedObject var arrivalCoordinator: OnboardingArrivalCoordinator

    var body: some View {
        ZStack {
            // Layer 1: warm curtain photo, clamped to the window frame
            Image("OnboardingBackground")
                .resizable()
                .scaledToFill()
                .frame(
                    width:  OnboardingDS.Layout.windowWidth,
                    height: OnboardingDS.Layout.windowHeight
                )
                .clipped()

            // Layer 2: dark warm scrim so text stays readable
            Color.black.opacity(0.38)

            // Layer 2: stage content cross-fades on stage change
            Group {
                switch onboardingManager.stage {
                case .googleSignIn:
                    OnboardingSignInView(onboardingManager: onboardingManager)
                case .name:
                    OnboardingNameView(onboardingManager: onboardingManager)
                case .role:
                    OnboardingRoleView(onboardingManager: onboardingManager)
                case .tools:
                    OnboardingToolsView(onboardingManager: onboardingManager)
                case .form:
                    OnboardingFormView(
                        onboardingManager: onboardingManager,
                        googleName: onboardingManager.googleProfile?.name ?? ""
                    )
                case .connections:
                    OnboardingConnectionsView(onboardingManager: onboardingManager)
                case .connectors:
                    OnboardingConnectorsView(onboardingManager: onboardingManager)
                case .welcome:
                    OnboardingWelcomeView(onboardingManager: onboardingManager)
                case .arrivalTransition:
                    OnboardingArrivalTransitionView(coordinator: arrivalCoordinator)
                case .launchAnimation:
                    OnboardingLaunchAnimationView(
                        appearance: onboardingManager.selectedAppearance
                    )
                case .complete:
                    EmptyView()
                }
            }
            .opacity(onboardingManager.stage == .arrivalTransition ? arrivalCoordinator.onboardingContentOpacity : 1)
            // The explicit id forces SwiftUI to treat each stage as a distinct
            // view, which triggers the .transition instead of updating in place.
            .id(onboardingManager.stage)
            .transition(.opacity)
            .animation(OnboardingDS.Animation.standard, value: onboardingManager.stage)
        }
        .frame(
            width:  OnboardingDS.Layout.windowWidth,
            height: OnboardingDS.Layout.windowHeight
        )
        .clipShape(
            RoundedRectangle(cornerRadius: OnboardingDS.Layout.cornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OnboardingDS.Layout.cornerRadius, style: .continuous)
                .strokeBorder(OnboardingDS.Colors.glassBorder, lineWidth: 0.5)
        )
    }
}
