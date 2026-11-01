//
//  PlayerView.swift
//  Pocket Snes
//
//  The player: the running console on top, console deck below, pause menu
//  behind the START button.
//

import SwiftUI

struct PlayerView: View {
    @EnvironmentObject private var library: GameLibrary
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var session: PlaySession
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.scenePhase) private var scenePhase

    let game: RetroGame

    @StateObject private var emulator = EmulatorSession()
    @State private var showingPause = false

    private var current: RetroGame {
        library.game(withID: game.id) ?? game
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if verticalSizeClass == .compact {
                landscapeBody
            } else {
                portraitBody
            }
        }
        .statusBarHidden(true)
        .onAppear {
            boot()
        }
        .onDisappear {
            emulator.releaseAllButtons()
            emulator.stop()
        }
        .onChange(of: showingPause) { _, isShowing in
            emulator.releaseAllButtons()
            if isShowing {
                emulator.pause()
            } else {
                emulator.resume()
            }
        }
        .onChange(of: settings.volume) { _, value in
            emulator.audio.volume = Float(value)
        }
        .onChange(of: settings.muted) { _, muted in
            emulator.audio.muted = muted
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                if !showingPause { emulator.resume() }
            case .inactive, .background:
                emulator.pause()
            @unknown default:
                break
            }
        }
        .sheet(isPresented: $showingPause) {
            PauseMenuView(game: current)
                .environmentObject(emulator)
        }
    }

    // MARK: - Boot

    /// Loads the stored ROM into a fresh core, or reports that the title has
    /// none attached.
    private func boot() {
        library.markPlayed(game.id)
        emulator.applyAudioSettings(volume: settings.volume, muted: settings.muted)

        if let romID = current.romID, let rom = ROMStore.shared.data(for: romID) {
            emulator.start(rom: rom)
            restorePendingSlot()
            return
        }

        emulator.markUnavailable()
    }

    /// A slot the library asked for is loaded as soon as the core is up.
    private func restorePendingSlot() {
        guard let slot = session.pendingSlot,
              let data = SaveStateStore.shared.data(gameID: game.id, slot: slot) else {
            session.pendingSlot = nil
            return
        }
        _ = emulator.restoreState(data)
        session.pendingSlot = nil
    }

    // MARK: Layouts

    /// The picture takes the upper half; the skin owns the lower half, edge to
    /// edge, so the deck reads as the body of a handheld.
    private var portraitBody: some View {
        GeometryReader { geometry in
            let halfHeight = geometry.size.height / 2

            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    topBar
                    Spacer(minLength: 0)
                    stage
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .frame(height: halfHeight)

                deck
                    .frame(height: halfHeight)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    @ViewBuilder
    private var deck: some View {
        switch settings.controlSkin {
        case .snesPocket:
            SnesPocketDeck(onInput: handleInput)
        case .classic:
            ControllerDeck(onInput: handleInput)
                .padding(.horizontal, 14)
                .padding(.bottom, 32)
        }
    }

    private var landscapeBody: some View {
        VStack(spacing: 6) {
            topBar

            ZStack {
                stage

                HStack(alignment: .bottom, spacing: 8) {
                    DirectionalPad(onInput: handleInput)
                        .frame(width: 100, height: 100)

                    Spacer(minLength: 0)

                    VStack(spacing: 8) {
                        PillControl(title: "SELECT", input: .select, onInput: handleInput)
                        PillControl(title: "START", input: .start, onInput: handleInput)
                    }

                    Spacer(minLength: 0)

                    FaceButtons(onInput: handleInput)
                        .frame(width: 100, height: 100)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 2)
                .opacity(settings.controlOpacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: 10) {
            CircleIconButton(systemName: "chevron.left", size: 36, fill: Color.white.opacity(0.08)) {
                emulator.stop()
                session.stop()
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(current.title)
                    .font(Theme.Face.text(13, .semibold))
                    .foregroundStyle(Theme.Palette.text)
                    .lineLimit(1)
                Text(statusLabel)
                    .font(Theme.Face.mono(8, .medium))
                    .tracking(1.3)
                    .foregroundStyle(Theme.Palette.muted)
            }

            Spacer(minLength: 8)

            CircleIconButton(systemName: "pause.fill", size: 36, fill: Color.white.opacity(0.08)) {
                showingPause = true
            }
        }
    }

    private var statusLabel: String {
        switch emulator.status {
        case .running:
            return emulator.fps > 0 ? "\(emulator.fps) FPS" : "RUNNING"
        case .paused:
            return "PAUSED"
        case .unavailable:
            return "NO ROM"
        case .failed(let message):
            return message.uppercased()
        case .idle:
            return current.system.shortName
        }
    }

    private var stage: some View {
        Group {
            if emulator.status == .unavailable {
                missingROM
            } else {
                EmulatorSurface(
                    image: emulator.image,
                    filter: settings.videoFilter,
                    fit: settings.screenFit,
                    scanlines: settings.scanlines
                )
            }
        }
    }

    /// Shown when a title has a stored ROM that is no longer on disk: the
    /// artwork stands in, with a straight answer and a way to see the console.
    private var missingROM: some View {
        ZStack {
            GameArtwork(art: game.art)
            Color.black.opacity(0.55)

            VStack(spacing: 9) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.Palette.accentSoft)
                Text("ROM file missing")
                    .font(Theme.Face.display(16, .bold))
                    .foregroundStyle(Theme.Palette.text)
                Text("This title's cartridge is no longer in storage. Import it again from Files.")
                    .font(Theme.Face.text(12))
                    .foregroundStyle(Theme.Palette.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 26)
            }
            .padding(.horizontal, 16)
        }
        .aspectRatio(Theme.Metrics.surfaceAspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: Input

    private func handleInput(_ input: PadInput, _ pressed: Bool) {
        emulator.setButton(input, pressed: pressed)
        if input == .start, pressed {
            showingPause = true
        }
    }
}

// MARK: - Pause menu

struct PauseMenuView: View {
    @EnvironmentObject private var session: PlaySession
    @EnvironmentObject private var library: GameLibrary
    @EnvironmentObject private var emulator: EmulatorSession
    @Environment(\.dismiss) private var dismiss

    let game: RetroGame

    @State private var showingSettings = false
    @State private var notice: String?

    private var current: RetroGame {
        library.game(withID: game.id) ?? game
    }

    var body: some View {
        ZStack {
            ScreenBackground(showsGlow: false)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    Button("Resume") {
                        dismiss()
                    }
                    .buttonStyle(PocketButtonStyle())

                    saveStates

                    HStack(spacing: 12) {
                        Button("Settings") {
                            showingSettings = true
                        }
                        .buttonStyle(PocketButtonStyle(kind: .secondary))

                        Button("Quit") {
                            dismiss()
                            session.stop()
                        }
                        .buttonStyle(PocketButtonStyle(kind: .danger))
                    }
                }
                .padding(20)
                .padding(.top, 4)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .alert(
            "Save states",
            isPresented: Binding(
                get: { notice != nil },
                set: { newValue in if !newValue { notice = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(notice ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            GameArtwork(art: game.art)
                .frame(width: 62, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.Palette.stroke, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 3) {
                RetroLabel("Paused", color: Theme.Palette.accentSoft)
                Text(current.title)
                    .font(Theme.Face.display(18, .bold))
                    .foregroundStyle(Theme.Palette.text)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            CircleIconButton(systemName: "xmark", size: 36) {
                dismiss()
            }
        }
    }

    private var saveStates: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeader("Save states") {
                Button {
                    saveState()
                } label: {
                    Text("SAVE")
                        .font(Theme.Face.mono(9, .bold))
                        .tracking(1.1)
                        .foregroundStyle(Theme.Palette.accentSoft)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Theme.Palette.accent.opacity(0.18)))
                        .overlay(Capsule().strokeBorder(Theme.Palette.accent.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(ScaleButtonStyle())
            }

            if current.saveStates.isEmpty {
                HStack(spacing: 12) {
                    IconTile(systemName: "square.and.arrow.down", tint: Theme.Palette.faint, size: 32)
                    Text("No save states for this title yet.")
                        .font(Theme.Face.text(13))
                        .foregroundStyle(Theme.Palette.muted)
                    Spacer(minLength: 0)
                }
                .padding(13)
                .panel(fill: Theme.Palette.surface, radius: 16)
            } else {
                ForEach(current.saveStates) { state in
                    HStack(spacing: 12) {
                        IconTile(systemName: "clock", tint: Theme.Palette.mint, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(state.label)
                                .font(Theme.Face.text(14, .semibold))
                                .foregroundStyle(Theme.Palette.text)
                                .lineLimit(1)
                            Text("Slot \(state.slot) · \(RelativeTime.label(state.date))")
                                .font(Theme.Face.mono(9, .medium))
                                .foregroundStyle(Theme.Palette.muted)
                        }
                        Spacer(minLength: 6)
                        Button {
                            loadState(state)
                        } label: {
                            Text("LOAD")
                                .font(Theme.Face.mono(9, .bold))
                                .tracking(1.1)
                                .foregroundStyle(Theme.Palette.accentSoft)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Theme.Palette.accent.opacity(0.18)))
                                .overlay(Capsule().strokeBorder(Theme.Palette.accent.opacity(0.35), lineWidth: 1))
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                    .padding(13)
                    .panel(fill: Theme.Palette.surface, radius: 16)
                }
            }
        }
    }

    // MARK: Save / load

    private func saveState() {
        guard emulator.status != .unavailable else {
            notice = "There is no ROM running to save."
            return
        }
        guard let data = emulator.captureState() else {
            notice = "The emulator is not ready to save yet."
            return
        }

        let slot = SaveStateStore.shared.nextSlot(gameID: game.id, existing: current.saveStates)
        let state = SaveState(slot: slot, label: "Slot \(slot)", date: Date())
        if SaveStateStore.shared.save(data, gameID: game.id, slot: slot) {
            library.setSaveState(state, for: game.id)
            notice = "Saved to slot \(slot)."
        } else {
            notice = "The save state could not be written."
        }
    }

    private func loadState(_ state: SaveState) {
        guard let data = SaveStateStore.shared.data(gameID: game.id, slot: state.slot) else {
            notice = "That slot is empty."
            return
        }
        if emulator.restoreState(data) {
            dismiss()
        } else {
            notice = "That save state could not be read."
        }
    }
}

#Preview {
    PlayerView(game: RetroGame(title: "Preview Game", art: .generated(for: "Preview Game")))
        .environmentObject(GameLibrary())
        .environmentObject(AppSettings())
        .environmentObject(PlaySession())
}
