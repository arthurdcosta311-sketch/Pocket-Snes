//
//  PPU.swift
//  Pocket Snes
//
//  Picture processing unit: VRAM/OAM/CGRAM, register file and a software
//  renderer for background modes 0-1 plus sprites. Unsupported tile modes
//  fall back to a mode-1-style render.
//

import Foundation

final class PPU {

    static let width = 256
    static let height = 224

    // MARK: - Memory

    var vram = [UInt8](repeating: 0, count: 0x10000)   // 64 KB = 32K words
    var oam = [UInt8](repeating: 0, count: 0x220)      // 512 + 32 bytes
    var cgram = [UInt8](repeating: 0, count: 0x200)    // 256 colors

    // MARK: - Registers

    var inidisp: UInt8 = 0x00          // $2100
    var obisel: UInt8 = 0x00           // $2101
    var bgmode: UInt8 = 0x00           // $2105
    var mosaic: UInt8 = 0x00           // $2106
    var bgsc: [UInt8] = [0, 0, 0, 0]   // $2107-$210A
    var bg12ba: UInt8 = 0              // $210B
    var bg34ba: UInt8 = 0              // $210C
    var bgx: [UInt16] = [0, 0, 0, 0]   // scroll
    var bgy: [UInt16] = [0, 0, 0, 0]
    var tm: UInt8 = 0                  // $212C main screen
    var ts: UInt8 = 0                  // $212D subscreen
    var cgwsel: UInt8 = 0              // $212A
    var cgadsub: UInt8 = 0             // $212B
    var fixedColorR: UInt8 = 0
    var fixedColorG: UInt8 = 0
    var fixedColorB: UInt8 = 0
    var m7a: UInt16 = 0
    var m7b: UInt8 = 0

    // Internal access state
    private var vramAddr: UInt16 = 0
    private var vramIncrement = 1
    private var vramRemapMode: UInt8 = 0
    private var vramReadBuffer: UInt16 = 0
    private var cgAddr: UInt8 = 0
    private var cgLatchHigh = false
    private var cgReadBuffer: UInt16 = 0
    private var oamAddr: UInt16 = 0
    private var scrollPrev: [UInt8] = [0, 0, 0, 0]

    // Timing state
    private(set) var scanline = 0
    private(set) var vblankFlag = false

    // Output: RGBA8, 256 x 224
    private(set) var frame = [UInt8](repeating: 0, count: 256 * 224 * 4)

    /// Sprite sizes indexed by the OBSEL size field: (small, large).
    static let spriteSizes: [(Int, Int)] = [
        (8, 16), (8, 32), (8, 64), (16, 32),
        (16, 64), (32, 64), (16, 32), (16, 32)
    ]

    // MARK: - Register interface

