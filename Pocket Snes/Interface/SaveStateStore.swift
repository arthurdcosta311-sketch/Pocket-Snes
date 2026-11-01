//
//  SaveStateStore.swift
//  Pocket Snes
//
//  Save states on disk: one file per game and slot, beside the ROMs. The
//  library keeps the labels the interface lists; the bytes live here.
//

import Foundation

final class SaveStateStore {

    static let shared = SaveStateStore()

    static let slots = 1...4

    private let fileManager = FileManager.default

    private var directory: URL {
        let base = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SaveStates", isDirectory: true)
    }

    private func url(for gameID: UUID, slot: Int) -> URL {
        return directory
            .appendingPathComponent(gameID.uuidString, isDirectory: true)
            .appendingPathComponent("slot\(slot).state")
    }

    func save(_ data: Data, gameID: UUID, slot: Int) -> Bool {
        do {
            let folder = url(for: gameID, slot: slot).deletingLastPathComponent()
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url(for: gameID, slot: slot), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    func data(gameID: UUID, slot: Int) -> Data? {
        return try? Data(contentsOf: url(for: gameID, slot: slot))
    }

    func delete(gameID: UUID, slot: Int) {
        try? fileManager.removeItem(at: url(for: gameID, slot: slot))
    }

    /// The lowest free slot, or the oldest one when all four are taken.
    func nextSlot(gameID: UUID, existing: [SaveState]) -> Int {
        let used = Set(existing.map { $0.slot })
        if let free = SaveStateStore.slots.first(where: { !used.contains($0) }) {
            return free
        }
        let oldest = existing.min { $0.date < $1.date }
        return oldest?.slot ?? 1
    }

    func deleteAll(gameID: UUID) {
        try? fileManager.removeItem(at: directory.appendingPathComponent(gameID.uuidString, isDirectory: true))
    }
}
