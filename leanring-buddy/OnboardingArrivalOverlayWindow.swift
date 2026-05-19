//
//  OnboardingArrivalOverlayWindow.swift
//  leanring-buddy
//

import AppKit
import SwiftUI

@MainActor
final class OnboardingArrivalOverlayWindowController {
    private let coordinator: OnboardingArrivalCoordinator
    private let orbFrameProvider: () -> NSRect
    private var window: NSPanel?

    init(
        coordinator: OnboardingArrivalCoordinator,
        orbFrameProvider: @escaping () -> NSRect
    ) {
        self.coordinator = coordinator
        self.orbFrameProvider = orbFrameProvider
    }

    func show() {
        guard window == nil else { return }

        let screenFrame = NSScreen.main?.frame ?? .zero
        let panel = NSPanel(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isFloatingPanel = true

        let overlayView = OnboardingArrivalOverlayView(
            coordinator: coordinator,
            orbFrameProvider: orbFrameProvider
        )
        let hostingView = NSHostingView(rootView: overlayView)
        hostingView.frame = screenFrame
        panel.contentView = hostingView

        window = panel
        panel.orderFrontRegardless()
    }

    func dismiss() {
        window?.orderOut(nil)
        window = nil
    }
}

struct OnboardingArrivalOverlayView: View {
    @ObservedObject var coordinator: OnboardingArrivalCoordinator
    let orbFrameProvider: () -> NSRect

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(white: 0.04)
                    .opacity(coordinator.washOpacity)
                    .ignoresSafeArea()

                let orbCenter = orbCenterInView(geometry: geometry)
                Circle()
                    .stroke(Color.cyan.opacity(coordinator.glowRingOpacity), lineWidth: 1.5)
                    .frame(
                        width: coordinator.glowRingRadius * 2,
                        height: coordinator.glowRingRadius * 2
                    )
                    .position(orbCenter)

                Circle()
                    .fill(Color.white.opacity(coordinator.innerLightOpacity))
                    .frame(width: 14, height: 14)
                    .blur(radius: 6)
                    .position(orbCenter)

                // Mascot that flies from the tap origin to the orb position.
                let clickPos = clickOriginInView(geometry: geometry)
                YavenOnboardingMascotView(
                    appearance: coordinator.selectedAppearance,
                    size: 48
                )
                .scaleEffect(coordinator.mascotScale)
                .opacity(coordinator.mascotOpacity)
                .position(coordinator.mascotAtOrb ? orbCenter : clickPos)
                .animation(
                    Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.7),
                    value: coordinator.mascotAtOrb
                )
            }
        }
        .ignoresSafeArea()
    }

    private func orbCenterInView(geometry: GeometryProxy) -> CGPoint {
        let orbFrame = orbFrameProvider()
        let screenFrame = NSScreen.main?.frame ?? .zero
        let x = orbFrame.midX - screenFrame.minX
        let y = geometry.size.height - (orbFrame.midY - screenFrame.minY)
        return CGPoint(x: x, y: y)
    }

    private func clickOriginInView(geometry: GeometryProxy) -> CGPoint {
        let screenFrame = NSScreen.main?.frame ?? .zero
        let x = coordinator.clickOrigin.x - screenFrame.minX
        let y = geometry.size.height - (coordinator.clickOrigin.y - screenFrame.minY)
        return CGPoint(x: x, y: y)
    }
}