    func writeRegister(_ reg: UInt16, _ value: UInt8) {
        switch reg {
        case 0x00: inidisp = value
        case 0x01: obisel = value
        case 0x02: oamAddr = (oamAddr & 0x0200) | (UInt16(value) << 1)
        case 0x03: oamAddr = (oamAddr & 0x01FF) | (UInt16(value & 1) << 9)
        case 0x04: oamWrite(value)                       // OAMDATA
        case 0x05: bgmode = value
        case 0x06: mosaic = value
        case 0x07: bgsc[0] = value
        case 0x08: bgsc[1] = value
        case 0x09: bgsc[2] = value
        case 0x0A: bgsc[3] = value
        case 0x0B: bg12ba = value
        case 0x0C: bg34ba = value
        case 0x0D...0x14: writeScroll(reg, value)
        case 0x15:                                       // VMAIN
            vramIncrement = [1, 32, 128, 128][Int(value & 3)]
            vramRemapMode = (value >> 2) & 3
        case 0x16:
            vramAddr = (UInt16(value) << 8) | (vramAddr & 0xFF)
            vramReadBuffer = readVRAMWord(vramAddr)
        case 0x17:
            vramAddr = (vramAddr & 0xFF00) | UInt16(value)
            vramReadBuffer = readVRAMWord(vramAddr)
        case 0x18: vramWriteLo(value)                    // VMDATA low
        case 0x19: vramWriteHi(value)                    // VMDATA high
        case 0x1B: m7a = (m7a & 0xFF00) | UInt16(value)
        case 0x1C: m7a = (m7a & 0x00FF) | UInt16(value) << 8
        case 0x1D: m7b = value
        case 0x20: break                                 // M7SEL, not modelled
        case 0x21: cgAddr = value                        // CGADD
        case 0x22: cgWrite(value)                        // CGDATA
        case 0x23, 0x24: break                           // window selects, unused
        case 0x2C: tm = value                            // TM: main screen layers
        case 0x2D: ts = value                            // TS: subscreen layers
        case 0x30: cgwsel = value                        // CGWSEL
        case 0x31: cgadsub = value                       // CGADSUB
        case 0x32:                                       // COLDATA
            if value & 0x20 != 0 { fixedColorR = value & 0x1F }
            if value & 0x40 != 0 { fixedColorG = value & 0x1F }
            if value & 0x80 != 0 { fixedColorB = value & 0x1F }
        default: break
        }
    }

    func readRegister(_ reg: UInt16) -> UInt8 {
        switch reg {
        case 0x04:
            let v = oam[Int(oamAddr & 0x03FF)]
            oamAddr = (oamAddr &+ 1) & 0x03FF
            return v
        case 0x34, 0x35, 0x36:
            let product = Int(Int16(bitPattern: m7a)) * Int(Int8(bitPattern: m7b))
            let shift = Int(reg - 0x34) * 8
            return UInt8(truncatingIfNeeded: product >> shift)
        case 0x37: return cgRead()
        case 0x38:
            // OAMDATA read: the byte at OAMADDR, then OAMADDR advances.
            let v = oam[Int(oamAddr & 0x03FF)]
            oamAddr = (oamAddr &+ 1) & 0x03FF
            return v
        case 0x39:
            let v = UInt8(truncatingIfNeeded: vramReadBuffer)
            vramReadBuffer = readVRAMWord(vramAddr)
            return v
        case 0x3A:
            let hi = UInt8(truncatingIfNeeded: vramReadBuffer >> 8)
            vramReadBuffer = readVRAMWord(vramAddr)
            vramAddr &+= UInt16(vramIncrement)
            return hi
        case 0x3B:
            let v = cgLatchHigh ? UInt8(truncatingIfNeeded: cgReadBuffer >> 8)
                                : UInt8(truncatingIfNeeded: cgReadBuffer)
            if cgLatchHigh { cgAddr = cgAddr &+ 1 }
            cgReadBuffer = cgramColor(Int(cgAddr))
            cgLatchHigh.toggle()
            return v
        case 0x3F:
            var v: UInt8 = 0
            if vblankFlag { v |= 0x80 }
            return v | 0x20
        default:
            return 0
        }
    }

    // MARK: - VRAM / OAM / CGRAM access

    private func remap(_ a: UInt16) -> UInt16 {
        switch vramRemapMode {
        case 1: return (a & 0xFF00) | ((a & 0x1C) << 3) | (a & 3)
        case 2: return (a & 0xFF00) | ((a & 1) << 8) | ((a >> 1) & 0x7F)
        case 3: return (a & 0xFE00) | ((a & 1) << 8) | ((a >> 1) & 0xFF)
        default: return a & 0x7FFF
        }
    }

    private func vramWriteLo(_ v: UInt8) {
        vram[(Int(remap(vramAddr)) << 1) & 0xFFFF] = v
    }

    private func vramWriteHi(_ v: UInt8) {
        vram[((Int(remap(vramAddr)) << 1) | 1) & 0xFFFF] = v
        vramAddr &+= UInt16(vramIncrement)
    }

