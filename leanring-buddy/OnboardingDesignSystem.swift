//
//  OnboardingDesignSystem.swift
//  leanring-buddy
//
//  Design tokens for the Yaven onboarding window. Kept separate from the
//  main DS namespace — onboarding uses a Pastel Dawn palette with blush,
//  powder blue, lavender, morning cream, and soft plum text.
//
//  Font setup: Caprasimo and Fraunces are bundled .ttf resources and registered
//  once in applicationDidFinishLaunching. SwiftUI Font.custom needs registered
//  PostScript face names, not filenames.
//

import CoreText
import SwiftUI

enum OnboardingDS {

    // MARK: - Colors

    enum Colors {
        /// Deep warm amber — heaviest gradient blob, dominant warm layer.
        static let inkNavy    = Color(hex: "#9B5E1A")
        /// Near-black warm base — darkest window fill behind the gradient.
        static let deepNavy   = Color(hex: "#1A1208")
        /// Morning gold — primary action fills, sunlit warmth.
        static let skyBlue    = Color(hex: "#D4903A")
        /// Dawn peach — mid-tone fills and secondary elements.
        static let periBlue   = Color(hex: "#C4886A")
        /// Warm sand — subtle tints, dividers, muted text.
        static let steelHaze  = Color(hex: "#BEA082")
        /// Cloud cream — warm primary text on dark surfaces.
        static let cloudCream = Color(hex: "#EDE8D5")
        /// Warm rose — accent for mascot and connector views.
        static let blushPink  = Color(hex: "#F0A070")
        /// Morning cream — soft golden highlight.
        static let morningCream = Color(hex: "#FFF1C8")
        /// Sunbeam — bright warm yellow highlight accent.
        static let morningGold  = Color(hex: "#F5C060")
        /// Glass fill — semi-transparent white layer for frosted cards.
        static let glassFill  = Color.white.opacity(0.08)
        /// Glass border — subtle outline on frosted panels.
        static let glassBorder = Color.white.opacity(0.12)
        /// Error — reads clearly on warm dark backgrounds.
        static let error      = Color(hex: "#E5646A")
    }

    // MARK: - Typography

    enum Fonts {
        private static let displayName = "Caprasimo-Regular"
        private static let headingName = "Caprasimo-Regular"

        /// Display title — large editorial serif for top-level headings.
        static func display(size: CGFloat = 48) -> Font {
            .custom(displayName, size: size, relativeTo: .largeTitle)
        }

        /// Heading — medium editorial serif for section titles.
        static func heading(size: CGFloat = 22) -> Font {
            .custom(headingName, size: size, relativeTo: .title2)
        }

        /// Body — system font for comfortable reading.
        static func body(size: CGFloat = 14) -> Font {
            .system(size: size)
        }

        /// Caption — small system font for privacy notices and timestamps.
        static func caption(size: CGFloat = 11) -> Font {
            .system(size: size)
        }

        /// Register bundled display fonts once at app start.
        static func register() {
            [
                "Caprasimo-Regular",
                "Fraunces-VariableFont_opsz,wght"
            ].forEach { resourceName in
                guard let url = Bundle.main.url(forResource: resourceName, withExtension: "ttf") else {
                    return
                }
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    // MARK: - Layout

    enum Layout {
        static let windowWidth:  CGFloat = 520
        static let windowHeight: CGFloat = 580
        static let cornerRadius: CGFloat = 20
        static let cardRadius:   CGFloat = 14
        static let cardPadding:  CGFloat = 24
    }

    // MARK: - Animation

    enum Animation {
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.25)
        static let slow     = SwiftUI.Animation.easeInOut(duration: 0.45)
    }
}
