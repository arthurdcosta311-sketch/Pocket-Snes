//
//  Cartridge.swift
//  Pocket Snes
//
//  Cartridge (ROM) handling: header detection and address mapping.
//

import Foundation

/// A SNES cartridge: raw ROM data plus LoROM/HiROM detection.
final class Cartridge {

    let rom: [UInt8]
    let isHiRom: Bool
    private(set) var title: String = "UNKNOWN"

    /// Battery-backed save RAM, mapped at $6000-$7FFF of certain banks.
    var sram: [UInt8] = Array(repeating: 0, count: 0x8000)

    init(rom: [UInt8]) {
        let cleaned = Cartridge.strippedOfCopierHeader(rom)
        self.rom = cleaned
        self.isHiRom = Cartridge.detectHiRom(cleaned)
        self.title = Cartridge.readTitle(cleaned, hiRom: isHiRom)
    }

    /// Real dumps often carry a 512-byte copier header ahead of the ROM image,
    /// which throws every header offset and mapping address off. Dumps with one
    /// are exactly 512 bytes past a multiple of 1 KB.
    static func strippedOfCopierHeader(_ rom: [UInt8]) -> [UInt8] {
        guard rom.count > 512, rom.count % 0x400 == 512 else { return rom }
        return Array(rom.dropFirst(512))
    }

    /// Convert a SNES bus address within a ROM-mapped region into a ROM file offset.
    /// Returns nil when the bank/offset combination is not ROM-mapped.
    func romIndex(bank: UInt8, off: UInt16) -> Int? {
        if isHiRom {
            switch bank {
            case 0x00...0x3F, 0x80...0xBF:
                // Mirrored window at $8000-$FFFF of the lower banks.
                guard off >= 0x8000 else { return nil }
                return ((Int(bank) & 0x3F) << 16) | Int(off)
            case 0x40...0x7D, 0xC0...0xFF:
                return ((Int(bank) & 0x3F) << 16) | Int(off)
            default:
                return nil
            }
        } else {
            guard off >= 0x8000 else { return nil }
            switch bank {
            case 0x00...0x7D, 0x80...0xFF:
                // LoROM banks $80-$FF mirror $00-$7F, hence the 0x7F mask.
                return ((Int(bank) & 0x7F) << 15) | (Int(off) & 0x7FFF)
            default:
                return nil
            }
        }
    }

    // MARK: - Header detection

    /// Heuristic LoROM/HiROM detection. Both candidate header windows are
    /// scored on checksum validity, the map-mode nibble, the ROM size field and
    /// a plausible reset vector. With only the first two signals a HiROM image
    /// is easily taken for a LoROM one, whose reset vector is garbage: the CPU
    /// then runs junk and the console stays on a black screen.
    static func detectHiRom(_ rom: [UInt8]) -> Bool {
        func score(_ offset: Int) -> Int {
            guard rom.count >= offset + 0x40 else { return -1000 }
            var s = 0
            let complement = Int(rom[offset + 0x1C]) | (Int(rom[offset + 0x1D]) << 8)
            let checksum = Int(rom[offset + 0x1E]) | (Int(rom[offset + 0x1F]) << 8)
            if (complement ^ 0xFFFF) == checksum { s += 10 }
            let mode = rom[offset + 0x15]
            if (mode & 0x20) != 0 { s += 3 }
            if offset == 0xFFC0 {
                if (mode & 1) != 0 { s += 4 } else { s -= 4 }
            } else {
                if (mode & 1) == 0 { s += 4 } else { s -= 4 }
            }
            let romSize = rom[offset + 0x17]
            if romSize >= 0x07 && romSize <= 0x0E { s += 3 }
            let reset = Int(rom[offset + 0x3C]) | (Int(rom[offset + 0x3D]) << 8)
            if reset >= 0x8000 { s += 6 }
            let printable = rom[offset..<(offset + 21)].filter { $0 >= 0x20 && $0 <= 0x7E }.count
            s += printable / 4
            return s
        }
        return score(0xFFC0) > score(0x7FC0)
    }

    static func readTitle(_ rom: [UInt8], hiRom: Bool) -> String {
        let offset = hiRom ? 0xFFC0 : 0x7FC0
        guard rom.count >= offset + 21 else { return "UNKNOWN" }
        let bytes = rom[offset..<(offset + 21)]
        let chars = bytes.map { (0x20...0x7E).contains($0) ? Character(UnicodeScalar($0)) : " " }
        let title = String(chars).trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "UNKNOWN" : title
    }
}