    private func readVRAMWord(_ wordAddr: UInt16) -> UInt16 {
        let b = Int(remap(wordAddr)) << 1
        return UInt16(vram[b & 0xFFFF]) | UInt16(vram[(b + 1) & 0xFFFF]) << 8
    }

    private func oamWrite(_ v: UInt8) {
        oam[Int(oamAddr & 0x03FF)] = v
        oamAddr = (oamAddr &+ 1) & 0x03FF
    }

    private func cgWrite(_ v: UInt8) {
        let index = Int(cgAddr) * 2 + (cgLatchHigh ? 1 : 0)
        cgram[index & 0x1FF] = v
        if cgLatchHigh { cgAddr = cgAddr &+ 1 }
        cgLatchHigh.toggle()
    }

    private func cgRead() -> UInt8 {
        let v = cgLatchHigh ? UInt8(truncatingIfNeeded: cgReadBuffer >> 8)
                            : UInt8(truncatingIfNeeded: cgReadBuffer)
        if cgLatchHigh { cgAddr = cgAddr &+ 1 }
        cgReadBuffer = cgramColor(Int(cgAddr))
        cgLatchHigh.toggle()
        return v
    }

    // Expose CGRAM write for DMA and tests through the normal register path.
    func writeCGDATA(_ v: UInt8) { cgWrite(v) }

    private func cgramColor(_ index: Int) -> UInt16 {
        let a = (index * 2) & 0x1FF
        return UInt16(cgram[a]) | UInt16(cgram[a + 1]) << 8
    }

    private func writeScroll(_ reg: UInt16, _ value: UInt8) {
        let idx = Int((reg - 0x0D) / 2)
        let isX = (reg - 0x0D) % 2 == 0
        let raw = (UInt16(value) << 8) | UInt16(scrollPrev[idx])
        scrollPrev[idx] = value
        let offset = UInt16(raw & 0x03FF)
        if isX { bgx[idx] = offset } else { bgy[idx] = offset }
    }

    // MARK: - Frame timing

    func startFrame() {
        vblankFlag = false
    }

    func runScanline(_ line: Int) {
        scanline = line
        if line == 225 {
            vblankFlag = true
            return
        }
        guard line < PPU.height else { return }
        renderLine(line)
    }

    // MARK: - Rendering

    private func renderLine(_ line: Int) {
        guard inidisp & 0x80 != 0 else {
            fillLine(line, color555: 0)
            return
        }

        var buf = [UInt16](repeating: 0, count: 256)
        var pri = [Int8](repeating: -1, count: 256)
        var lay = [Int8](repeating: -1, count: 256)

        var mode = bgmode & 0x07
        if mode >= 2 { mode = 1 } // Unsupported tile modes: approximate as mode 1

        // Draw BG4 -> BG1 so that, at equal priority, BG1 wins.
        for layer in (0...3).reversed() {
            guard tm & (1 << layer) != 0 else { continue }
            if mode == 1 && layer == 3 { continue }
            renderBG(layer, line: line, mode: mode, buf: &buf, pri: &pri, lay: &lay)
        }
        renderSprites(line, buf: &buf, pri: &pri, lay: &lay)

        let backdrop = cgramColor(0)
        for x in 0..<256 {
            var color = backdrop
            if lay[x] >= 0 {
                color = applyColorMath(buf[x], layer: Int(lay[x]))
            }
            setFramePixel(line: line, x: x, color555: color)
        }
    }

