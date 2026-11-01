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

    /// The stored ROM this title boots. Sample entries have none.
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

    /// Starts from whatever was stored last time, or from the sample shelf on a
    /// first launch. Pass an explicit list to bypass both.
    init(games: [RetroGame]? = nil) {
        if let games {
            self.games = games
        } else if let stored = GameLibrary.loadStored() {
            self.games = stored
        } else {
            self.games = GameLibrary.sampleGames
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

// MARK: - Sample library

extension GameLibrary {
    static var sampleGames: [RetroGame] {
        let now = Date()

        func states(_ labels: [String]) -> [SaveState] {
            return labels.enumerated().map { index, label in
                SaveState(
                    slot: index + 1,
                    label: label,
                    date: now.addingTimeInterval(-Double((index + 1) * 7) * 3600)
                )
            }
        }

        return [
            RetroGame(
                title: "Super Mario World",
                tagline: "Dinosaur Land, one cape spin at a time",
                blurb: "Bright, generous platforming with a secret behind every vine. Runs crisp and full speed on Pocket Snes.",
                year: 1990,
                players: 2,
                fileSize: "512 KB",
                playTime: 12 * 3600 + 40 * 60,
                progress: 0.62,
                lastPlayed: now.addingTimeInterval(-1_800),
                isFavorite: true,
                saveStates: states(["Donut Plains 2", "Vanilla Dome"]),
                art: GameArt(seed: 11, sky: 0x2E5FAF, land: 0x3FA34D, sun: 0xFFD65C, accent: 0xFFC94A, symbol: "star.fill")
            ),
            RetroGame(
                title: "Zelda: A Link to the Past",
                tagline: "Hyrule, light and dark",
                blurb: "Two overworlds, a dozen dungeons and one very quiet hero. Save anywhere with three quick slots.",
                year: 1991,
                fileSize: "1 MB",
                playTime: 31 * 3600,
                progress: 0.34,
                lastPlayed: now.addingTimeInterval(-64_800),
                isFavorite: true,
                saveStates: states(["Tower of Hera"]),
                art: GameArt(seed: 22, sky: 0x14243F, land: 0x4A6B3A, sun: 0xE8D48B, accent: 0xC9B8FF, symbol: "shield.lefthalf.filled")
            ),
            RetroGame(
                title: "Super Metroid",
                tagline: "Zebes, in silence and static",
                blurb: "Atmosphere first: drip-fed abilities, a map that folds back on itself, and a soundtrack that never lets go.",
                year: 1994,
                fileSize: "3 MB",
                playTime: 8 * 3600 + 15 * 60,
                progress: 0.48,
                lastPlayed: now.addingTimeInterval(-3 * 86_400),
                saveStates: states(["Norfair", "Maridia"]),
                art: GameArt(seed: 33, sky: 0x1B1030, land: 0x4B2C7A, sun: 0xC9B8FF, accent: 0x35E0A1, symbol: "bolt.fill")
            ),
            RetroGame(
                title: "Donkey Kong Country",
                tagline: "Pre-rendered jungle, 16-bit shine",
                blurb: "Roll, bounce and barrel-blast through the Kongs' island. Frame-perfect controls, prepared for a Bluetooth pad.",
                year: 1994,
                players: 2,
                fileSize: "4 MB",
                playTime: 5 * 3600 + 20 * 60,
                progress: 0.22,
                lastPlayed: now.addingTimeInterval(-6 * 86_400),
                saveStates: [],
                art: GameArt(seed: 44, sky: 0x123A3A, land: 0x8B5A2B, sun: 0x7BF0C0, accent: 0xFFC94A, symbol: "leaf.fill")
            ),
            RetroGame(
                title: "F-Zero",
                tagline: "Mode 7 at four hundred kilometres an hour",
                blurb: "Silky pseudo-3D racing. Widescreen fill keeps the sense of speed without cropping the track map.",
                year: 1990,
                fileSize: "512 KB",
                playTime: 2 * 3600 + 5 * 60,
                progress: 0.15,
                lastPlayed: now.addingTimeInterval(-9 * 86_400),
                art: GameArt(seed: 55, sky: 0x2A0F3A, land: 0xE0556A, sun: 0xFFC94A, accent: 0x4C8DFF, symbol: "flag.checkered")
            ),
            RetroGame(
                title: "Chrono Trigger",
                tagline: "Time travel with a party you choose",
                blurb: "The one with no filler. Long sessions, three save slots and a quick resume that drops you back mid-battle.",
                year: 1995,
                fileSize: "4 MB",
                playTime: 22 * 3600 + 10 * 60,
                progress: 0.55,
                lastPlayed: now.addingTimeInterval(-12 * 86_400),
                isFavorite: true,
                saveStates: states(["End of Time", "Magus' Castle"]),
                art: GameArt(seed: 66, sky: 0x2B1B4E, land: 0x6B4FA0, sun: 0xF2EEE4, accent: 0xFFC94A, symbol: "clock.fill")
            ),
            RetroGame(
                title: "Star Fox",
                tagline: "Arwing, cornered",
                blurb: "Polygons, chatter and barrel rolls. Bigger, chunkier pixels are half the charm.",
                year: 1993,
                fileSize: "1 MB",
                playTime: 3 * 3600 + 30 * 60,
                progress: 0.4,
                lastPlayed: now.addingTimeInterval(-18 * 86_400),
                saveStates: [],
                art: GameArt(seed: 77, sky: 0x0B1B33, land: 0x2C4B7A, sun: 0xE8D48B, accent: 0xFF5C5C, symbol: "airplane")
            ),
            RetroGame(
                title: "Yoshi's Island",
                tagline: "Crayon lands",
                blurb: "Hand-drawn pastel worlds with a wobbling baby on your back. A good test of colour handling.",
                year: 1995,
                fileSize: "4 MB",
                playTime: 6 * 3600 + 45 * 60,
                progress: 0.3,
                lastPlayed: now.addingTimeInterval(-24 * 86_400),
                art: GameArt(seed: 88, sky: 0x3E8BD6, land: 0x4FB86B, sun: 0xFFF1B8, accent: 0xFFC94A, symbol: "sun.max.fill")
            )
        ]
    }
}
