//
//  OnboardingArrivalTransitionView.swift
//  leanring-buddy
//

import SwiftUI

struct OnboardingArrivalTransitionView: View {
    @ObservedObject var coordinator: OnboardingArrivalCoordinator

    var body: some View {
        ZStack {
            Color.clear

            Color(white: 0.04)
                .opacity(coordinator.washOpacity)
                .ignoresSafeArea()
        }
        .onAppear {
            coordinator.startTransitionOut()
        }
    }
}