    private func renderBG(_ layer: Int, line: Int, mode: UInt8,
                          buf: inout [UInt16], pri: inout [Int8], lay: inout [Int8]) {
        let bpp2 = mode == 0 || (mode == 1 && layer == 2)
        let cbase = charBaseFor(mode: mode, layer: layer)
        let size16 = tileSize16(layer)
        let shift = size16 ? 4 : 3
        let scrollX = Int(bgx[layer])
        let scrollY = Int(bgy[layer])
        let basePriority = Int8((bgsc[layer] >> 13) & 3)

        for px in 0..<256 {
            let sx = px + scrollX
            let sy = line + scrollY
            let tx = sx >> shift
            let ty = sy >> shift
            let entry = mapEntry(layer, tx: tx, ty: ty)
            let color = pixelColor(entry, charBase: cbase, bpp2: bpp2,
                                   sx: sx, sy: sy, size16: size16)
            guard color >= 0 else { continue }
            let p: Int8 = (entry & 0x2000) != 0 ? 3 : basePriority
            if p >= pri[px] {
                buf[px] = UInt16(color)
                pri[px] = p
                lay[px] = Int8(layer)
            }
        }
    }

    private func charBaseFor(mode: UInt8, layer: Int) -> Int {
        func nib(_ v: UInt8, _ high: Bool) -> Int { Int((high ? v >> 4 : v) & 0xF) }
        switch mode {
        case 0:
            if layer < 2 { return nib(bg12ba, layer == 1) << 12 }
            return nib(bg34ba, layer == 3) << 12
        case 1:
            if layer < 2 { return nib(bg12ba, layer == 1) << 12 }
            return Int((bgmode >> 4) & 0x3) << 12
        default:
            return 0
        }
    }

    private func tileSize16(_ layer: Int) -> Bool {
        if layer < 2 { return bgmode & 0x80 != 0 }
        return bg34ba & 0x80 != 0
    }

    private func mapEntry(_ layer: Int, tx: Int, ty: Int) -> Int {
        let sc = Int(bgsc[layer])
        let base = (sc & 0x03FF) << 10
        let wide = sc & (1 << 10) != 0
        let tall = sc & (1 << 11) != 0
        var x = tx, y = ty
        var quadrant = 0
        if tx >= 32 {
            if wide { quadrant |= 1 }
            x = tx & 31
        }
        if ty >= 32 {
            if tall { quadrant |= 2 }
            y = ty & 31
        }
        let addr = base + (quadrant << 11) + ((y & 31) << 6) + ((x & 31) << 1)
        return Int(vram[addr & 0xFFFF]) | Int(vram[(addr + 1) & 0xFFFF]) << 8
    }

    /// Returns a BGR555 color, or -1 when the pixel is transparent.
    private func pixelColor(_ entry: Int, charBase: Int, bpp2: Bool,
                            sx: Int, sy: Int, size16: Bool) -> Int {
        var tile = entry & 0x3FF
        let hflip = entry & 0x4000 != 0
        let vflip = entry & 0x8000 != 0
        let pal = (entry >> 10) & 7

        let mask = size16 ? 15 : 7
        var cx = sx & mask
        var cy = sy & mask
        if hflip { cx = mask - cx }
        if vflip { cy = mask - cy }

        if size16 {
            // Sub-tiles ladder +1 per column, +16 per row.
            let col = (sx >> 3) & 1
            let row = (sy >> 3) & 1
            tile += col + row * 16
        }

        let bytesPerTile = bpp2 ? 16 : 32
        let base = charBase + tile * bytesPerTile + (cy & 7) * 2
        let bit = 7 - (cx & 7)
        var value = 0
        if bpp2 {
            let b0 = Int(vram[base & 0xFFFF])
            let b1 = Int(vram[(base + 1) & 0xFFFF])
            value = ((b0 >> bit) & 1) | (((b1 >> bit) & 1) << 1)
        } else {
            let b0 = Int(vram[base & 0xFFFF])
            let b1 = Int(vram[(base + 1) & 0xFFFF])
            let b2 = Int(vram[(base + 16) & 0xFFFF])
            let b3 = Int(vram[(base + 17) & 0xFFFF])
            let low = ((b0 >> bit) & 1) | (((b1 >> bit) & 1) << 1)
            let high = (((b2 >> bit) & 1) << 2) | (((b3 >> bit) & 1) << 3)
            value = low | high
        }
        guard value != 0 else { return -1 }
        let colorIndex = bpp2 ? pal * 4 + value : pal * 16 + value
        return Int(cgramColor(colorIndex))
    }

