//
//  EmulatorSurface.swift
//  Pocket Snes
//
//  The picture the engine produces: RGBA frames turned into an image and
//  scaled according to the display settings.
//

import SwiftUI
import CoreGraphics
import Foundation

// MARK: - Frame conversion

enum FrameRenderer {

    /// RGBA8, 256 x 224 -> CGImage. Called once per emulated frame.
    static func image(from pixels: [UInt8]) -> CGImage? {
        let width = PPU.width
        let height = PPU.height
        let bytesPerRow = width * 4
        guard pixels.count >= bytesPerRow * height else { return nil }

        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}

// MARK: - Surface

struct EmulatorSurface: View {
    var image: CGImage?
    var filter: VideoFilter = .sharp
    var fit: ScreenFit = .fit
    var scanlines: Bool = true

    private var aspect: CGFloat {
        CGFloat(PPU.width) / CGFloat(PPU.height)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                if let image {
                    picture(Image(decorative: image, scale: 1, orientation: .up), in: geometry.size)
                    if scanlines || filter == .crt {
                        Scanlines()
                    }
                } else {
                    loading
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .aspectRatio(Theme.Metrics.surfaceAspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.6), radius: 24, x: 0, y: 12)
    }

    @ViewBuilder
    private func picture(_ image: Image, in size: CGSize) -> some View {
        switch fit {
        case .fit:
            image
                .resizable()
                .interpolation(interpolation)
                .aspectRatio(aspect, contentMode: .fit)

        case .fill:
            image
                .resizable()
                .interpolation(interpolation)
                .aspectRatio(aspect, contentMode: .fill)
                .clipped()

        case .pixelPerfect:
            let scale = max(1, floor(min(size.width / CGFloat(PPU.width),
                                        size.height / CGFloat(PPU.height))))
            image
                .resizable()
                .interpolation(.none)
                .frame(width: CGFloat(PPU.width) * scale,
                       height: CGFloat(PPU.height) * scale)
        }
    }

    private var interpolation: Image.Interpolation {
        switch filter {
        case .sharp, .crt:
            return .none
        case .smooth:
            return .high
        }
    }

    private var loading: some View {
        VStack(spacing: 8) {
            Image(systemName: "hourglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.Palette.faint)
            Text("STARTING")
                .font(Theme.Face.mono(9, .bold))
                .tracking(1.6)
                .foregroundStyle(Theme.Palette.faint)
        }
    }
}
