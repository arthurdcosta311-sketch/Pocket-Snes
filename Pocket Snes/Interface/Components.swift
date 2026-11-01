//
//  Components.swift
//  Pocket Snes
//
//  Shared interface pieces: labels, cards, buttons, pills and rows.
//

import SwiftUI

// MARK: - Small caps label

struct RetroLabel: View {
    private let title: String
    private let color: Color
    private let size: CGFloat
    private let tracking: CGFloat

    init(_ text: String, color: Color = Theme.Palette.muted, size: CGFloat = 11, tracking: CGFloat = 1.8) {
        self.title = text
        self.color = color
        self.size = size
        self.tracking = tracking
    }

    var body: some View {
        Text(title.uppercased())
            .font(Theme.Face.mono(size, .semibold))
            .tracking(tracking)
            .foregroundStyle(color)
    }
}

// MARK: - Section header

struct SectionHeader<Trailing: View>: View {
    private let title: String
    private let trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            RetroLabel(title, color: Theme.Palette.muted, size: 10, tracking: 2.4)
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

// MARK: - Buttons

struct PocketButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
        case danger
    }

    var tint: Color = Theme.Palette.accent
    var height: CGFloat = 52
    var kind: Kind = .primary

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .font(Theme.Face.display(16, .bold))
            .kerning(0.2)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(background(isPressed: configuration.isPressed))
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(Theme.Motion.press, value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary:
            return Theme.Palette.ink
        case .secondary:
            return Theme.Palette.text
        case .danger:
            return Theme.Palette.red
        }
    }

    @ViewBuilder
    private func background(isPressed: Bool) -> some View {
        switch kind {
        case .primary:
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                )
                .shadow(
                    color: tint.opacity(0.45),
                    radius: isPressed ? 8 : 18,
                    x: 0,
                    y: isPressed ? 3 : 10
                )
        case .secondary:
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.Palette.raised)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                )
        case .danger:
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.Palette.red.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Theme.Palette.red.opacity(0.45), lineWidth: 1)
                )
        }
    }
}

struct ScaleButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Theme.Motion.press, value: configuration.isPressed)
    }
}

struct CircleIconButton: View {
    var systemName: String
    var size: CGFloat = 40
    var tint: Color = Theme.Palette.text
    var fill: Color = Theme.Palette.raised
    var action: () -> Void = {}

    var body: some View {
        Button {
            Haptics.select()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Circle().fill(fill))
                .overlay(Circle().strokeBorder(Theme.Palette.stroke, lineWidth: 1))
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Chips

struct TagChip: View {
    var text: String
    var tint: Color = Theme.Palette.muted
    var systemName: String?

    var body: some View {
        HStack(spacing: 5) {
            if let systemName {
                Image(systemName: systemName)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text.uppercased())
                .font(Theme.Face.mono(9, .semibold))
                .tracking(1.1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(tint.opacity(0.12))
                .overlay(Capsule().strokeBorder(tint.opacity(0.22), lineWidth: 1))
        )
    }
}

// MARK: - Progress

struct PlayProgressBar: View {
    var value: Double
    var tint: Color = Theme.Palette.accentSoft

    var body: some View {
        GeometryReader { geometry in
            let clamped = min(max(value, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.16))
                Capsule()
                    .fill(tint)
                    .frame(width: max(6, geometry.size.width * clamped))
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Pills

struct OptionPills<Option: Hashable>: View {
    let options: [Option]
    let label: (Option) -> String
    @Binding var selection: Option

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    Haptics.select()
                    withAnimation(Theme.Motion.smooth) {
                        selection = option
                    }
                } label: {
                    Text(label(option).uppercased())
                        .font(Theme.Face.mono(10, .bold))
                        .tracking(1.0)
                        .foregroundStyle(isSelected ? Theme.Palette.text : Theme.Palette.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isSelected ? Theme.Palette.accent : Theme.Palette.raised)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    isSelected ? Theme.Palette.accentSoft.opacity(0.5) : Color.clear,
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
    }
}

// MARK: - Icon tile

struct IconTile: View {
    var systemName: String
    var tint: Color = Theme.Palette.accent
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .fill(tint.opacity(0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .strokeBorder(tint.opacity(0.24), lineWidth: 1)
            )
    }
}

// MARK: - Stat tile

struct StatTile: View {
    var label: String
    var value: String
    var tint: Color = Theme.Palette.accentSoft

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RetroLabel(label, color: Theme.Palette.muted, size: 9, tracking: 1.4)
            Text(value)
                .font(Theme.Face.display(16, .bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 13)
        .panel(fill: Theme.Palette.surface, radius: 16)
    }
}

// MARK: - Settings rows

struct SettingToggleRow: View {
    var icon: String
    var tint: Color
    var title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 13) {
            IconTile(systemName: icon, tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.Face.text(15, .semibold))
                    .foregroundStyle(Theme.Palette.text)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Face.text(12))
                        .foregroundStyle(Theme.Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Theme.Palette.accent)
        }
        .padding(13)
        .panel(fill: Theme.Palette.surface, radius: 16)
    }
}

struct SettingSliderRow: View {
    var icon: String
    var tint: Color
    var title: String
    var valueLabel: String
    var range: ClosedRange<Double>
    @Binding var value: Double

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 13) {
                IconTile(systemName: icon, tint: tint)
                Text(title)
                    .font(Theme.Face.text(15, .semibold))
                    .foregroundStyle(Theme.Palette.text)
                Spacer(minLength: 8)
                Text(valueLabel)
                    .font(Theme.Face.mono(12, .semibold))
                    .foregroundStyle(Theme.Palette.accentSoft)
            }
            Slider(value: $value, in: range)
                .tint(Theme.Palette.accent)
        }
        .padding(13)
        .panel(fill: Theme.Palette.surface, radius: 16)
    }
}

struct SettingPillsRow<Option: Hashable>: View {
    var icon: String
    var tint: Color
    var title: String
    var subtitle: String
    var options: [Option]
    var label: (Option) -> String
    @Binding var selection: Option

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 13) {
                IconTile(systemName: icon, tint: tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Theme.Face.text(15, .semibold))
                        .foregroundStyle(Theme.Palette.text)
                    Text(subtitle)
                        .font(Theme.Face.text(12))
                        .foregroundStyle(Theme.Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
            }
            OptionPills(options: options, label: label, selection: $selection)
        }
        .padding(13)
        .panel(fill: Theme.Palette.surface, radius: 16)
    }
}


// MARK: - Press and hold

/// Wraps any label so it reports press *and* release, which is what the
/// emulator needs for buttons that stay held down.
struct HoldButton<Label: View>: View {
    var onState: (Bool) -> Void
    @ViewBuilder var label: () -> Label

    @State private var held = false

    var body: some View {
        label()
            .scaleEffect(held ? 0.94 : 1)
            .animation(Theme.Motion.press, value: held)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in set(true) }
                    .onEnded { _ in set(false) }
            )
    }

    private func set(_ down: Bool) {
        guard held != down else { return }
        held = down
        onState(down)
    }
}
