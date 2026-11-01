//
//  GameDetailView.swift
//  Pocket Snes
//
//  A game's page: art, details, save states and the way into the player.
//

import SwiftUI

struct GameDetailView: View {
    @EnvironmentObject private var library: GameLibrary
    @EnvironmentObject private var session: PlaySession
    @Environment(\.dismiss) private var dismiss

    let game: RetroGame

    private var current: RetroGame {
        library.game(withID: game.id) ?? game
    }

    var body: some View {
        ZStack {
            ScreenBackground(showsGlow: false)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    hero
                    titleBlock
                    playRow
                    statsRow
                    saveStatesSection
                    aboutSection
                }
                .padding(.horizontal, Theme.Metrics.gutter)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Hero

    private var hero: some View {
        GameArtwork(art: current.art)
            .frame(height: 232)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.Palette.text)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                        .overlay(Circle().strokeBorder(Theme.Palette.hairline, lineWidth: 1))
                }
                .buttonStyle(ScaleButtonStyle())
                .padding(12)
            }
            .cardShadow()
    }

    // MARK: Title

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(current.title)
                .font(Theme.Face.display(26, .heavy))
                .foregroundStyle(Theme.Palette.text)
                .fixedSize(horizontal: false, vertical: true)

            if !current.tagline.isEmpty {
                Text(current.tagline)
                    .font(Theme.Face.text(14))
                    .foregroundStyle(Theme.Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 7) {
                TagChip(text: current.system.shortName, tint: Theme.Palette.accentSoft)
                TagChip(text: "\(current.year)", tint: Theme.Palette.muted)
                if current.players > 1 {
                    TagChip(text: current.playersLabel, tint: Theme.Palette.mint)
                }
            }
            .padding(.top, 2)
        }
    }

    // MARK: Play

    private var playRow: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.press()
                library.markPlayed(current.id)
                session.start(current)
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text(current.lastPlayed == nil ? "Start playing" : "Resume")
                }
            }
            .buttonStyle(PocketButtonStyle(height: 54))

            CircleIconButton(
                systemName: current.isFavorite ? "heart.fill" : "heart",
                size: 54,
                tint: current.isFavorite ? Theme.Palette.red : Theme.Palette.text
            ) {
                withAnimation(Theme.Motion.smooth) {
                    library.toggleFavorite(current.id)
                }
            }
        }
    }

    // MARK: Stats

    private var statsRow: some View {
        HStack(spacing: 10) {
            StatTile(label: "Played", value: current.playTimeLabel)
            StatTile(label: "Players", value: "\(current.players)", tint: Theme.Palette.mint)
            StatTile(label: "Size", value: current.fileSize, tint: Theme.Palette.text)
        }
    }

    // MARK: Save states

    private var saveStatesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Save states")
            if current.saveStates.isEmpty {
                HStack(spacing: 12) {
                    IconTile(systemName: "clock", tint: Theme.Palette.faint, size: 32)
                    Text("No save states yet. Save one from the pause menu while playing.")
                        .font(Theme.Face.text(13))
                        .foregroundStyle(Theme.Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(13)
                .panel(fill: Theme.Palette.surface, radius: 16)
            } else {
                VStack(spacing: 8) {
                    ForEach(current.saveStates) { state in
                        saveStateRow(state)
                    }
                }
            }
        }
    }

    private func saveStateRow(_ state: SaveState) -> some View {
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
                Haptics.select()
                library.markPlayed(current.id)
                session.start(current, loadingSlot: state.slot)
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

    // MARK: About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("About")
            Text(current.blurb)
                .font(Theme.Face.text(13))
                .foregroundStyle(Theme.Palette.muted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .panel(fill: Theme.Palette.surface, radius: 16)
        }
    }
}
