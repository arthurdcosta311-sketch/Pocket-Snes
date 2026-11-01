//
//  Theme.swift
//  Pocket Snes
//
//  The app's visual language: colour, type, spacing, surfaces and motion.
//  Everything on screen pulls from here so the interface stays consistent.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum Theme {

    /// Builds a colour from a hex literal without needing an asset entry.
    static func rgb(_ hex: UInt32, _ alpha: Double = 1) -> Color {
        Color(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    // MARK: - Colour

    enum Palette {
        /// Deepest tone, used behind the player.
        static let ink = rgb(0x07060B)
        /// The app's base background.
        static let backdrop = rgb(0x0C0A13)
        /// Cards and rows sitting on the backdrop.
        static let surface = rgb(0x171425)
        /// Controls sitting on a surface.
        static let raised = rgb(0x231E36)
        /// The controller deck under the emulator surface.
        static let deck = rgb(0x1B1729)

        static let text = rgb(0xF2EEE4)
        static let muted = rgb(0x958FA9)
        static let faint = rgb(0x625D79)

        static let accent = rgb(0x8B5CF6)
        static let accentSoft = rgb(0xC9B8FF)
        static let accentDeep = rgb(0x4A2E92)

        static let mint = rgb(0x35E0A1)
        static let blue = rgb(0x4C8DFF)
        static let green = rgb(0x35D07F)
        static let red = rgb(0xFF5C5C)
        static let yellow = rgb(0xFFC94A)

        static let stroke = Color.white.opacity(0.08)
        static let hairline = Color.white.opacity(0.14)
    }

    // MARK: - Spacing

    enum Metrics {
        static let gutter: CGFloat = 20
        static let cardRadius: CGFloat = 20
        static let innerRadius: CGFloat = 14
        static let chipRadius: CGFloat = 9
        static let sectionGap: CGFloat = 28
        static let gridSpacing: CGFloat = 14
        /// Cover art is drawn at a 5:4 box.
        static let artAspect: CGFloat = 1.25
        /// SNES output, used for the emulator surface.
        static let surfaceAspect: CGFloat = 4.0 / 3.0
    }

    // MARK: - Type

    enum Face {
        static func display(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
            .system(size: size, weight: weight, design: .rounded)
        }

        static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .rounded)
        }

        static func mono(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
    }

    // MARK: - Motion

    enum Motion {
        static let press = Animation.spring(response: 0.22, dampingFraction: 0.62)
        static let smooth = Animation.spring(response: 0.36, dampingFraction: 0.86)
    }
}

// MARK: - Haptics

enum Haptics {
    static func press() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred(intensity: 0.7)
        #endif
    }

    static func select() {
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
}

// MARK: - Background

/// Backdrop used by every screen: the base tone, a faint dot grid for texture
/// and two soft glows for depth. No gradient fills on any control.
struct ScreenBackground: View {
    var showsGlow: Bool = true

    var body: some View {
        ZStack {
            Theme.Palette.backdrop
            DotGrid()
            if showsGlow {
                Circle()
                    .fill(Theme.Palette.accent.opacity(0.26))
                    .frame(width: 300, height: 300)
                    .blur(radius: 90)
                    .offset(x: 130, y: -290)
                Circle()
                    .fill(Theme.Palette.mint.opacity(0.10))
                    .frame(width: 240, height: 240)
                    .blur(radius: 90)
                    .offset(x: -150, y: 320)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct DotGrid: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 22
            let dot = Path(ellipseIn: CGRect(x: 0, y: 0, width: 1.7, height: 1.7))
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    context.fill(dot.offsetBy(dx: x, dy: y), with: .color(.white.opacity(0.05)))
                    x += spacing
                }
                y += spacing
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Surfaces

extension View {
    /// The standard card surface: solid fill, hairline border, no gradient.
    func panel(
        fill: Color = Theme.Palette.surface,
        radius: CGFloat = Theme.Metrics.cardRadius,
        stroke: Color? = nil
    ) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(stroke ?? Theme.Palette.stroke, lineWidth: 1)
                )
        )
    }

    func cardShadow() -> some View {
        shadow(color: Color.black.opacity(0.45), radius: 20, x: 0, y: 12)
    }
}
