//
//  SNESCore.swift
//  Pocket Snes
//
//  Top-level emulation core: ties CPU, PPU, APU, cart and bus together and
//  runs the console scanline by scanline. This is the type the interface
//  layer plugs into.
//

import Foundation

/// One controller's button state.
struct SNESInput {
    var b = false, y = false, select = false, start = false
    var up = false, down = false, left = false, right = false
    var a = false, x = false, l = false, r = false

    /// Bit layout matching the SNES controller shift register:
    /// B, Y, Select, Start, Up, Down, Left, Right, A, X, L, R.
    var bits: UInt16 {
        var v: UInt16 = 0
        let order: [Bool] = [b, y, select, start, up, down, left, right, a, x, l, r, false, false, false, false]
        for (i, pressed) in order.enumerated() where pressed {
            v |= 1 << UInt16(i)
        }
        return v
    }
}

final class SNESCore {

    let cart: Cartridge
    let bus: Bus
    let cpu: CPU65816

    private(set) var frameCount = 0

    /// Controller state, mirrored into the bus each frame.
    var input = SNESInput() {
        didSet { bus.joy1 = input.bits }
    }

    /// The last rendered frame as RGBA8 pixels, 256 x 224.
    var frame: [UInt8] { bus.ppu.frame }

    init(cart: Cartridge) {
        self.cart = cart
        self.bus = Bus(cart: cart)
        self.cpu = CPU65816(bus: bus)
        bus.joy1 = input.bits
    }

    /// Convenience for the interface layer: build a core straight from ROM data.
    convenience init(romData: [UInt8]) {
        self.init(cart: Cartridge(rom: romData))
    }

    /// Runs one full video frame (262 scanlines, NTSC timing).
    func runFrame() {
        bus.vblankFlag = false
        bus.ppu.startFrame()

        for line in 0..<262 {
            if line == 0 { bus.hdmaInit() }
            bus.ppu.runScanline(line)
            bus.hdmaLine(line)
            runScanlineCPU()

            if line == 225 {
                bus.vblankFlag = true
                bus.nmiFlag = true
                if bus.nmiEnable {
                    cpu.nmiPending = true
                }
            }
        }

        frameCount += 1
    }

    /// Runs roughly 227 CPU cycles (one scanline at ~3.58 MHz).
    private func runScanlineCPU() {
        var budget = 227
        while budget > 0, !cpu.halted {
            cpu.step()
            budget -= max(1, cpu.cycleDebt)
        }
    }
}
