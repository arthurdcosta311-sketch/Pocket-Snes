//
//  ROMStore.swift
//  Pocket Snes
//
//  Imported ROM images live on disk, keyed by an id the library keeps on each
//  title. The player asks the store for the bytes and hands them to SNESCore.
//

import Foundation

final class ROMStore {

    static let shared = ROMStore()

    private let fileManager = FileManager.default

    private var directory: URL {
        let base = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ROMs", isDirectory: true)
    }

    func url(for id: UUID) -> URL {
        return directory.appendingPathComponent("\(id.uuidString).smc")
    }

    /// Writes the bytes the user picked and returns the id to keep on the title.
    @discardableResult
    func save(_ data: Data) throws -> UUID {
        let id = UUID()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url(for: id), options: .atomic)
        return id
    }

    func data(for id: UUID) -> [UInt8]? {
        guard let raw = try? Data(contentsOf: url(for: id)), !raw.isEmpty else { return nil }
        return [UInt8](raw)
    }

    func sizeLabel(for id: UUID) -> String? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url(for: id).path),
              let bytes = attributes[.size] as? Int64 else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB]
        return formatter.string(fromByteCount: bytes)
    }

    func delete(_ id: UUID) {
        try? fileManager.removeItem(at: url(for: id))
    }
}
