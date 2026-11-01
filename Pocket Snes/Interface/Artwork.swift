//
//  Artwork.swift
//  Pocket Snes
//
//  Cover art and the emulator surface stand-in. Art is generated from a seed so
//  a game always looks the same between launches; the scene is also what fills
//  the player until the engine view is dropped in.
//

import SwiftUI

// MARK: - Art description

struct GameArt: Hashable, Codable {
    var seed: Int
    var sky: UInt32
    var land: UInt32
    var sun: UInt32
    var accent: UInt32
    var symbol: String
}

// MARK: - Deterministic randomness

struct SeededRandom {
    private var state: UInt64

    init(seed: Int) {
        state = UInt64(bitPattern: Int64(seed)) &* 0x9E37_79B9_7F4A_7C15 &+ 0x2545_F491_4F6C_DD1D
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }

    /// 0 ..< 1
    mutating func unit() -> CGFloat {
        CGFloat(next() >> 40) / CGFloat(1 << 24)
    }

    mutating func value(_ range: ClosedRange<CGFloat>) -> CGFloat {
        range.lowerBound + unit() * (range.upperBound - range.lowerBound)
    }
}

// MARK: - Artwork

struct GameArtwork: View {
    let art: GameArt

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
        .background(Theme.rgb(art.sky))
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        let width = size.width
        let height = size.height
        var random = SeededRandom(seed: art.seed)

        // Sky
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .color(Theme.rgb(art.sky))
        )

        // Sun, with a soft halo drawn as a few fading circles
        let sunCenter = CGPoint(x: width * 0.72, y: height * 0.30)
        let sunRadius = width * 0.115
        for step in stride(from: 3.4, through: 1.6, by: -0.45) {
            let radius = sunRadius * CGFloat(step)
            let alpha = 0.06 * Double(3.4 - step + 0.45) / 3.4
            context.fill(
                Path(ellipseIn: CGRect(
                    x: sunCenter.x - radius,
                    y: sunCenter.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )),
                with: .color(Theme.rgb(art.sun, alpha + 0.04))
            )
        }
        context.fill(
            Path(ellipseIn: CGRect(
                x: sunCenter.x - sunRadius,
                y: sunCenter.y - sunRadius,
                width: sunRadius * 2,
                height: sunRadius * 2
            )),
            with: .color(Theme.rgb(art.sun))
        )

        // Two pixel-art hill ranges, drawn as vertical bars so the skyline is
        // chunky rather than smooth.
        drawRange(
            in: &context,
            size: size,
            baseline: height * 0.62,
            amplitude: height * 0.20,
            phase: 1.4,
            bars: 34,
            color: Theme.rgb(art.land, 0.45),
            random: &random
        )
        drawRange(
            in: &context,
            size: size,
            baseline: height * 0.74,
            amplitude: height * 0.16,
            phase: 3.9,
            bars: 22,
            color: Theme.rgb(art.land),
            random: &random
        )

        // Ground
        context.fill(
            Path(CGRect(x: 0, y: height * 0.80, width: width, height: height * 0.20)),
            with: .color(Theme.rgb(art.land))
        )
        context.fill(
            Path(CGRect(x: 0, y: height * 0.80, width: width, height: max(2, height * 0.012))),
            with: .color(Theme.rgb(art.accent, 0.85))
        )

        // Floating pixel blocks
        let blockCount = 5
        for index in 0..<blockCount {
            let blockSize = width * random.value(0.035...0.075)
            let x = width * random.value(0.06...0.86)
            let y = height * random.value(0.14...0.52)
            context.fill(
                Path(CGRect(x: x, y: y, width: blockSize, height: blockSize)),
                with: .color(Theme.rgb(art.accent, index % 2 == 0 ? 0.85 : 0.4))
            )
        }

        // A tiny hero sprite standing on the ground
        let sprite = width * 0.055
        let spriteX = width * 0.24
        let spriteY = height * 0.80 - sprite * 2.1
        let spriteColor = Theme.rgb(art.accent)
        context.fill(Path(CGRect(x: spriteX + sprite * 0.3, y: spriteY, width: sprite, height: sprite)), with: .color(spriteColor))
        context.fill(Path(CGRect(x: spriteX, y: spriteY + sprite * 1.05, width: sprite * 1.6, height: sprite * 0.95)), with: .color(spriteColor))
        context.fill(Path(CGRect(x: spriteX + sprite * 0.1, y: spriteY + sprite * 2, width: sprite * 0.55, height: sprite * 0.6)), with: .color(spriteColor))
        context.fill(Path(CGRect(x: spriteX + sprite * 0.95, y: spriteY + sprite * 2, width: sprite * 0.55, height: sprite * 0.6)), with: .color(spriteColor))

        // Scanline texture
        var lineY: CGFloat = 0
        while lineY < height {
            context.fill(
                Path(CGRect(x: 0, y: lineY, width: width, height: 1)),
                with: .color(.black.opacity(0.10))
            )
            lineY += 3
        }
    }

    private func drawRange(
        in context: inout GraphicsContext,
        size: CGSize,
        baseline: CGFloat,
        amplitude: CGFloat,
        phase: CGFloat,
        bars: Int,
        color: Color,
        random: inout SeededRandom
    ) {
        let barWidth = size.width / CGFloat(bars)
        for index in 0..<bars {
            let t = CGFloat(index) / CGFloat(bars)
            let wave = (sin(t * .pi * 4 + phase) + 1) / 2
            let jitter = random.value(-0.16...0.16)
            let barHeight = max(barWidth * 0.5, amplitude * (wave + jitter))
            let rect = CGRect(
                x: CGFloat(index) * barWidth,
                y: baseline - barHeight,
                width: barWidth + 0.5,
                height: barHeight + (size.height - baseline)
            )
            context.fill(Path(rect), with: .color(color))
        }
    }
}

struct Scanlines: View {
    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                context.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                    with: .color(.black.opacity(0.22))
                )
                y += 3
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Generated art for imported titles

extension GameArt {
    static func generated(for title: String) -> GameArt {
        let seed = stableSeed(title)
        let palettes: [(sky: UInt32, land: UInt32, sun: UInt32, accent: UInt32)] = [
            (0x2E5FAF, 0x3FA34D, 0xFFD65C, 0xFFC94A),
            (0x1B1030, 0x4B2C7A, 0xC9B8FF, 0x35E0A1),
            (0x0B1B33, 0x2C4B7A, 0xE8D48B, 0xFF5C5C),
            (0x2B1B4E, 0x6B4FA0, 0xF2EEE4, 0xFFC94A),
            (0x123A3A, 0x2E7A6B, 0x7BF0C0, 0x35E0A1),
            (0x3A1220, 0x8B2B3C, 0xFFC94A, 0xFF9A5C)
        ]
        let symbols = [
            "star.fill", "bolt.fill", "leaf.fill", "flame.fill",
            "moon.stars.fill", "airplane", "sparkles", "shield.lefthalf.filled"
        ]
        let palette = palettes[seed % palettes.count]
        return GameArt(
            seed: seed,
            sky: palette.sky,
            land: palette.land,
            sun: palette.sun,
            accent: palette.accent,
            symbol: symbols[seed % symbols.count]
        )
    }

    static func stableSeed(_ text: String) -> Int {
        var hash = 5381
        for scalar in text.unicodeScalars {
            hash = (hash &* 33) &+ Int(scalar.value)
        }
        return abs(hash % 9973) + 1
    }
}
