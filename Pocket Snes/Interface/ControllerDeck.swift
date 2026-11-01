//
//  ControllerDeck.swift
//  Pocket Snes
//
//  The on-screen pad. Everything here reports a PadInput press or release; the
//  emulator session turns that into controller state.
//

import SwiftUI

enum PadInput: String, CaseIterable {
    case up, down, left, right
    case a, b, x, y
    case l, r, start, select
}

// MARK: - Deck

struct ControllerDeck: View {
    @EnvironmentObject private var settings: AppSettings

    var onInput: (PadInput, Bool) -> Void

    var body: some View {
        VStack(spacing: 14) {
            if settings.showsShoulders {
                HStack(spacing: 12) {
                    ShoulderButton(title: "L", input: .l, onInput: onInput)
                    Spacer(minLength: 0)
                    ShoulderButton(title: "R", input: .r, onInput: onInput)
                }
            }

            HStack(alignment: .center, spacing: 6) {
                DirectionalPad(onInput: onInput)
                    .frame(width: 104, height: 104)

                Spacer(minLength: 2)

                VStack(spacing: 10) {
                    PillControl(title: "SELECT", input: .select, onInput: onInput)
                    PillControl(title: "START", input: .start, onInput: onInput)
                }

                Spacer(minLength: 2)

                FaceButtons(onInput: onInput)
                    .frame(width: 100, height: 100)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Theme.Palette.deck)
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(Theme.Palette.stroke, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 22, x: 0, y: 12)
        )
        .opacity(settings.controlOpacity)
    }
}

// MARK: - D-pad

struct DirectionalPad: View {
    @EnvironmentObject private var settings: AppSettings

    var onInput: (PadInput, Bool) -> Void

    @State private var pressed: PadInput?

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let arm = side / 3
            let offset = (side - arm) / 2

            ZStack {
                crossPath(side: side, arm: arm, offset: offset)
                    .fill(Theme.Palette.raised)
                    .overlay(
                        crossPath(side: side, arm: arm, offset: offset)
                            .stroke(Theme.Palette.hairline, lineWidth: 1)
                    )

                if let pressed {
                    highlight(for: pressed, side: side, arm: arm, offset: offset)
                }

                arrowPath(side: side, arm: arm)
                    .fill(Theme.Palette.faint)

                Circle()
                    .fill(Theme.Palette.deck)
                    .frame(width: arm * 0.5, height: arm * 0.5)
                    .overlay(Circle().strokeBorder(Theme.Palette.stroke, lineWidth: 1))
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
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

    private func crossPath(side: CGFloat, arm: CGFloat, offset: CGFloat) -> Path {
        var path = Path()
        path.addRoundedRect(
            in: CGRect(x: offset, y: 0, width: arm, height: side),
            cornerSize: CGSize(width: 10, height: 10)
        )
        path.addRoundedRect(
            in: CGRect(x: 0, y: offset, width: side, height: arm),
            cornerSize: CGSize(width: 10, height: 10)
        )
        return path
    }

    private func arrowPath(side: CGFloat, arm: CGFloat) -> Path {
        let size = arm * 0.19
        let center = side / 2
        var path = Path()

        let upY = arm * 0.92
        path.move(to: CGPoint(x: center, y: upY - size * 0.8))
        path.addLine(to: CGPoint(x: center - size * 0.70, y: upY + size * 0.20))
        path.addLine(to: CGPoint(x: center + size * 0.70, y: upY + size * 0.20))
        path.closeSubpath()

        let downY = side - arm * 0.92
        path.move(to: CGPoint(x: center, y: downY + size * 0.8))
        path.addLine(to: CGPoint(x: center - size * 0.70, y: downY - size * 0.20))
        path.addLine(to: CGPoint(x: center + size * 0.70, y: downY - size * 0.20))
        path.closeSubpath()

        let leftX = arm * 0.92
        path.move(to: CGPoint(x: leftX - size * 0.8, y: center))
        path.addLine(to: CGPoint(x: leftX + size * 0.20, y: center - size * 0.70))
        path.addLine(to: CGPoint(x: leftX + size * 0.20, y: center + size * 0.70))
        path.closeSubpath()

        let rightX = side - arm * 0.92
        path.move(to: CGPoint(x: rightX + size * 0.8, y: center))
        path.addLine(to: CGPoint(x: rightX - size * 0.20, y: center - size * 0.70))
        path.addLine(to: CGPoint(x: rightX - size * 0.20, y: center + size * 0.70))
        path.closeSubpath()

        return path
    }

    private func highlight(for direction: PadInput, side: CGFloat, arm: CGFloat, offset: CGFloat) -> some View {
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

        return RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Theme.Palette.accent.opacity(0.65))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }

    private func update(at location: CGPoint, side: CGFloat, arm: CGFloat) {
        let center = CGPoint(x: side / 2, y: side / 2)
        let dx = location.x - center.x
        let dy = location.y - center.y
        let distance = (dx * dx + dy * dy).squareRoot()

        var next: PadInput?
        if distance > arm * 0.45 {
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

struct FaceButtons: View {
    @EnvironmentObject private var settings: AppSettings

    var onInput: (PadInput, Bool) -> Void

    private let diameter: CGFloat = 40
    private let radius: CGFloat = 30

    var body: some View {
        ZStack {
            faceButton("X", tint: Theme.Palette.blue, input: .x)
                .offset(y: -radius)
            faceButton("Y", tint: Theme.Palette.green, input: .y)
                .offset(x: -radius)
            faceButton("A", tint: Theme.Palette.red, input: .a)
                .offset(x: radius)
            faceButton("B", tint: Theme.Palette.yellow, input: .b)
                .offset(y: radius)
        }
        .frame(width: radius * 2 + diameter, height: radius * 2 + diameter)
    }

    private func faceButton(_ title: String, tint: Color, input: PadInput) -> some View {
        HoldButton(onState: { down in
            if down, settings.haptics { Haptics.press() }
            onInput(input, down)
        }) {
            Text(title)
                .font(Theme.Face.display(15, .heavy))
                .foregroundStyle(Theme.Palette.ink.opacity(0.92))
                .frame(width: diameter, height: diameter)
                .background(
                    Circle()
                        .fill(tint)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.30), lineWidth: 1))
                        .shadow(color: tint.opacity(0.35), radius: 10, x: 0, y: 5)
                )
        }
    }
}

// MARK: - Small controls

struct PillControl: View {
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
                .font(Theme.Face.mono(8, .bold))
                .tracking(1.1)
                .foregroundStyle(Theme.Palette.muted)
                .frame(width: 58, height: 26)
                .background(Capsule().fill(Theme.Palette.raised))
                .overlay(Capsule().strokeBorder(Theme.Palette.stroke, lineWidth: 1))
        }
    }
}

struct ShoulderButton: View {
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
                .foregroundStyle(Theme.Palette.muted)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Theme.Palette.raised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Theme.Palette.stroke, lineWidth: 1)
                )
        }
        .frame(width: 92)
    }
}
