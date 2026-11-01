//
//  DemoCartridge.swift
//  Pocket Snes
//
//  The cartridge behind the sample library: a real LoROM image with a short
//  65816 program, plus the scene it shows. The scene is written through the
//  bus and PPU registers, so starting a sample title exercises the same code
//  path an imported ROM takes.
//

import Foundation

enum DemoCartridge {

    // MARK: - ROM

    /// A minimal LoROM image. The reset vector points at a short program that
    /// drops the CPU into native mode and then, once per vblank, cues the next
    /// note of a scale on the sound unit. The picture comes from the scene below,
    /// so both halves of the console are exercised.
    static func rom() -> [UInt8] {
        var rom = [UInt8](repeating: 0xEA, count: 0x8000) // NOP filler
        let program = noteProgram()
        rom.replaceSubrange(0..<program.count, with: program)

        rom[0x7FD5] = 0x20    // header: LoROM
        rom[0x7FFC] = 0x00    // reset vector -> $8000
        rom[0x7FFD] = 0x80
        return rom
    }

    /// 65816: wait for vblank, bump a frame counter, write the next note to
    /// $2141-$2143 and commit it on $2140, then wait for the flag to clear so it
    /// happens exactly once a frame.
    private static func noteProgram() -> [UInt8] {
        var bytes: [UInt8] = []

        func lda(_ value: UInt8) { bytes += [0xA9, value] }
        func sta(_ address: UInt16) { bytes += [0x8D, UInt8(address & 0xFF), UInt8(address >> 8)] }
        func ldaAbs(_ address: UInt16) { bytes += [0xAD, UInt8(address & 0xFF), UInt8(address >> 8)] }
        func incAbs(_ address: UInt16) { bytes += [0xEE, UInt8(address & 0xFF), UInt8(address >> 8)] }
        func branch(_ opcode: UInt8, to target: Int) {
            let at = bytes.count + 1
            bytes += [opcode, 0x00]
            let delta = target - (at + 1)
            bytes[at] = UInt8(bitPattern: Int8(clamping: delta))
        }

        bytes += [0x78, 0x18, 0xFB]   // SEI, CLC, XCE -> native mode
        bytes += [0xE2, 0x30]         // SEP #$30: 8-bit A and index
        lda(0x00)
        sta(0x0010)                   // frame counter

        // Wait for vblank to start.
        let loop = bytes.count
        ldaAbs(0x4212)
        bytes += [0x29, 0x80]         // AND #$80
        branch(0xF0, to: loop)        // BEQ loop

        incAbs(0x0010)

        // Note = ((frame >> 3) & 7) * 2 + 48, a rising scale across eight steps.
        ldaAbs(0x0010)
        bytes += [0x4A, 0x4A, 0x4A]   // LSR A x3
        bytes += [0x29, 0x07]         // AND #$07
        bytes += [0x0A]               // ASL A
        bytes += [0x18]               // CLC
        bytes += [0x69, 0x30]         // ADC #$30
        sta(0x2141)                   // note
        lda(0x50)
        sta(0x2142)                   // level
        lda(0x00)
        sta(0x2143)                   // square wave
        lda(0xA5)
        sta(0x2140)                   // commit

        // Wait for vblank to end, so the next note is a frame away.
        let wait = bytes.count
        ldaAbs(0x4212)
        bytes += [0x29, 0x80]
        branch(0xD0, to: wait)        // BNE wait

        let target = UInt16(0x8000 + loop)
        bytes += [0x4C, UInt8(target & 0xFF), UInt8(target >> 8)]
        return bytes
    }

    // MARK: - Scene

    /// Writes palette, tiles and tilemap, then turns the screen on.
    static func install(on core: SNESCore, art: GameArt) {
        let bus = core.bus

        bus.write(0x2100, 0x80)   // force blank while the scene is written

        writePalette(on: bus, art: art)
        writeTiles(on: bus)
        writeMap(on: bus)

        bus.write(0x2105, 0x00)   // BG mode 0, 8x8 tiles
        bus.write(0x2107, 0x01)   // BG1 tilemap at VRAM byte $0400
        bus.write(0x210B, 0x00)   // BG1/BG2 character data at $0000
        bus.write(0x212C, 0x01)   // main screen: BG1 only
        bus.write(0x2100, 0x0F)   // screen on, full brightness

        core.bus.ppu.bgx[0] = 0
        core.bus.ppu.bgy[0] = 0
    }

    /// Moves the scene with the D-pad so the controls visibly feed the core.
    static func scroll(_ offset: Int, on core: SNESCore) {
        core.bus.ppu.bgx[0] = UInt16(offset & 0x03FF)
    }

    // MARK: - Scene pieces

    private static func color555(_ hex: UInt32) -> UInt16 {
        let r = (hex >> 16) & 0xFF
        let g = (hex >> 8) & 0xFF
        let b = hex & 0xFF
        return UInt16((r >> 3) | ((g >> 3) << 5) | ((b >> 3) << 10))
    }

    private static func writePalette(on bus: Bus, art: GameArt) {
        bus.write(0x2121, 0x00)   // CGADD = 0

        // Two palettes: 0 for the world, 1 for the highlights.
        let colors: [UInt32] = [
            art.sky, art.land, art.sun, art.accent,
            art.sky, art.accent, art.sun, art.accent
        ]
        for hex in colors {
            let value = color555(hex)
            bus.write(0x2122, UInt8(value & 0xFF))
            bus.write(0x2122, UInt8(value >> 8))
        }
    }

    private static func solidTile(_ color: UInt8) -> [UInt8] {
        var tile = [UInt8](repeating: 0, count: 16)
        for row in 0..<8 {
            tile[row * 2] = color & 1 != 0 ? 0xFF : 0x00
            tile[row * 2 + 1] = color & 2 != 0 ? 0xFF : 0x00
        }
        return tile
    }

    private static func writeTiles(on bus: Bus) {
        bus.write(0x2115, 0x80)   // VMAIN: +1 word, no remap
        bus.write(0x2116, 0x00)   // VMADD = $0000
        bus.write(0x2117, 0x00)

        var striped = [UInt8](repeating: 0, count: 16)
        for row in 0..<8 {
            striped[row * 2] = 0xAA
            striped[row * 2 + 1] = 0x55
        }

        let tiles: [[UInt8]] = [
            [UInt8](repeating: 0, count: 16),   // 0: empty, sky shows through
            solidTile(1),                       // 1: ground
            striped,                            // 2: stripe
            solidTile(3)                        // 3: highlight
        ]

        for tile in tiles {
            var index = 0
            while index + 1 < tile.count {
                bus.write(0x2118, tile[index])
                bus.write(0x2119, tile[index + 1])
                index += 2
            }
        }
    }

    private static func writeMap(on bus: Bus) {
        bus.write(0x2115, 0x80)
        bus.write(0x2116, 0x02)   // VRAM word $0200 = byte $0400
        bus.write(0x2117, 0x00)

        for ty in 0..<32 {
            for tx in 0..<32 {
                var tile = 0
                var palette = 0

                if ty >= 20 {
                    tile = (tx / 4) % 2 == 0 ? 1 : 2
                }

                if (ty == 4 || ty == 5), (tx % 8) < 3 {
                    tile = 3
                    palette = 1
                }

                let entry = UInt16(tile | (palette << 10))
                bus.write(0x2118, UInt8(entry & 0xFF))
                bus.write(0x2119, UInt8(entry >> 8))
            }
        }
    }
}
