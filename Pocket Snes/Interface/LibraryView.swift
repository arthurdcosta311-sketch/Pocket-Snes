//
//  LibraryView.swift
//  Pocket Snes
//
//  The home screen: resume card, search, and the grid of games.
//

import SwiftUI
import Foundation
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var library: GameLibrary
    @EnvironmentObject private var session: PlaySession

    @State private var searchText = ""
    @State private var sort: LibrarySort = .recent
    @State private var showingSettings = false
    @State private var showingImporter = false
    @State private var importNotice: String?

    private let columns = [
        GridItem(.flexible(), spacing: Theme.Metrics.gridSpacing),
        GridItem(.flexible(), spacing: Theme.Metrics.gridSpacing)
    ]

    private var visibleGames: [RetroGame] {
        let filtered: [RetroGame]
        if searchText.isEmpty {
            filtered = library.games
        } else {
            filtered = library.games.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }

        switch sort {
        case .recent:
            return filtered.sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
        case .alphabetical:
            return filtered.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .mostPlayed:
            return filtered.sorted { $0.playTime > $1.playTime }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Metrics.sectionGap) {
                        header
                        searchField

                        if let recent = library.recentlyPlayed {
                            Button {
                                Haptics.select()
                                library.markPlayed(recent.id)
                                session.start(recent)
                            } label: {
                                continueCard(recent)
                            }
                            .buttonStyle(ScaleButtonStyle())
                        }

                        gamesSection
                        footer
                    }
                    .padding(.horizontal, Theme.Metrics.gutter)
                    .padding(.top, 10)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: RetroGame.self) { game in
                GameDetailView(game: game)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                let imported = importROMs(at: urls)
                importNotice = importMessage(for: imported, of: urls.count)
            case .failure:
                break
            }
        }
        .alert(
            "Library updated",
            isPresented: Binding(
                get: { importNotice != nil },
                set: { newValue in if !newValue { importNotice = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importNotice ?? "")
        }
    }

    // MARK: Import

    /// Reads each picked file, stores its bytes and adds a library entry that
    /// points at them. Files that cannot be read are counted, not silently lost.
    private func importROMs(at urls: [URL]) -> [RetroGame] {
        var imported: [RetroGame] = []

        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            guard let raw = try? Data(contentsOf: url), !raw.isEmpty else { continue }
            guard let romID = try? ROMStore.shared.save(raw) else { continue }

            let game = RetroGame.imported(
                from: url,
                romID: romID,
                sizeLabel: ROMStore.shared.sizeLabel(for: romID)
            )
            imported.append(game)
        }

        if !imported.isEmpty {
            library.add(imported)
        }
        return imported
    }

    private func importMessage(for imported: [RetroGame], of attempted: Int) -> String {
        if imported.isEmpty {
            return "That file could not be read as a ROM."
        }
        if imported.count == 1 {
            return "\(imported[0].title) is in your library."
        }
        if imported.count < attempted {
            return "\(imported.count) games added. \(attempted - imported.count) file(s) could not be read."
        }
        return "\(imported.count) games are in your library."
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("POCKET SNES")
                    .font(Theme.Face.mono(10, .bold))
                    .tracking(3.6)
                    .foregroundStyle(Theme.Palette.accentSoft)
                Text("Library")
                    .font(Theme.Face.display(34, .heavy))
                    .foregroundStyle(Theme.Palette.text)
            }
            Spacer(minLength: 8)
            CircleIconButton(systemName: "plus") {
                showingImporter = true
            }
            CircleIconButton(systemName: "gearshape.fill") {
                showingSettings = true
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Palette.muted)
            TextField(
                "",
                text: $searchText,
                prompt: Text("Search your library").foregroundStyle(Theme.Palette.muted)
            )
            .font(Theme.Face.text(14))
            .foregroundStyle(Theme.Palette.text)
            .tint(Theme.Palette.accent)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Palette.faint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .panel(fill: Theme.Palette.surface, radius: 14)
    }

    // MARK: Continue card

    private func continueCard(_ game: RetroGame) -> some View {
        ZStack(alignment: .bottomLeading) {
            GameArtwork(art: game.art)
            Color.black.opacity(0.5)

            VStack(alignment: .leading, spacing: 9) {
                RetroLabel("Continue playing", color: Theme.Palette.accentSoft)
                Text(game.title)
                    .font(Theme.Face.display(23, .heavy))
                    .foregroundStyle(Theme.Palette.text)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    PlayProgressBar(value: game.progress)
                        .frame(width: 110)
                    Text("\(game.progressLabel) complete")
                        .font(Theme.Face.mono(10, .medium))
                        .foregroundStyle(Theme.Palette.text.opacity(0.75))
                    Spacer(minLength: 0)
                }
            }
            .padding(18)
        }
        .frame(height: 196)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 6) {
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("RESUME")
                    .font(Theme.Face.mono(10, .bold))
                    .tracking(1.4)
            }
            .foregroundStyle(Theme.Palette.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Capsule().fill(Theme.Palette.accentSoft))
            .padding(16)
        }
        .cardShadow()
    }

    // MARK: Games

    private var gamesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("All games") {
                Menu {
                    ForEach(LibrarySort.allCases) { option in
                        Button(option.title) {
                            withAnimation(Theme.Motion.smooth) {
                                sort = option
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(sort.title.uppercased())
                            .font(Theme.Face.mono(9, .semibold))
                            .tracking(1.1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(Theme.Palette.muted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.Palette.raised))
                    .overlay(Capsule().strokeBorder(Theme.Palette.stroke, lineWidth: 1))
                }
            }

            if visibleGames.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(visibleGames) { game in
                        NavigationLink(value: game) {
                            GameCard(game: game)
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                    addGameTile
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.Palette.faint)
            Text(library.games.isEmpty ? "Your library is empty" : "Nothing matches \u{201C}\(searchText)\u{201D}")
                .font(Theme.Face.text(14, .semibold))
                .foregroundStyle(Theme.Palette.text)
            Text(library.games.isEmpty
                 ? "Add a SNES ROM from Files to get started."
                 : "Try another title, or add another ROM from Files.")
                .font(Theme.Face.text(12))
                .foregroundStyle(Theme.Palette.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Button("Add games") {
                showingImporter = true
            }
            .buttonStyle(PocketButtonStyle(height: 44))
            .frame(maxWidth: 180)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .panel(fill: Theme.Palette.surface, radius: 18)
    }

    private var addGameTile: some View {
        Button {
            Haptics.select()
            showingImporter = true
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                Text("ADD GAMES")
                    .font(Theme.Face.mono(9, .bold))
                    .tracking(1.3)
            }
            .foregroundStyle(Theme.Palette.muted)
            .frame(maxWidth: .infinity)
            .aspectRatio(Theme.Metrics.artAspect, contentMode: .fit)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        Theme.Palette.hairline,
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 6])
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text("\(library.games.count) titles")
            Text("·")
            Text("\(library.totalPlayTimeLabel) played")
        }
        .font(Theme.Face.mono(10, .medium))
        .foregroundStyle(Theme.Palette.faint)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}

// MARK: - Card

struct GameCard: View {
    let game: RetroGame

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GameArtwork(art: game.art)
                .aspectRatio(Theme.Metrics.artAspect, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Theme.Palette.stroke, lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) {
                    if game.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.Palette.red)
                            .padding(6)
                            .background(Circle().fill(Color.black.opacity(0.45)))
                            .padding(8)
                    }
                }

            Text(game.title)
                .font(Theme.Face.text(14, .semibold))
                .foregroundStyle(Theme.Palette.text)
                .lineLimit(1)

            HStack(spacing: 5) {
                Text(game.system.shortName)
                Text("·")
                Text(game.playTimeLabel)
            }
            .font(Theme.Face.mono(9, .medium))
            .foregroundStyle(Theme.Palette.muted)
        }
    }
}

#Preview {
    LibraryView()
        .environmentObject(GameLibrary())
        .environmentObject(AppSettings())
        .environmentObject(PlaySession())
        .preferredColorScheme(.dark)
}
