//
//  SnesPocketSkin.swift
//  Pocket Snes
//
//  The Pocket controller skin: a full-width console deck that fills the lower
//  half of the screen. D-pad on the left, lavender face buttons on the right,
//  shoulders and the console mark along the top rail.
//

import SwiftUI

// MARK: - Palette

/// The skin's own tones: a graphite shell with a violet cast, a recessed well
/// for the controls and lavender keys.
private enum PocketPalette {
    static let shell = Theme.rgb(0x14111E)
    static let well = Theme.rgb(0x0B0913)
    static let keyTop = Theme.rgb(0x2C2543)
    static let keyLip = Theme.rgb(0x1A1529)
    static let lavender = Theme.rgb(0x9B8AD6)
    static let lavenderRim = Theme.rgb(0x5F4E96)
    static let legend = Theme.rgb(0x1F1738)
}

// MARK: - Deck

struct SnesPocketDeck: View {
    @EnvironmentObject private var settings: AppSettings

    var onInput: (PadInput, Bool) -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            // Everything is sized from the deck so the skin fits a phone half
            // and a tablet half alike.
            let padSide = min(width * 0.34, height * 0.58)
            let clusterSide = min(width * 0.40, height * 0.66)
            let keyWidth = min(56, width * 0.15)

            VStack(spacing: 10) {
                if settings.showsShoulders {
                    shoulderRow
                }

                Spacer(minLength: 0)

                HStack(alignment: .center, spacing: 0) {
                    PocketDPad(onInput: onInput)
                        .frame(width: padSide, height: padSide)

                    Spacer(minLength: 4)

                    PocketSystemKeys(width: keyWidth, onInput: onInput)

                    Spacer(minLength: 4)

                    PocketFaceButtons(side: clusterSide, onInput: onInput)
                        .frame(width: clusterSide, height: clusterSide)
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 0)
            }
            .padding(.top, 12)
            .padding(.bottom, 22)
            .frame(width: width, height: height)
        }
        .background(shell)
        .clipShape(
            UnevenRoundedRectangle(topLeadingRadius: 34, topTrailingRadius: 34, style: .continuous)
        )
        .opacity(settings.controlOpacity)
    }

    private var shoulderRow: some View {
        HStack(spacing: 12) {
            PocketShoulderKey(title: "L", input: .l, onInput: onInput)

            Spacer(minLength: 0)

            RetroLabel("SNES", color: PocketPalette.lavender.opacity(0.45), size: 8, tracking: 3.2)

            Spacer(minLength: 0)

            PocketShoulderKey(title: "R", input: .r, onInput: onInput)
        }
        .padding(.horizontal, 16)
    }

    private var shell: some View {
        ZStack(alignment: .top) {
            PocketPalette.shell

            VStack(spacing: 0) {
                Rectangle()
                    .fill(PocketPalette.lavender.opacity(0.50))
                    .frame(height: 1.5)
                Rectangle()
                    .fill(Color.black.opacity(0.40))
                    .frame(height: 1)
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - D-pad

private struct PocketDPad: View {
    @EnvironmentObject private var settings: AppSettings

    var onInput: (PadInput, Bool) -> Void

    @State private var pressed: PadInput?

    private let armRatio: CGFloat = 0.34

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let arm = side * armRatio

            ZStack {
                Circle()
                    .fill(PocketPalette.well)
                    .overlay(Circle().strokeBorder(PocketPalette.keyLip, lineWidth: 1))
                    .shadow(color: .black.opacity(0.50), radius: 8, x: 0, y: 4)

                PocketCrossShape(armRatio: armRatio)
                    .fill(PocketPalette.keyTop)
                    .overlay(
                        PocketCrossShape(armRatio: armRatio)
                            .stroke(Color.white.opacity(0.09), lineWidth: 1)
                    )

                if let pressed {
                    highlight(for: pressed, side: side, arm: arm)
                }

                PocketCrossArrows(armRatio: armRatio)
                    .fill(PocketPalette.lavender.opacity(0.55))

                Circle()
                    .fill(Color.black.opacity(0.22))
                    .frame(width: arm * 0.52, height: arm * 0.52)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        update(at: value.location, side: side, arm: arm)
                    }
                    .onEnded { _ in
                        release()
                    }
            )
        }
    }

    private func highlight(for direction: PadInput, side: CGFloat, arm: CGFloat) -> some View {
        let offset = (side - arm) / 2
        let rect: CGRect

        switch direction {
        case .up:
            rect = CGRect(x: offset, y: 0, width: arm, height: offset + arm / 2)
        case .down:
            rect = CGRect(x: offset, y: offset + arm / 2, width: arm, height: side - offset - arm / 2)
        case .left:
            rect = CGRect(x: 0, y: offset, width: offset + arm / 2, height: arm)
        case .right:
            rect = CGRect(x: offset + arm / 2, y: offset, width: side - offset - arm / 2, height: arm)
        default:
            rect = .zero
        }

        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Theme.Palette.accent.opacity(0.55))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
        }
        .frame(width: side, height: side, alignment: .topLeading)
        .clipShape(PocketCrossShape(armRatio: armRatio))
    }

    private func update(at location: CGPoint, side: CGFloat, arm: CGFloat) {
        let center = CGPoint(x: side / 2, y: side / 2)
        let dx = location.x - center.x
        let dy = location.y - center.y
        let distance = (dx * dx + dy * dy).squareRoot()

        var next: PadInput?
        if distance > arm * 0.42 {
            if abs(dx) > abs(dy) {
                next = dx > 0 ? .right : .left
            } else {
                next = dy > 0 ? .down : .up
            }
        }

        guard next != pressed else { return }

        if let previous = pressed {
            onInput(previous, false)
        }
        pressed = next

        if let next {
            if settings.haptics { Haptics.press() }
            onInput(next, true)
        }
    }

    private func release() {
        if let previous = pressed {
            onInput(previous, false)
        }
        pressed = nil
    }
}

