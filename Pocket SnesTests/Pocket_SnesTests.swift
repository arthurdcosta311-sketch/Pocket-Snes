//
//  Pocket_SnesTests.swift
//  Pocket SnesTests
//
//  Engine checks: cartridge detection, CPU execution, PPU output, save states
//  and the controller bit layout.
//

import Testing
import Foundation
@testable import Pocket_Snes

struct Pocket_SnesTests {

    // MARK: - Helpers

    /// A minimal valid LoROM image: header at $7FC0, reset vector at $FFFC.
    private func loROM(program: [UInt8] = []) -> [UInt8] {
        var rom = [UInt8](repeating: 0xEA, count: 0x8000)

        if !program.isEmpty {
            rom.replaceSubrange(0..<program.count, with: program)
        }

        // Title "TEST" at $7FD0, terminated so readTitle stops there.
        rom[0x7FD0] = 0x54 // T
        rom[0x7FD1] = 0x45 // E
        rom[0x7FD2] = 0x53 // S
        rom[0x7FD3] = 0x54 // T
        rom[0x7FD4] = 0x00

        rom[0x7FD5] = 0x20     // map mode: LoROM
        rom[0x7FD7] = 0x08     // ROM size
        rom[0x7FDC] = 0xFF     // checksum complement
        rom[0x7FDD] = 0xFF
        rom[0x7FDE] = 0x00     // checksum
        rom[0x7FDF] = 0x00
        return rom
    }

    /// CLC, XCE (native), REP #$30, LDA #$1234, STA $1000, BRA -2.
    private let program: [UInt8] = [
        0x18,
        0xFB,
        0xC2, 0x30,
        0xA9, 0x34, 0x12,
        0x8D, 0x00, 0x10,
        0x80, 0xFE
    ]

    // MARK: - Cartridge

    @Test func detectsLoROMAndReadsTitle() {
        let cart = Cartridge(rom: loROM())
        #expect(cart.isHiRom == false)
        #expect(cart.title == "TEST")
    }

    @Test func stripsCopierHeader() {
        var headered = loROM()
        headered.insert(contentsOf: [UInt8](repeating: 0x00, count: 0x200), at: 0)
        #expect(headered.count % 0x400 == 0x200)   // headered shape

        let cart = Cartridge(rom: headered)
        #expect(cart.rom.count == 0x8000)          // header removed
        #expect(cart.isHiRom == false)
        #expect(cart.title == "TEST")
    }

    // MARK: - IRQ

    @Test func irqTimerFiresAtProgrammedLine() {
        let core = SNESCore(romData: loROM())
        core.bus.write(0x4209, 0x80)   // VTIME = $080 -> line 128
        core.bus.write(0x420A, 0x00)
        core.bus.write(0x4200, 0x10)   // V-IRQ on the V match

        core.runFrame()

        #expect(core.bus.irqFlag)
        #expect(core.cpu.irqPending)
    }

    @Test func irqTimerRegistersFollowTheHardwareMap() {
        let core = SNESCore(romData: loROM())
        core.bus.write(0x4207, 0x34)   // HTIMEL
        core.bus.write(0x4208, 0x01)   // HTIMEH
        core.bus.write(0x4209, 0x56)   // VTIMEL
        core.bus.write(0x420A, 0x01)   // VTIMEH

        #expect(core.bus.hTime == 0x0134)
        #expect(core.bus.vTime == 0x0156)
    }

    @Test func irqFlagClearsWhenRead() {
        let core = SNESCore(romData: loROM())
        core.bus.write(0x4200, 0x10)   // V-IRQ enabled, VTIME = 0

        core.runFrame()
        #expect(core.bus.irqFlag)

        #expect(core.bus.read(0x4211) & 0x80 != 0)
        #expect(core.bus.read(0x4211) & 0x80 == 0)  // acknowledged
    }

    // MARK: - CPU

    @Test func cpuRunsProgramAndWritesWRAM() {
        var rom = loROM(program: program)
        rom[0x7FFC] = 0x00     // reset vector -> $8000
        rom[0x7FFD] = 0x80

        let core = SNESCore(cart: Cartridge(rom: rom))
        for _ in 0..<40 { core.cpu.step() }

        #expect(core.cpu.emu == false)
        #expect(core.bus.wram[0x1000] == 0x34)
        #expect(core.bus.wram[0x1001] == 0x12)
    }

