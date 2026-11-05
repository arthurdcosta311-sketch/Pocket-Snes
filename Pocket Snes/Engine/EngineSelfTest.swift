//
//  EngineSelfTest.swift
//  Pocket Snes
//
//  A built-in check that exercises the CPU and PPU cores with a tiny
//  assembled program and a palette-only render, so the engine's health can
//  be verified from the app without a real cartridge.
//

import Foundation

enum EngineSelfTest {

    static func run() -> [String] {
        var out: [String] = []
        func check(_ name: String, _ cond: Bool) {
            out.append("\(cond ? "PASS" : "FAIL")  \(name)")
        }

        // ---- CPU test -------------------------------------------------
        // LoROM program mapped at bank 0 $8000, entry via the reset vector.
        let program: [UInt8] = [
            0x18,             // CLC
            0xFB,             // XCE  -> native mode
            0xC2, 0x30,       // REP #$30: 16-bit A and index
            0xA9, 0x34, 0x12, // LDA #$1234
            0x8D, 0x00, 0x10, // STA $1000 (WRAM mirror)
            0xA2, 0x78, 0x56, // LDX #$5678
            0x86, 0x20,       // STX $20 (direct page)
            0xE2, 0x20,       // SEP #$20: 8-bit A
            0xA9, 0x07,       // LDA #$07
            0x18,             // CLC
            0x69, 0x09,       // ADC #$09 -> $10
            0x8D, 0x02, 0x10, // STA $1002
            0x80, 0xFE        // BRA -2: idle loop
        ]

        var rom = [UInt8](repeating: 0xEA, count: 0x8000) // NOP filler
        rom.replaceSubrange(0..<program.count, with: program)
        rom[0x7FD5] = 0x20     // header: LoROM map mode
        rom[0x7FFC] = 0x00     // reset vector -> $8000
        rom[0x7FFD] = 0x80

        let cpuCore = SNESCore(cart: Cartridge(rom: rom))
        for _ in 0..<80 { cpuCore.cpu.step() }

        check("CPU: entered native mode", !cpuCore.cpu.emu)
        check("CPU: 16-bit store to WRAM",
              cpuCore.bus.wram[0x1000] == 0x34 && cpuCore.bus.wram[0x1001] == 0x12)
        check("CPU: direct page store",
              cpuCore.bus.wram[0x20] == 0x78 && cpuCore.bus.wram[0x21] == 0x56)
        check("CPU: decimal-free ADC ($07 + $09)",
              cpuCore.bus.wram[0x1002] == 0x10)

        // ---- WRAM $2180 test ------------------------------------------
        cpuCore.bus.write(0x2181, 0x50)  // WMADDL = $50
        cpuCore.bus.write(0x2182, 0x05)  // WMADDM = $05 -> $0550
        cpuCore.bus.write(0x2183, 0x00)  // WMADDH = $00
        cpuCore.bus.write(0x2180, 0x99)  // WMDATA = $99
        check("Bus: WRAM $2180 data port write", cpuCore.bus.wram[0x0550] == 0x99)

        // ---- VRAM $2116/$2117 test ------------------------------------
        cpuCore.bus.write(0x2115, 0x80)  // VMAIN: inc on high write ($2119)
        cpuCore.bus.write(0x2116, 0x34)  // VMADDL = $34
        cpuCore.bus.write(0x2117, 0x12)  // VMADDH = $12 -> word $1234
        cpuCore.bus.write(0x2118, 0xAA)  // VMDATAL
        cpuCore.bus.write(0x2119, 0x55)  // VMDATAH -> writes $55AA at word $1234 (byte $2468)
        let v0 = cpuCore.bus.ppu.vram[0x2468]
        let v1 = cpuCore.bus.ppu.vram[0x2469]
        check("PPU: VRAM $2116/17 correct byte ordering", v0 == 0xAA && v1 == 0x55)

        // ---- PPU test -------------------------------------------------
        let blank = [UInt8](repeating: 0xEA, count: 0x8000)
        let ppuCore = SNESCore(cart: Cartridge(rom: blank))

        ppuCore.bus.write(0x2100, 0x0F)  // INIDISP: screen on, full brightness
        ppuCore.bus.write(0x2121, 0x00)  // CGADDR: color 0
        ppuCore.bus.write(0x2122, 0xE0)  // CGDATA low: green $3E0
        ppuCore.bus.write(0x2122, 0x03)  // CGDATA high
        ppuCore.bus.ppu.runScanline(0)

        let frame = ppuCore.bus.ppu.frame
        let r = Int(frame[0]), g = Int(frame[1]), b = Int(frame[2])
        check("PPU: renders backdrop palette color", r < 8 && g > 200 && b < 8)

        return out
    }
}
