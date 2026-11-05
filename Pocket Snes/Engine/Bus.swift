//
//  Bus.swift
//  Pocket Snes
//
//  The system bus: full memory map (LoROM/HiROM), PPU/APU registers, WRAM,
//  SRAM, joypad, arithmetic units and the DMA/HDMA controllers.
//

import Foundation

final class Bus {

    let cart: Cartridge
    let ppu: PPU
    let apu: APU
    var wram: [UInt8]
    var wramAddr: UInt32 = 0

    private(set) var openBus: UInt8 = 0

    // MARK: I/O registers
    var nmiEnable = false
    var autoJoypad = false
    var hdmaEnable: UInt8 = 0
    var nmiFlag = false
    var vblankFlag = false

    // IRQ timers: $4200 bits 5 and 4 enable the H and V comparisons,
    // $4207/$4208 hold HTIME and $4209/$420A hold VTIME. The dot counter is
    // not modelled, so an H match is taken at the start of its line.
    var hIRQEnable = false
    var vIRQEnable = false
    var irqFlag = false
    var hTime: UInt16 = 0
    var vTime: UInt16 = 0

    // Math units
    private var multA: UInt8 = 0
    private var multB: UInt8 = 0
    private var divA: UInt16 = 0
    private var divB: UInt8 = 0
    private var lastOpWasDivide = false

    // Joypad
    var joy1: UInt16 = 0xFFFF
    private var joy1Latched: UInt16 = 0xFFFF

    // DMA / HDMA
    var dmaChannels: [[UInt8]] = Array(repeating: Array(repeating: 0, count: 8), count: 8)

    struct HDMAState: Codable {
        var active = false
        var finished = false
        var indirect = false
        var tableAddr: UInt32 = 0
        var indirectAddr: UInt32 = 0
        var linesLeft: UInt8 = 0
        var repeatMode = false
    }
    var hdmaStates: [HDMAState] = (0..<8).map { _ in HDMAState() }

    init(cart: Cartridge) {
        self.cart = cart
        self.ppu = PPU()
        self.apu = APU()
        self.wram = [UInt8](repeating: 0, count: 0x20000)
    }

    // MARK: - Access

    func read(_ addr: UInt32) -> UInt8 {
        let bank = UInt8(truncatingIfNeeded: addr >> 16)
        let off = UInt16(truncatingIfNeeded: addr)
        let v = readDevice(bank, off)
        openBus = v
        return v
    }

    func write(_ addr: UInt32, _ value: UInt8) {
        let bank = UInt8(truncatingIfNeeded: addr >> 16)
        let off = UInt16(truncatingIfNeeded: addr)
        writeDevice(bank, off, value)
        openBus = value
    }

    // MARK: - Memory map

    private func readDevice(_ bank: UInt8, _ off: UInt16) -> UInt8 {
        switch bank {
        case 0x00...0x3F, 0x80...0xBF:
            switch off {
            case 0x0000...0x1FFF:
                return wram[Int(off) & 0x1FFF]
            case 0x2100...0x213F:
                return ppu.readRegister(off & 0x3F)
            case 0x2140...0x217F:
                return apu.read(port: Int(off & 3))
            case 0x2180:
                let v = wram[Int(wramAddr & 0x1FFFF)]
                wramAddr = (wramAddr &+ 1) & 0x1FFFF
                return v
            case 0x4016, 0x4017:
                return readJoypad(Int(off & 1))
            case 0x4200...0x43FF:
                return readIO(off)
            case 0x6000...0x7FFF:
                if cart.isHiRom {
                    let b = bank & 0x7F
                    if b >= 0x20 && b <= 0x3F {
                        let sramOff = (Int(b - 0x20) << 13) | (Int(off) & 0x1FFF)
                        return cart.sram[sramOff % cart.sram.count]
                    }
                    return openBus
                } else {
                    return cart.sram[Int(off) & (cart.sram.count - 1)]
                }
            case 0x8000...0xFFFF:
                if let i = cart.romIndex(bank: bank, off: off) {
                    return cart.rom[i % cart.rom.count]
                }
                return openBus
            default:
                return openBus
            }
        case 0x7E:
            return wram[Int(off)]
        case 0x7F:
            return wram[0x10000 + Int(off)]
        case 0x40...0x7D:
            if !cart.isHiRom && (0x6000...0x7FFF).contains(off) {
                return cart.sram[Int(off) & (cart.sram.count - 1)]
            }
            if let i = cart.romIndex(bank: bank, off: off) {
                return cart.rom[i % cart.rom.count]
            }
            return openBus
        case 0xC0...0xFF:
            if let i = cart.romIndex(bank: bank, off: off) {
                return cart.rom[i % cart.rom.count]
            }
            return openBus
        default:
            return openBus
        }
    }

