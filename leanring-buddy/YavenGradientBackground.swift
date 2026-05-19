//
//  YavenGradientBackground.swift
//  leanring-buddy
//
//  Animated warm morning gradient background for the onboarding window.
//  Four radial gradient blobs drift at different speeds and phases using
//  TimelineView + Canvas, producing a golden, cloud-light motion — like
//  sunlight filtering through curtains on a Sunday morning.
//
//  Designed to sit directly behind NSVisualEffectView glass layers so the
//  colour shows through the frosted surface at reduced opacity.
//

import SwiftUI

struct YavenGradientBackground: View {

    var body: some View {
        ZStack {
            // Base: deep navy anchors the darkest value
            OnboardingDS.Colors.deepNavy

            // Animated blob layer
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let t = timeline.date.timeIntervalSinceReferenceDate * 0.25

                    // Blob A — deep amber, main warm body drifting upper-left
                    drawBlob(
                        context: &context, size: size,
                        centerFraction: CGPoint(
                            x: 0.25 + 0.18 * sin(t * 0.60),
                            y: 0.28 + 0.14 * cos(t * 0.45)
                        ),
                        radiusFraction: 0.65,
                        color: OnboardingDS.Colors.inkNavy.opacity(0.88)
                    )

                    // Blob B — dawn peach, drifts lower-right like morning horizon
                    drawBlob(
                        context: &context, size: size,
                        centerFraction: CGPoint(
                            x: 0.72 + 0.14 * cos(t * 0.50 + 1.30),
                            y: 0.68 + 0.18 * sin(t * 0.70 + 0.80)
                        ),
                        radiusFraction: 0.55,
                        color: OnboardingDS.Colors.periBlue.opacity(0.60)
                    )

                    // Blob C — warm rose, gentle centre drift like filtered curtain light
                    drawBlob(
                        context: &context, size: size,
                        centerFraction: CGPoint(
                            x: 0.52 + 0.10 * sin(t * 0.35 + 2.10),
                            y: 0.48 + 0.10 * cos(t * 0.55 + 1.60)
                        ),
                        radiusFraction: 0.42,
                        color: OnboardingDS.Colors.blushPink.opacity(0.38)
                    )

                    // Blob D — sunbeam gold highlight, upper-right
                    drawBlob(
                        context: &context, size: size,
                        centerFraction: CGPoint(
                            x: 0.80 + 0.12 * sin(t * 0.40 + 3.50),
                            y: 0.20 + 0.12 * cos(t * 0.60 + 2.00)
                        ),
                        radiusFraction: 0.38,
                        color: OnboardingDS.Colors.morningGold.opacity(0.32)
                    )
                }
                .blendMode(.plusLighter)
            }
        }
    }

    private func drawBlob(
        context: inout GraphicsContext,
        size: CGSize,
        centerFraction: CGPoint,
        radiusFraction: CGFloat,
        color: Color
    ) {
        let center = CGPoint(
            x: size.width  * centerFraction.x,
            y: size.height * centerFraction.y
        )
        let radius = max(size.width, size.height) * radiusFraction
        let bounds = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width:  radius * 2,
            height: radius * 2
        )

        context.fill(
            Path(ellipseIn: bounds),
            with: .radialGradient(
                Gradient(colors: [color, color.opacity(0)]),
                center: center,
                startRadius: 0,
                endRadius: radius
            )
        )
    }
}
