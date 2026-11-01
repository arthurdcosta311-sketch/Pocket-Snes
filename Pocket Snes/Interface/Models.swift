//
//  Models.swift
//  Pocket Snes
//
//  Library data used by the interface. The library store is the seam the
//  emulator core plugs into: it owns the titles, their save states and which
//  one is currently loaded.
//

import Foundation

// MARK: - System

enum GameSystem: String, CaseIterable, Identifiable, Hashable, Codable {
    case superNintendo = "SNES"

    var id: String { rawValue }

    var displayName: String {
        return "Super Nintendo"
    }

    var shortName: String {
        return rawValue
    }
}

// MARK: - Save state

struct SaveState: Identifiable, Hashable, Codable {
    let id: UUID
    var slot: Int
    var label: String
    var date: Date

    init(id: UUID = UUID(), slot: Int, label: String, date: Date) {
        self.id = id
        self.slot = slot
        self.label = label
        self.date = date
    }
}

// MARK: - Game

struct RetroGame: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var tagline: String
    var blurb: String
    var system: GameSystem
    var year: Int
    var players: Int
    var region: String
    var fileSize: String
    var playTime: TimeInterval
    var progress: Double
    var lastPlayed: Date?
    var isFavorite: Bool
    var saveStates: [SaveState]
    var art: GameArt

    /// The stored ROM this title boots. nil until a ROM is imported.
    var romID: UUID?

    init(
        id: UUID = UUID(),
        title: String,
        tagline: String = "",
        blurb: String = "",
        system: GameSystem = .superNintendo,
        year: Int = 1994,
        players: Int = 1,
        region: String = "NTSC",
        fileSize: String = "4 MB",
        playTime: TimeInterval = 0,
        progress: Double = 0,
        lastPlayed: Date? = nil,
        isFavorite: Bool = false,
        saveStates: [SaveState] = [],
        art: GameArt,
        romID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.tagline = tagline
        self.blurb = blurb
        self.system = system
        self.year = year
        self.players = players
        self.region = region
        self.fileSize = fileSize
        self.playTime = playTime
        self.progress = progress
        self.lastPlayed = lastPlayed
        self.isFavorite = isFavorite
        self.saveStates = saveStates
        self.art = art
        self.romID = romID
    }

    var playTimeLabel: String {
        let totalMinutes = Int(playTime) / 60
        if totalMinutes < 1 { return "Not played" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes)m" }
        if minutes == 0 { return "\(hours)h" }
        return "\(hours)h \(minutes)m"
    }

    var progressLabel: String {
        return "\(Int((progress * 100).rounded()))%"
    }

    var playersLabel: String {
        return players > 1 ? "1–\(players) players" : "1 player"
    }
}

// MARK: - Import

extension RetroGame {
    /// Builds a library entry from a chosen file. ROMStore has already written
    /// the bytes; the entry only remembers their id.
    static func imported(from url: URL, romID: UUID, sizeLabel: String? = nil) -> RetroGame {
        let raw = url.deletingPathExtension().lastPathComponent
        let cleaned = raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = cleaned.isEmpty ? "Untitled ROM" : cleaned
        return RetroGame(
            title: title,
            tagline: "Imported from Files",
            blurb: "Pulled in from your Files app. Save states and play time appear here once you start playing.",
            fileSize: sizeLabel ?? "ROM",
            progress: 0,
            art: .generated(for: title),
            romID: romID
        )
    }
}

// MARK: - Sorting

enum LibrarySort: String, CaseIterable, Identifiable {
    case recent
    case alphabetical
    case mostPlayed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent:
            return "Recent"
        case .alphabetical:
            return "A–Z"
        case .mostPlayed:
            return "Most played"
        }
    }
}

// MARK: - Library store

final class GameLibrary: ObservableObject {
    @Published var games: [RetroGame] {
        didSet { persist() }
    }

    /// Starts from whatever was stored last time, or an empty library on a
    /// first launch. Pass an explicit list to bypass both.
    init(games: [RetroGame]? = nil) {
        if let games {
            self.games = games
        } else if let stored = GameLibrary.loadStored() {
            self.games = stored
        } else {
            self.games = []
            persist()
        }
    }

    var recentlyPlayed: RetroGame? {
        games
            .filter { $0.lastPlayed != nil }
            .max { ($0.lastPlayed ?? .distantPast) < ($1.lastPlayed ?? .distantPast) }
    }

    var totalPlayTime: TimeInterval {
        games.reduce(0) { $0 + $1.playTime }
    }

    var totalPlayTimeLabel: String {
        let minutes = Int(totalPlayTime) / 60
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(remainder)m" }
        if remainder == 0 { return "\(hours)h" }
        return "\(hours)h \(remainder)m"
    }

    func game(withID id: UUID) -> RetroGame? {
        return games.first { $0.id == id }
    }

    func toggleFavorite(_ id: UUID) {
        guard let index = games.firstIndex(where: { $0.id == id }) else { return }
        games[index].isFavorite.toggle()
    }

    func add(_ imported: [RetroGame]) {
        guard !imported.isEmpty else { return }
        games.insert(contentsOf: imported, at: 0)
    }

    func markPlayed(_ id: UUID) {
        guard let index = games.firstIndex(where: { $0.id == id }) else { return }
        games[index].lastPlayed = Date()
    }

    // MARK: - Save states

    func setSaveState(_ state: SaveState, for id: UUID) {
        guard let index = games.firstIndex(where: { $0.id == id }) else { return }
        var states = games[index].saveStates
        states.removeAll { $0.slot == state.slot }
        states.append(state)
        games[index].saveStates = states.sorted { $0.slot < $1.slot }
    }

    // MARK: - Persistence

    /// The library is stored as JSON. A new non-optional stored property on
    /// `RetroGame` (or anything it holds) will fail to decode an existing
    /// library, so give it a default or write a custom `init(from:)`.
    private static var storeURL: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("library.json")
    }

    private static func loadStored() -> [RetroGame]? {
        guard let data = try? Data(contentsOf: storeURL), !data.isEmpty else { return nil }
        return try? JSONDecoder().decode([RetroGame].self, from: data)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(games) else { return }
        try? data.write(to: GameLibrary.storeURL, options: .atomic)
    }
}

// MARK: - Play session

/// Which title is on the emulator surface right now. The player is presented
/// whenever this holds a game.
final class PlaySession: ObservableObject {
    @Published var game: RetroGame?

    /// A slot the player should load as soon as it boots, set by the library.
    @Published var pendingSlot: Int?

    func start(_ game: RetroGame, loadingSlot: Int? = nil) {
        self.pendingSlot = loadingSlot
        self.game = game
    }

    func stop() {
        game = nil
        pendingSlot = nil
    }
}

// MARK: - Relative time

enum RelativeTime {
    static func label(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