    // MARK: - PPU

    @Test func ppuRendersBackdropColor() {
        let core = SNESCore(romData: loROM())
        core.bus.write(0x2100, 0x0F)   // INIDISP: screen on
        core.bus.write(0x2121, 0x00)   // CGADD: color 0
        core.bus.write(0x2122, 0xE0)   // CGDATA low
        core.bus.write(0x2122, 0x03)   // CGDATA high -> green
        core.bus.ppu.runScanline(0)

        let frame = core.bus.ppu.frame
        #expect(frame.count == 256 * 224 * 4)
        #expect(frame[3] == 255)
    }

    @Test func enablingALayerChangesThePicture() {
        let core = SNESCore(romData: loROM())
        core.bus.write(0x2100, 0x0F)
        core.bus.write(0x2121, 0x00)
        core.bus.write(0x2122, 0xE0)
        core.bus.write(0x2122, 0x03)

        core.bus.write(0x212C, 0x01)   // TM: BG1 on main screen
        core.bus.ppu.runScanline(0)

        #expect(core.bus.ppu.tm == 0x01)
    }

    // MARK: - Save states

    @Test func saveStateRoundTrips() throws {
        let core = SNESCore(romData: loROM())
        core.bus.write(0x7E0000, 0x42)
        core.bus.write(0x2100, 0x0F)

        let data = try #require(core.captureState())

        core.bus.write(0x7E0000, 0x00)
        core.bus.write(0x2100, 0x80)
        #expect(core.bus.wram[0] == 0x00)

        #expect(core.restoreState(data))
        #expect(core.bus.wram[0] == 0x42)
        #expect(core.bus.ppu.inidisp == 0x0F)
    }

    // MARK: - Input

    @Test func inputBitsFollowControllerOrder() {
        var input = SNESInput()
        input.a = true
        #expect(input.bits == 0x0100)

        input.start = true
        #expect(input.bits == 0x0108)

        input.up = true
        #expect(input.bits == 0x0118)
    }

    // MARK: - Self-test

    @Test func engineSelfTestReportsNoFailures() {
        let results = EngineSelfTest.run()
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { !$0.hasPrefix("FAIL") })
    }

    // MARK: - Background rendering

    /// The tilemap base comes from BGxSC bits 2-7, in units of $400 words — one
    /// unit is exactly one 32x32 screen, 2 KB. This VRAM is a byte array, so the
    /// byte offset is `(sc & 0xFC) << 9`. Reading it with the wrong shift leaves
    /// every layer transparent, which is the black screen real ROMs showed.
    @Test func bgTilemapIsReadFromTheScreenRegisterBase() {
        let core = SNESCore(romData: loROM())
        let ppu = core.bus.ppu

        // Tile 0: opaque colour 1 on all 64 pixels. SNES tiles are planar:
        // eight bytes of plane 0 for rows 0-7, then plane 1.
        for row in 0..<8 {
            ppu.vram[row] = 0xFF
            ppu.vram[8 + row] = 0x00
        }

        // Palette 0: backdrop black, colour 1 white.
        ppu.cgram[0] = 0x00
        ppu.cgram[1] = 0x00
        ppu.cgram[2] = 0xFF
        ppu.cgram[3] = 0x7F

        // Tilemap at $2000: every entry is tile 0, palette 0, priority 0.
        // $2000 is screen unit 4, and BGxSC keeps that number in bits 2-7.
        let base = 0x2000
        for entry in 0..<(32 * 32) {
            ppu.vram[base + entry * 2] = 0x00
            ppu.vram[base + entry * 2 + 1] = 0x00
        }

        ppu.bgmode = 0x00
        ppu.bgsc[0] = 0x10       // screen unit 4 -> $2000, 32x32
        ppu.tm = 0x01
        ppu.inidisp = 0x0F

        ppu.runScanline(0)

        // A pixel inside the first tile must be the map's colour, not backdrop.
        let pixel = 8 * 4
        #expect(ppu.frame[pixel] > 0xF0)
    }

    @Test func scrollRegistersTakeLowByteFirst() {
        let core = SNESCore(romData: loROM())

        core.bus.write(0x210D, 0x34)   // BG1HOFS low byte
        core.bus.write(0x210D, 0x01)   // top two bits

        #expect(core.bus.ppu.bgx[0] == 0x0134)
    }
}