    private func renderSprites(_ line: Int, buf: inout [UInt16],
                               pri: inout [Int8], lay: inout [Int8]) {
        let sizeIndex = Int(obisel >> 5) & 7
        let nameBase = Int(obisel & 0x7) << 13
        let small = PPU.spriteSizes[sizeIndex].0
        let large = PPU.spriteSizes[sizeIndex].1

        for i in stride(from: 127, through: 0, by: -1) {
            let o = i * 4
            var x = Int(oam[o])
            let y = Int(oam[o + 1])
            var tile = Int(oam[o + 2])
            let attr = oam[o + 3]
            // High table: two sprites per byte, bit 2n = X MSB of sprite 2n.
            let h = oam[0x200 + (i >> 1)]
            x |= ((Int(h) >> ((i & 1) * 2)) & 1) << 8

            let (sw, sh) = attr & 0x80 != 0 ? (large, large) : (small, small)
            let sy = ((line - y) % 256 + 256) % 256
            guard sy < sh else { continue }
            let row = (attr & 0x40 != 0) ? (sh - 1 - sy) : sy
            let pal = Int(attr & 0x7)
            let sprio: Int8 = attr & 0x10 != 0 ? 2 : 0
            let hflip = attr & 0x20 != 0

            for px in 0..<sw {
                let sx = x + px
                guard sx < 256 else { continue }
                let col = hflip ? (7 - (px & 7)) : (px & 7)
                // Sub-tiles ladder +1 per column, +16 per row.
                let tileN = tile + (px >> 3) + (row >> 3) * 16
                let charAddr = nameBase + tileN * 32 + (row & 7) * 2
                let bit = 7 - col
                let b0 = vram[charAddr & 0xFFFF]
                let b1 = vram[(charAddr + 1) & 0xFFFF]
                let b2 = vram[(charAddr + 16) & 0xFFFF]
                let b3 = vram[(charAddr + 17) & 0xFFFF]
                let value = ((b0 >> bit) & 1) | (((b1 >> bit) & 1) << 1)
                           | (((b2 >> bit) & 1) << 2) | (((b3 >> bit) & 1) << 3)
                guard value != 0 else { continue }
                let color = cgramColor(128 + pal * 16 + Int(value))
                if sprio >= pri[sx] {
                    buf[sx] = color
                    pri[sx] = sprio
                    lay[sx] = 4
                }
            }
        }
    }

    private func applyColorMath(_ color: UInt16, layer: Int) -> UInt16 {
        guard cgwsel & 0x02 != 0 else { return color }
        let bit: UInt8 = layer < 4 ? UInt8(1 << layer) : 0x10
        guard cgadsub & bit != 0 else { return color }
        let fixed = UInt16(fixedColorR) | UInt16(fixedColorG) << 5 | UInt16(fixedColorB) << 10
        let sub = cgadsub & 0x80 != 0
        let half = cgadsub & 0x40 != 0
        var r = Int(color & 0x1F), g = Int((color >> 5) & 0x1F), b = Int((color >> 10) & 0x1F)
        let fr = Int(fixed & 0x1F), fg = Int((fixed >> 5) & 0x1F), fb = Int((fixed >> 10) & 0x1F)
        if sub {
            r = max(0, r - fr); g = max(0, g - fg); b = max(0, b - fb)
        } else {
            r = min(0x1F, r + fr); g = min(0x1F, g + fg); b = min(0x1F, b + fb)
        }
        if half { r /= 2; g /= 2; b /= 2 }
        return UInt16(r) | UInt16(g) << 5 | UInt16(b) << 10
    }