// MARK: - Face buttons

private struct PocketFaceButtons: View {
    @EnvironmentObject private var settings: AppSettings

    var side: CGFloat
    var onInput: (PadInput, Bool) -> Void

    private var diameter: CGFloat { side * 0.44 }
    private var radius: CGFloat { (side - diameter) / 2 }

    var body: some View {
        ZStack {
            Circle()
                .fill(PocketPalette.well)
                .overlay(Circle().strokeBorder(PocketPalette.keyLip, lineWidth: 1))
                .shadow(color: .black.opacity(0.50), radius: 8, x: 0, y: 4)

            faceButton("X", input: .x)
                .offset(y: -radius)
            faceButton("Y", input: .y)
                .offset(x: -radius)
            faceButton("A", input: .a)
                .offset(x: radius)
            faceButton("B", input: .b)
                .offset(y: radius)
        }
        .frame(width: side, height: side)
    }

    private func faceButton(_ title: String, input: PadInput) -> some View {
        HoldButton(onState: { down in
            if down, settings.haptics { Haptics.press() }
            onInput(input, down)
        }) {
            ZStack {
                Circle()
                    .fill(PocketPalette.lavender)
                    .overlay(Circle().strokeBorder(PocketPalette.lavenderRim, lineWidth: 2))
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                            .padding(4)
                    )

                Text(title)
                    .font(Theme.Face.display(diameter * 0.34, .heavy))
                    .foregroundStyle(PocketPalette.legend)
                    .offset(y: -diameter * 0.03)
            }
            .frame(width: diameter, height: diameter)
            .shadow(color: Color.black.opacity(0.55), radius: 6, x: 0, y: 4)
        }
    }
}

// MARK: - Select / Start

private struct PocketSystemKeys: View {
    @EnvironmentObject private var settings: AppSettings

    var width: CGFloat
    var onInput: (PadInput, Bool) -> Void

    var body: some View {
        VStack(spacing: 16) {
            key("SELECT", input: .select, angle: -8)
            key("START", input: .start, angle: 8)
        }
    }