    private func writeDevice(_ bank: UInt8, _ off: UInt16, _ value: UInt8) {
        switch bank {
        case 0x00...0x3F, 0x80...0xBF:
            switch off {
            case 0x0000...0x1FFF:
                wram[Int(off) & 0x1FFF] = value
            case 0x2100...0x213F:
                ppu.writeRegister(off & 0x3F, value)
            case 0x2140...0x217F:
                apu.write(port: Int(off & 3), value: value)
            case 0x2180:
                wram[Int(wramAddr & 0x1FFFF)] = value
                wramAddr = (wramAddr &+ 1) & 0x1FFFF
            case 0x2181:
                wramAddr = (wramAddr & 0x1FF00) | UInt32(value)
            case 0x2182:
                wramAddr = (wramAddr & 0x100FF) | (UInt32(value) << 8)
            case 0x2183:
                wramAddr = (wramAddr & 0x0FFFF) | (UInt32(value & 1) << 16)
            case 0x4016:
                joy1Latched = joy1
            case 0x4200...0x43FF:
                writeIO(off, value)
            case 0x6000...0x7FFF:
                if cart.isHiRom {
                    let b = bank & 0x7F
                    if b >= 0x20 && b <= 0x3F {
                        let sramOff = (Int(b - 0x20) << 13) | (Int(off) & 0x1FFF)
                        cart.sram[sramOff % cart.sram.count] = value
                    }
                } else {
                    cart.sram[Int(off) & (cart.sram.count - 1)] = value
                }
            default:
                break
            }
        case 0x7E:
            wram[Int(off)] = value
        case 0x7F:
            wram[0x10000 + Int(off)] = value
        case 0x40...0x7D:
            if !cart.isHiRom && (0x6000...0x7FFF).contains(off) {
                cart.sram[Int(off) & (cart.sram.count - 1)] = value
            }
        default:
            break
        }
    }

    // MARK: - I/O registers ($4200-$43FF)

    private func writeIO(_ off: UInt16, _ value: UInt8) {
        switch off {
        case 0x4200:
            nmiEnable = value & 0x80 != 0
            hIRQEnable = value & 0x20 != 0
            vIRQEnable = value & 0x10 != 0
            autoJoypad = value & 0x01 != 0
        case 0x4201: break // Programmable I/O port, unused
        case 0x4202:
            multA = value
            lastOpWasDivide = false
        case 0x4203:
            multB = value
        case 0x4204:
            divA = (divA & 0xFF00) | UInt16(value)
            lastOpWasDivide = true
        case 0x4205:
            divA = (divA & 0x00FF) | UInt16(value) << 8
        case 0x4206:
            divB = value
        case 0x4207:
            hTime = (hTime & 0x0100) | UInt16(value)
        case 0x4208:
            hTime = (hTime & 0x00FF) | UInt16(value & 0x01) << 8
        case 0x4209:
            vTime = (vTime & 0x0100) | UInt16(value)
        case 0x420A:
            vTime = (vTime & 0x00FF) | UInt16(value & 0x01) << 8
        case 0x420B:
            runDMA(enable: value)
        case 0x420C:
            hdmaEnable = value
        case 0x4300...0x437F:
            let channel = Int((off - 0x4300) / 0x10)
            let reg = Int((off - 0x4300) % 0x10)
            guard channel < 8, reg < 8 else { return }
            dmaChannels[channel][reg] = value
        default:
            break
        }
    }

