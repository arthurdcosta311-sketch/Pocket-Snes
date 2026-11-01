//
//  SettingsView.swift
//  Pocket Snes
//
//  Display, audio and control preferences, styled as cards.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var testResults: [String]?

    var body: some View {
        ZStack {
            ScreenBackground(showsGlow: false)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    displaySection
                    audioSection
                    controlsSection
                    engineSection
                    aboutCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .sheet(
            isPresented: Binding(
                get: { testResults != nil },
                set: { newValue in if !newValue { testResults = nil } }
            )
        ) {
            EngineTestSheet(results: testResults ?? [])
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("POCKET SNES")
                    .font(Theme.Face.mono(10, .bold))
                    .tracking(3.4)
                    .foregroundStyle(Theme.Palette.accentSoft)
                Text("Settings")
                    .font(Theme.Face.display(28, .heavy))
                    .foregroundStyle(Theme.Palette.text)
            }
            Spacer(minLength: 8)
            CircleIconButton(systemName: "xmark", size: 38) {
                dismiss()
            }
        }
    }

    // MARK: Sections

    private var displaySection: some View {
        section("Display") {
            SettingPillsRow(
                icon: "display",
                tint: Theme.Palette.blue,
                title: "Video filter",
                subtitle: "How the picture is scaled to the screen.",
                options: VideoFilter.allCases,
                label: { $0.title },
                selection: $settings.videoFilter
            )

            SettingPillsRow(
                icon: "arrow.up.left.and.arrow.down.right",
                tint: Theme.Palette.mint,
                title: "Screen fit",
                subtitle: "Fill trims a little, Fit keeps the whole frame.",
                options: ScreenFit.allCases,
                label: { $0.title },
                selection: $settings.screenFit
            )

            SettingToggleRow(
                icon: "rectangle.on.rectangle",
                tint: Theme.Palette.accentSoft,
                title: "Scanlines",
                subtitle: "A CRT texture over the emulator surface.",
                isOn: $settings.scanlines
            )
        }
    }

    private var audioSection: some View {
        section("Audio") {
            SettingSliderRow(
                icon: "speaker.wave.2.fill",
                tint: Theme.Palette.yellow,
                title: "Volume",
                valueLabel: settings.volumeLabel,
                range: 0...1,
                value: $settings.volume
            )

            SettingToggleRow(
                icon: "speaker.slash.fill",
                tint: Theme.Palette.red,
                title: "Mute",
                subtitle: "Silences the emulator without losing game audio state.",
                isOn: $settings.muted
            )
        }
    }

    private var controlsSection: some View {
        section("Controls") {
            SettingPillsRow(
                icon: "gamecontroller.fill",
                tint: Theme.Palette.accentSoft,
                title: "Controller skin",
                subtitle: "Pocket fills the lower half of the screen. Classic floats a deck over the picture.",
                options: ControllerSkin.allCases,
                label: { $0.title },
                selection: $settings.controlSkin
            )

            SettingSliderRow(
                icon: "circle.lefthalf.filled",
                tint: Theme.Palette.accentSoft,
                title: "Control opacity",
                valueLabel: settings.controlOpacityLabel,
                range: 0.4...1.0,
                value: $settings.controlOpacity
            )

            SettingToggleRow(
                icon: "hand.tap.fill",
                tint: Theme.Palette.mint,
                title: "Haptics",
                subtitle: "A light tap for every button press.",
                isOn: $settings.haptics
            )

            SettingToggleRow(
                icon: "capsule",
                tint: Theme.Palette.blue,
                title: "Shoulder buttons",
                subtitle: "Show L and R on the console deck.",
                isOn: $settings.showsShoulders
            )
        }
    }

    private var engineSection: some View {
        section("Engine") {
            Button {
                Haptics.select()
                testResults = EngineSelfTest.run()
            } label: {
                HStack(spacing: 13) {
                    IconTile(systemName: "cpu", tint: Theme.Palette.mint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Run engine self-test")
                            .font(Theme.Face.text(15, .semibold))
                            .foregroundStyle(Theme.Palette.text)
                        Text("Checks the CPU and PPU without a cartridge.")
                            .font(Theme.Face.text(12))
                            .foregroundStyle(Theme.Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Theme.Palette.accentSoft)
                }
                .padding(13)
                .panel(fill: Theme.Palette.surface, radius: 16)
            }
            .buttonStyle(ScaleButtonStyle())
        }
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                IconTile(systemName: "gamecontroller.fill", tint: Theme.Palette.accentSoft, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pocket Snes")
                        .font(Theme.Face.text(15, .semibold))
                        .foregroundStyle(Theme.Palette.text)
                    Text("Version \(appVersion)")
                        .font(Theme.Face.mono(10, .medium))
                        .foregroundStyle(Theme.Palette.muted)
                }
                Spacer(minLength: 8)
            }
            Text("A small, quiet place for sixteen-bit games. Bring your own ROMs.")
                .font(Theme.Face.text(12))
                .foregroundStyle(Theme.Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .panel(fill: Theme.Palette.surface, radius: 18)
    }

    // MARK: Helpers

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            RetroLabel(title, color: Theme.Palette.muted, size: 10, tracking: 2.4)
            VStack(spacing: 8) {
                content()
            }
        }
    }

    private var appVersion: String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

// MARK: - Engine self-test

struct EngineTestSheet: View {
    @Environment(\.dismiss) private var dismiss

    let results: [String]

    private var failures: Int {
        results.filter { $0.hasPrefix("FAIL") }.count
    }

    var body: some View {
        ZStack {
            ScreenBackground(showsGlow: false)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    ForEach(results, id: \.self) { line in
                        HStack(spacing: 10) {
                            Image(systemName: line.hasPrefix("PASS") ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(line.hasPrefix("PASS") ? Theme.Palette.mint : Theme.Palette.red)
                            Text(line)
                                .font(Theme.Face.mono(11, .medium))
                                .foregroundStyle(Theme.Palette.text)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .panel(fill: Theme.Palette.surface, radius: 12)
                    }
                }
                .padding(20)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                RetroLabel("Engine self-test", color: Theme.Palette.muted, size: 10, tracking: 2.4)
                Text(failures == 0 ? "All checks passed" : "\(failures) check(s) failed")
                    .font(Theme.Face.display(20, .heavy))
                    .foregroundStyle(failures == 0 ? Theme.Palette.mint : Theme.Palette.red)
            }
            Spacer(minLength: 8)
            CircleIconButton(systemName: "xmark", size: 36) {
                dismiss()
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings())
        .preferredColorScheme(.dark)
}