    private func key(_ title: String, input: PadInput, angle: Double) -> some View {
        HoldButton(onState: { down in
            if down, settings.haptics { Haptics.press() }
            onInput(input, down)
        }) {
            Capsule()
                .fill(PocketPalette.keyTop)
                .frame(width: width, height: 26)
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                .overlay(
                    Text(title)
                        .font(Theme.Face.mono(7.5, .bold))
                        .tracking(1.1)
                        .foregroundStyle(PocketPalette.lavender.opacity(0.90))
                )
                .shadow(color: Color.black.opacity(0.45), radius: 5, x: 0, y: 3)
                .rotationEffect(.degrees(angle))
        }
    }
}

// MARK: - Shoulders

private struct PocketShoulderKey: View {
    @EnvironmentObject private var settings: AppSettings

    var title: String
    var input: PadInput
    var onInput: (PadInput, Bool) -> Void

    var body: some View {
        HoldButton(onState: { down in
            if down, settings.haptics { Haptics.press() }
            onInput(input, down)
        }) {
            Text(title)
                .font(Theme.Face.mono(12, .bold))
                .tracking(1.4)
                .foregroundStyle(PocketPalette.lavender.opacity(0.85))
                .frame(width: 78, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(PocketPalette.keyTop)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.45), radius: 5, x: 0, y: 3)
        }
    }
}

// MARK: - Shapes

/// The d-pad cross as one outline, so its stroke never draws across the middle.
private struct PocketCrossShape: Shape {
    var armRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let arm = side * armRatio
        let offset = (side - arm) / 2
        let corner = CGSize(width: arm * 0.24, height: arm * 0.24)
        let minX = rect.midX - side / 2
        let minY = rect.midY - side / 2

        let vertical = Path(
            roundedRect: CGRect(x: minX + offset, y: minY, width: arm, height: side),
            cornerSize: corner
        )
        let horizontal = Path(
            roundedRect: CGRect(x: minX, y: minY + offset, width: side, height: arm),
            cornerSize: corner
        )

        return vertical.union(horizontal)
    }
}

private struct PocketCrossArrows: Shape {
    var armRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let arm = side * armRatio
        let size = arm * 0.22
        let center = side / 2
        let minX = rect.midX - side / 2
        let minY = rect.midY - side / 2

        var path = Path()

        let upY = minY + arm * 0.92
        path.move(to: CGPoint(x: minX + center, y: upY - size * 0.8))
        path.addLine(to: CGPoint(x: minX + center - size * 0.70, y: upY + size * 0.20))
        path.addLine(to: CGPoint(x: minX + center + size * 0.70, y: upY + size * 0.20))
        path.closeSubpath()

        let downY = minY + side - arm * 0.92
        path.move(to: CGPoint(x: minX + center, y: downY + size * 0.8))
        path.addLine(to: CGPoint(x: minX + center - size * 0.70, y: downY - size * 0.20))
        path.addLine(to: CGPoint(x: minX + center + size * 0.70, y: downY - size * 0.20))
        path.closeSubpath()

        let leftX = minX + arm * 0.92
        path.move(to: CGPoint(x: leftX - size * 0.8, y: minY + center))
        path.addLine(to: CGPoint(x: leftX + size * 0.20, y: minY + center - size * 0.70))
        path.addLine(to: CGPoint(x: leftX + size * 0.20, y: minY + center + size * 0.70))
        path.closeSubpath()

        let rightX = minX + side - arm * 0.92
        path.move(to: CGPoint(x: rightX + size * 0.8, y: minY + center))
        path.addLine(to: CGPoint(x: rightX - size * 0.20, y: minY + center - size * 0.70))
        path.addLine(to: CGPoint(x: rightX - size * 0.20, y: minY + center + size * 0.70))
        path.closeSubpath()

        return path
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 0) {
            Spacer(minLength: 0)
            SnesPocketDeck(onInput: { _, _ in })
                .frame(height: 400)
        }
    }
    .environmentObject(AppSettings())
    .preferredColorScheme(.dark)
}