    private func readIO(_ off: UInt16) -> UInt8 {
        switch off {
        case 0x4210:
            let v: UInt8 = (nmiFlag ? 0x80 : 0) | 0x02
            nmiFlag = false
            return v
        case 0x4211:
            // Bit 7 is the IRQ flag; reading it acknowledges and clears it.
            let v: UInt8 = irqFlag ? 0x80 : 0
            irqFlag = false
            return v
        case 0x4212:
            var v: UInt8 = 0
            if vblankFlag { v |= 0x80 }
            return v
        case 0x4213:
            return 0x40
        case 0x4214:
            return UInt8(truncatingIfNeeded: mathResult())
        case 0x4215:
            return UInt8(truncatingIfNeeded: mathResult() >> 8)
        case 0x4216:
            return UInt8(truncatingIfNeeded: mathRemainderOrProduct())
        case 0x4217:
            return UInt8(truncatingIfNeeded: mathRemainderOrProduct() >> 8)
        case 0x4218:
            return UInt8(truncatingIfNeeded: ~joy1)
        case 0x4219:
            return UInt8(truncatingIfNeeded: (~joy1) >> 8)
        case 0x421A...0x421F:
            return 0xFF
        case 0x4300...0x437F:
            let channel = Int((off - 0x4300) / 0x10)
            let reg = Int((off - 0x4300) % 0x10)
            guard channel < 8, reg < 8 else { return openBus }
            return dmaChannels[channel][reg]
        default:
            return openBus
        }
    }

    private func mathResult() -> UInt16 {
        if lastOpWasDivide {
            if divB == 0 { return 0xFFFF }
            return divA / UInt16(divB)
        }
        return UInt16(Int(multA) * Int(multB))
    }

    private func mathRemainderOrProduct() -> UInt16 {
        if lastOpWasDivide {
            if divB == 0 { return divA }
            return divA % UInt16(divB)
        }
        return UInt16(Int(multA) * Int(multB))
    }

    // MARK: - Joypad

    /// Raises the IRQ flag when the line reaches a programmed count: the
    /// vertical comparison when $4200 bit 4 is set, the horizontal one when
    /// bit 5 is set. The dot counter is not modelled, so an H match is taken at
    /// the start of the line and therefore fires once per line. The core calls
    /// this once per scan line; the CPU takes the interrupt whenever its I flag
    /// is clear.
    func irqTimerTick(line: Int) {
        guard line < 225 else { return }
        if vIRQEnable, line == Int(vTime) {
            irqFlag = true
        }
        if hIRQEnable {
            irqFlag = true
        }
    }

    private func readJoypad(_ port: Int) -> UInt8 {
        if port == 0 {
            let pressed = joy1Latched & 1 != 0
            joy1Latched = (joy1Latched >> 1) | 0x8000
            return (pressed ? 0x00 : 0x01) | 0x3C
        }
        return 0x3C
    }

    // MARK: - DMA

    private func runDMA(enable: UInt8) {
        let unitTable: [[Int]] = [[0], [0, 1], [0, 0], [0, 0, 1, 1], [0, 1, 2, 3]]
        for ch in 0..<8 where enable & (1 << ch) != 0 {
            let r = dmaChannels[ch]
            let mode = Int(r[0] & 0x07)
            let toB = r[0] & 0x80 == 0
            let fixed = r[0] & 0x08 != 0
            let decrement = r[0] & 0x10 != 0
            let bReg = 0x2100 + UInt16(r[1])
            var aAddr = UInt32(r[2]) | UInt32(r[3]) << 8 | UInt32(r[4]) << 16
            var count = Int(r[5]) | Int(r[6]) << 8
            if count == 0 { count = 0x10000 }

            let pattern = unitTable[min(mode, 4)]
            for i in 0..<count {
                let unit = pattern[i % pattern.count]
                let target = UInt32(bReg + UInt16(unit))
                if toB {
                    write(target, read(aAddr))
                } else {
                    write(aAddr, read(target))
                }
                if !fixed {
                    let bank = aAddr & 0xFF0000
                    let nextOff = decrement ? (UInt16(aAddr) &- 1) : (UInt16(aAddr) &+ 1)
                    aAddr = bank | UInt32(nextOff)
                }
            }

            dmaChannels[ch][2] = UInt8(truncatingIfNeeded: aAddr)
            dmaChannels[ch][3] = UInt8(truncatingIfNeeded: aAddr >> 8)
            dmaChannels[ch][4] = UInt8(truncatingIfNeeded: aAddr >> 16)
            let left = UInt16(truncatingIfNeeded: count)
            dmaChannels[ch][5] = UInt8(truncatingIfNeeded: left)
            dmaChannels[ch][6] = UInt8(truncatingIfNeeded: left >> 8)
        }
    }

    // MARK: - HDMA

    func hdmaInit() {
        for ch in 0..<8 where hdmaEnable & (1 << ch) != 0 {
            let r = dmaChannels[ch]
            var s = hdmaStates[ch]
            s.active = true
            s.finished = false
            s.indirect = r[0] & 0x40 != 0
            s.tableAddr = UInt32(r[2]) | UInt32(r[3]) << 8 | UInt32(r[4]) << 16
            s.linesLeft = 0
            hdmaStates[ch] = s
        }
    }