    private func setFramePixel(line: Int, x: Int, color555: UInt16) {
        let i = (line * 256 + x) * 4
        guard i + 3 < frame.count else { return }
        let r5 = Int(color555 & 0x1F)
        let g5 = Int((color555 >> 5) & 0x1F)
        let b5 = Int((color555 >> 10) & 0x1F)
        frame[i] = UInt8(r5 << 3 | r5 >> 2)
        frame[i + 1] = UInt8(g5 << 3 | g5 >> 2)
        frame[i + 2] = UInt8(b5 << 3 | b5 >> 2)
        frame[i + 3] = 255
    }

    private func fillLine(_ line: Int, color555: UInt16) {
        for x in 0..<256 {
            setFramePixel(line: line, x: x, color555: color555)
        }
    }
}


// MARK: - Snapshot

extension PPU {

    /// VRAM, OAM, CGRAM, the register file and the internal access latches.
    struct Snapshot: Codable {
        var vram: [UInt8]
        var oam: [UInt8]
        var cgram: [UInt8]

        var inidisp: UInt8
        var obisel: UInt8
        var bgmode: UInt8
        var mosaic: UInt8
        var bgsc: [UInt8]
        var bg12ba: UInt8
        var bg34ba: UInt8
        var bgx: [UInt16]
        var bgy: [UInt16]
        var tm: UInt8
        var ts: UInt8
        var cgwsel: UInt8
        var cgadsub: UInt8
        var fixedColorR: UInt8
        var fixedColorG: UInt8
        var fixedColorB: UInt8
        var m7a: UInt16
        var m7b: UInt8

        var vramAddr: UInt16
        var vramIncrement: Int
        var vramRemapMode: UInt8
        var vramReadBuffer: UInt16
        var cgAddr: UInt8
        var cgLatchHigh: Bool
        var cgReadBuffer: UInt16
        var oamAddr: UInt16
        var scrollPrev: [UInt8]
        var scanline: Int
        var vblankFlag: Bool
    }

    func snapshot() -> Snapshot {
        return Snapshot(
            vram: vram, oam: oam, cgram: cgram,
            inidisp: inidisp, obisel: obisel, bgmode: bgmode, mosaic: mosaic,
            bgsc: bgsc, bg12ba: bg12ba, bg34ba: bg34ba, bgx: bgx, bgy: bgy,
            tm: tm, ts: ts, cgwsel: cgwsel, cgadsub: cgadsub,
            fixedColorR: fixedColorR, fixedColorG: fixedColorG, fixedColorB: fixedColorB,
            m7a: m7a, m7b: m7b,
            vramAddr: vramAddr, vramIncrement: vramIncrement,
            vramRemapMode: vramRemapMode, vramReadBuffer: vramReadBuffer,
            cgAddr: cgAddr, cgLatchHigh: cgLatchHigh, cgReadBuffer: cgReadBuffer,
            oamAddr: oamAddr, scrollPrev: scrollPrev,
            scanline: scanline, vblankFlag: vblankFlag
        )
    }

    func restore(_ s: Snapshot) {
        vram = s.vram
        oam = s.oam
        cgram = s.cgram
        inidisp = s.inidisp
        obisel = s.obisel
        bgmode = s.bgmode
        mosaic = s.mosaic
        bgsc = s.bgsc
        bg12ba = s.bg12ba
        bg34ba = s.bg34ba
        bgx = s.bgx
        bgy = s.bgy
        tm = s.tm
        ts = s.ts
        cgwsel = s.cgwsel
        cgadsub = s.cgadsub
        fixedColorR = s.fixedColorR
        fixedColorG = s.fixedColorG
        fixedColorB = s.fixedColorB
        m7a = s.m7a
        m7b = s.m7b
        vramAddr = s.vramAddr
        vramIncrement = s.vramIncrement
        vramRemapMode = s.vramRemapMode
        vramReadBuffer = s.vramReadBuffer
        cgAddr = s.cgAddr
        cgLatchHigh = s.cgLatchHigh
        cgReadBuffer = s.cgReadBuffer
        oamAddr = s.oamAddr
        scrollPrev = s.scrollPrev
        scanline = s.scanline
        vblankFlag = s.vblankFlag
    }
}