    func hdmaLine(_ line: Int) {
        guard line <= 224, hdmaEnable != 0 else { return }
        let unitTable: [[Int]] = [[0], [0, 1], [0, 0], [0, 0, 1, 1], [0, 1, 2, 3]]
        for ch in 0..<8 where hdmaEnable & (1 << ch) != 0 {
            var s = hdmaStates[ch]
            guard s.active, !s.finished else { continue }
            let r = dmaChannels[ch]

            if s.linesLeft == 0 {
                let header = read(s.tableAddr)
                s.tableAddr &+= 1
                if header & 0x80 != 0 {
                    s.finished = true
                    hdmaStates[ch] = s
                    continue
                }
                s.linesLeft = header & 0x7F
                if s.linesLeft == 0 {
                    s.finished = true
                    hdmaStates[ch] = s
                    continue
                }
                s.repeatMode = header & 0x40 != 0
                if s.indirect {
                    var ia = UInt32(read(s.tableAddr))
                    s.tableAddr &+= 1
                    ia |= UInt32(read(s.tableAddr)) << 8
                    s.tableAddr &+= 1
                    ia |= UInt32(r[7]) << 16
                    s.indirectAddr = ia
                }
            }
            s.linesLeft &-= 1

            if s.repeatMode && s.linesLeft > 0 {
                // Repeat: data transfers only on the first line of a block.
                hdmaStates[ch] = s
                continue
            }

            let mode = Int(r[0] & 7)
            let pattern = unitTable[min(mode, 4)]
            let bReg = 0x2100 + UInt16(r[1])
            var srcAddr = s.indirect ? s.indirectAddr : s.tableAddr
            for unit in pattern {
                let v = read(srcAddr)
                write(UInt32(bReg + UInt16(unit)), v)
                srcAddr &+= 1
            }
            if s.indirect {
                s.indirectAddr = srcAddr
            } else {
                s.tableAddr = srcAddr
            }
            hdmaStates[ch] = s
        }
    }
}


// MARK: - Snapshot

extension Bus {

    /// WRAM, the I/O latches and the DMA/HDMA controller state.
    struct Snapshot: Codable {
        var wram: [UInt8]
        var openBus: UInt8
        var nmiEnable: Bool
        var autoJoypad: Bool
        var hdmaEnable: UInt8
        var nmiFlag: Bool
        var vblankFlag: Bool
        var multA: UInt8
        var multB: UInt8
        var divA: UInt16
        var divB: UInt8
        var lastOpWasDivide: Bool
        var joy1: UInt16
        var joy1Latched: UInt16
        var hIRQEnable: Bool
        var vIRQEnable: Bool
        var irqFlag: Bool
        var hTime: UInt16
        var vTime: UInt16
        var dmaChannels: [[UInt8]]
        var hdmaStates: [HDMAState]
    }

    func snapshot() -> Snapshot {
        return Snapshot(
            wram: wram, openBus: openBus,
            nmiEnable: nmiEnable, autoJoypad: autoJoypad,
            hdmaEnable: hdmaEnable, nmiFlag: nmiFlag, vblankFlag: vblankFlag,
            multA: multA, multB: multB, divA: divA, divB: divB,
            lastOpWasDivide: lastOpWasDivide,
            joy1: joy1, joy1Latched: joy1Latched,
            hIRQEnable: hIRQEnable, vIRQEnable: vIRQEnable, irqFlag: irqFlag,
            hTime: hTime, vTime: vTime,
            dmaChannels: dmaChannels, hdmaStates: hdmaStates
        )
    }

    func restore(_ s: Snapshot) {
        wram = s.wram
        openBus = s.openBus
        nmiEnable = s.nmiEnable
        autoJoypad = s.autoJoypad
        hdmaEnable = s.hdmaEnable
        nmiFlag = s.nmiFlag
        vblankFlag = s.vblankFlag
        multA = s.multA
        multB = s.multB
        divA = s.divA
        divB = s.divB
        lastOpWasDivide = s.lastOpWasDivide
        joy1 = s.joy1
        joy1Latched = s.joy1Latched
        hIRQEnable = s.hIRQEnable
        vIRQEnable = s.vIRQEnable
        irqFlag = s.irqFlag
        hTime = s.hTime
        vTime = s.vTime
        dmaChannels = s.dmaChannels
        hdmaStates = s.hdmaStates
    }
}
