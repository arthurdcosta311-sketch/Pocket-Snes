//
//  CPU65816.swift
//  Pocket Snes
//
//  A MOS 65816 interpreter core: native + emulation mode, full official
//  instruction set, 8/16-bit register widths and decimal arithmetic.
//  Cycle counts are approximations sufficient for scanline-paced execution.
//

import Foundation

final class CPU65816 {

    // MARK: - Registers

    private(set) var a: UInt16 = 0        // Accumulator (C when 16-bit)
    private(set) var x: UInt16 = 0
    private(set) var y: UInt16 = 0
    private(set) var sp: UInt16 = 0x01FF  // Stack pointer
    private(set) var dp: UInt16 = 0       // Direct page
    private(set) var db: UInt8 = 0        // Data bank
    private(set) var k: UInt8 = 0         // Program bank
    private(set) var pc: UInt16 = 0       // Program counter (within bank)
    private(set) var emu = true           // Emulation mode flag (E)

    // Status flags
    private(set) var fCarry = false
    private(set) var fZero = false
    private(set) var fIRQDisable = true
    private(set) var fDecimal = false
    private(set) var fIndex8 = true
    private(set) var fAccum8 = true
    private(set) var fOverflow = false
    private(set) var fNegative = false

    private(set) var halted = false
    private var waiting = false

    /// Rough cycle cost of the last executed instruction, consumed by the
    /// scanline-paced timing loop.
    private(set) var cycleDebt = 0

    var nmiPending = false
    var irqPending = false

    let bus: Bus

    init(bus: Bus) {
        self.bus = bus
        reset()
    }

    // MARK: - Lifecycle

    func reset() {
        emu = true
        fAccum8 = true
        fIndex8 = true
        fIRQDisable = true
        fDecimal = false
        sp = 0x01FF
        k = 0
        pc = read16(0xFFFC)
        db = 0
        dp = 0
        halted = false
        waiting = false
        nmiPending = false
        irqPending = false
    }

    // MARK: - Fetch helpers

    private func fetch8() -> UInt8 {
        let v = bus.read((UInt32(k) << 16) | UInt32(pc))
        pc &+= 1
        return v
    }

    private func fetch16() -> UInt16 {
        UInt16(fetch8()) | UInt16(fetch8()) << 8
    }

    private func fetch24() -> UInt32 {
        UInt32(fetch16()) | UInt32(fetch8()) << 16
    }

    private func fetchImm(_ width: Int) -> UInt16 {
        width == 2 ? fetch16() : UInt16(fetch8())
    }

    private func read16(_ addr: UInt32) -> UInt16 {
        UInt16(bus.read(addr)) | UInt16(bus.read(addr &+ 1)) << 8
    }

    private func readW(_ addr: UInt32, width: Int) -> UInt16 {
        width == 2
            ? UInt16(bus.read(addr)) | UInt16(bus.read(addr &+ 1)) << 8
            : UInt16(bus.read(addr))
    }

    private func writeW(_ addr: UInt32, _ v: UInt16, width: Int) {
        if width == 2 {
            bus.write(addr, UInt8(truncatingIfNeeded: v))
            bus.write(addr &+ 1, UInt8(truncatingIfNeeded: v >> 8))
        } else {
            bus.write(addr, UInt8(truncatingIfNeeded: v))
        }
    }

    // MARK: - Stack

    private func push(_ v: UInt8) {
        bus.write(UInt32(sp), v)
        sp &-= 1
        // In emulation mode the stack lives only in page $01.
        if emu, sp < 0x0100 { sp |= 0x0100 }
    }

    private func pop() -> UInt8 {
        sp &+= 1
        if emu, sp > 0x01FF { sp = 0x0100 }
        return bus.read(UInt32(sp))
    }

    private func push16(_ v: UInt16) {
        push(UInt8(truncatingIfNeeded: v >> 8))
        push(UInt8(truncatingIfNeeded: v))
    }

    private func pop16() -> UInt16 {
        let lo = pop()
        return UInt16(pop()) << 8 | UInt16(lo)
    }

    private func pushAccum() {
        if fAccum8 {
            push(UInt8(truncatingIfNeeded: a))
        } else {
            push(UInt8(truncatingIfNeeded: a >> 8))
            push(UInt8(truncatingIfNeeded: a))
        }
    }

    private func popAccum() {
        if fAccum8 {
            a = (a & 0xFF00) | UInt16(pop())
        } else {
            let lo = pop()
            let hi = pop()
            a = UInt16(hi) << 8 | UInt16(lo)
        }
    }

    // MARK: - Flags

    private var aw: Int { fAccum8 ? 1 : 2 }
    private var xw: Int { fIndex8 ? 1 : 2 }

    func getP() -> UInt8 {
        var p: UInt8 = 0
        if fCarry { p |= 0x01 }
        if fZero { p |= 0x02 }
        if fIRQDisable { p |= 0x04 }
        if fDecimal { p |= 0x08 }
        if fIndex8 { p |= 0x10 }
        if fAccum8 { p |= 0x20 }
        if fOverflow { p |= 0x40 }
        if fNegative { p |= 0x80 }
        return p
    }

    func setP(_ v: UInt8) {
        fCarry = v & 0x01 != 0
        fZero = v & 0x02 != 0
        fIRQDisable = v & 0x04 != 0
        fDecimal = v & 0x08 != 0
        fIndex8 = v & 0x10 != 0
        fAccum8 = v & 0x20 != 0
        fOverflow = v & 0x40 != 0
        fNegative = v & 0x80 != 0
    }

    private func setNZ(_ v: UInt16, width: Int) {
        if width == 2 {
            fZero = v == 0
            fNegative = v & 0x8000 != 0
        } else {
            let b = UInt8(truncatingIfNeeded: v)
            fZero = b == 0
            fNegative = b & 0x80 != 0
        }
    }

    /// Loads and transfers all land here. OR-ing a load into the old register
    /// (`(a & 0xFF00) | value`) left the previous high byte's bits set through
    /// every 16-bit LDA/PLA, so set-up code computed wrong addresses and left
    /// the console blank. A 16-bit load replaces both halves; an 8-bit one
    /// clears the high byte.
    private func setAccum(_ value: UInt16) {
        a = fAccum8 ? value & 0x00FF : value
        setNZ(a, width: aw)
    }

    private func setXReg(_ value: UInt16) {
        x = fIndex8 ? value & 0x00FF : value
        setNZ(x, width: xw)
    }

    private func setYReg(_ value: UInt16) {
        y = fIndex8 ? value & 0x00FF : value
        setNZ(y, width: xw)
    }

    // MARK: - Addressing modes (linear 24-bit effective addresses)

    private func dataAddr(_ offset: UInt16) -> UInt32 {
        (UInt32(db) << 16) | UInt32(offset)
    }

    private func direct(_ offset: UInt8) -> UInt16 {
        dp &+ UInt16(offset)
    }

    private func readDirect16(_ offset: UInt8) -> UInt16 {
        let p = direct(offset)
        return UInt16(bus.read(UInt32(p))) | UInt16(bus.read(UInt32(p &+ 1))) << 8
    }

    private func addrZP() -> UInt32 { UInt32(direct(fetch8())) }

    private func addrZPX() -> UInt32 { UInt32(direct(fetch8() &+ UInt8(truncatingIfNeeded: x))) }

    private func addrZPY() -> UInt32 { UInt32(direct(fetch8() &+ UInt8(truncatingIfNeeded: y))) }

    private func addrAbs() -> UInt32 { dataAddr(fetch16()) }

    /// In 8-bit index mode the high byte of X is forced to zero, no matter
    /// what a previous 16-bit write left there.
    private func indexX() -> UInt16 {
        fIndex8 ? x & 0xFF : x
    }

    private func indexY() -> UInt16 {
        fIndex8 ? y & 0xFF : y
    }

    private func addrAbsX() -> UInt32 { dataAddr(fetch16() &+ indexX()) }

    private func addrAbsY() -> UInt32 { dataAddr(fetch16() &+ indexY()) }

    private func addrIZP() -> UInt32 { dataAddr(readDirect16(fetch8())) }

    private func addrIZPY() -> UInt32 { dataAddr(readDirect16(fetch8()) &+ indexY()) }

    private func addrIZPX() -> UInt32 {
        let p = direct(fetch8() &+ UInt8(truncatingIfNeeded: x))
        return dataAddr(UInt16(bus.read(UInt32(p))) | UInt16(bus.read(UInt32(p &+ 1))) << 8)
    }

    private func addrAbsInd() -> UInt32 {
        let p = fetch16()
        let lo = bus.read(UInt32(p))
        let hi = bus.read(UInt32((p &+ 1) & 0xFFFF))
        return dataAddr(UInt16(lo) | UInt16(hi) << 8)
    }

    private func addrAbsIndX() -> UInt32 {
        let p = (UInt32(k) << 16) | UInt32(fetch16() &+ indexX())
        let lo = bus.read(p)
        let hi = bus.read((UInt32(k) << 16) | UInt32((UInt16(p) &+ 1) & 0xFFFF))
        return (UInt32(k) << 16) | UInt32(UInt16(lo) | UInt16(hi) << 8)
    }

    private func addrLong() -> UInt32 { fetch24() }

    private func addrLongX() -> UInt32 { fetch24() &+ UInt32(x) }

    private func addrDPLong() -> UInt32 {
        let p = direct(fetch8())
        var v: UInt32 = UInt32(bus.read(UInt32(p)))
        v |= UInt32(bus.read(UInt32(p &+ 1))) << 8
        v |= UInt32(bus.read(UInt32(p &+ 2))) << 16
        return v
    }

    private func addrDPLongY() -> UInt32 { addrDPLong() &+ UInt32(y) }

    private func addrABLLongInd() -> UInt32 {
        let p = fetch16()
        var v: UInt32 = UInt32(bus.read(UInt32(p)))
        v |= UInt32(bus.read(UInt32(p &+ 1))) << 8
        v |= UInt32(bus.read(UInt32(p &+ 2))) << 16
        return v
    }

    private func addrSR() -> UInt32 {
        let o = fetch8()
        return UInt32((sp &+ 1 &+ UInt16(o)) & 0xFFFF)
    }

    private func addrSRY() -> UInt32 {
        let o = fetch8()
        let ptr = UInt32((sp &+ 1 &+ UInt16(o)) & 0xFFFF)
        let lo = bus.read(ptr)
        let hi = bus.read((ptr &+ 1) & 0xFFFF)
        let targetOff = (UInt16(lo) | (UInt16(hi) << 8)) &+ indexY()
        return dataAddr(targetOff)
    }

    private func branch8(_ condition: Bool) {
        let offset = Int8(bitPattern: fetch8())
        if condition {
            cycleDebt += 2
            pc = pc &+ UInt16(bitPattern: Int16(offset))
        }
    }

    // MARK: - Arithmetic / logic ops

    private func opADC(_ operand: UInt16, width: Int) {
        if width == 2 {
            let r = Int(a) + Int(operand) + (fCarry ? 1 : 0)
            fOverflow = (~(a ^ operand) & (a ^ UInt16(truncatingIfNeeded: r)) & 0x8000) != 0
            fCarry = r > 0xFFFF
            a = UInt16(truncatingIfNeeded: r)
            setNZ(a, width: 2)
        } else {
            let op = UInt8(truncatingIfNeeded: operand)
            if fDecimal {
                var al = Int(a & 0x0F) + Int(op & 0x0F) + (fCarry ? 1 : 0)
                if al > 9 { al += 6 }
                var ah = Int((a >> 4) & 0x0F) + Int((op >> 4) & 0x0F) + (al > 0x0F ? 1 : 0)
                fZero = ((a &+ UInt16(op) &+ (fCarry ? 1 : 0)) & 0xFF) == 0
                fNegative = ah & 0x08 != 0
                fOverflow = (~(a ^ UInt16(op)) & (a ^ UInt16(ah << 4)) & 0x80) != 0
                if ah > 9 { ah += 6 }
                fCarry = ah > 0x0F
                a = (a & 0xFF00) | (UInt16(ah & 0x0F) << 4) | UInt16(al & 0x0F)
            } else {
                let r = Int(a & 0xFF) + Int(op) + (fCarry ? 1 : 0)
                fOverflow = (~(a ^ UInt16(op)) & (a ^ UInt16(truncatingIfNeeded: r)) & 0x80) != 0
                fCarry = r > 0xFF
                a = (a & 0xFF00) | UInt16(truncatingIfNeeded: r)
                setNZ(a, width: 1)
            }
        }
    }

    private func opSBC(_ operand: UInt16, width: Int) {
        if fDecimal && width == 1 {
            let op = UInt8(truncatingIfNeeded: operand)
            let borrow = fCarry ? 0 : 1
            var al = Int(a & 0x0F) - Int(op & 0x0F) - borrow
            var ah = Int((a >> 4) & 0x0F) - Int((op >> 4) & 0x0F)
            fOverflow = (~(a ^ UInt16(op)) & (a ^ UInt16(truncatingIfNeeded: Int(a) - Int(op) - borrow)) & 0x80) != 0
            fNegative = ah & 0x08 != 0
            fZero = ((Int(a) - Int(op) - borrow) & 0xFF) == 0
            if al < 0 { al -= 6; ah -= 1 }
            if ah < 0 { ah -= 6 }
            fCarry = (Int(a) - Int(op) - borrow) >= 0
            a = (a & 0xFF00) | (UInt16(ah & 0x0F) << 4) | UInt16(al & 0x0F)
            return
        }
        if width == 2 {
            opADC(~operand, width: 2)
        } else {
            opADC(UInt16(UInt8(~UInt8(truncatingIfNeeded: operand))), width: 1)
        }
    }

    private func opAND(_ operand: UInt16, width: Int) {
        a = width == 2 ? a & operand : (a & 0xFF00) | ((a & operand) & 0xFF)
        setNZ(a, width: width)
    }

    private func opORA(_ operand: UInt16, width: Int) {
        a = width == 2 ? a | operand : (a & 0xFF00) | ((a | operand) & 0xFF)
        setNZ(a, width: width)
    }

    private func opEOR(_ operand: UInt16, width: Int) {
        a = width == 2 ? a ^ operand : (a & 0xFF00) | ((a ^ operand) & 0xFF)
        setNZ(a, width: width)
    }

    private func opCMP(_ reg: UInt16, _ operand: UInt16, width: Int) {
        // Compare at the operand width: in 8-bit mode only the low halves
        // count, whatever the high byte of A happens to hold. Comparing the
        // full registers made every 8-bit test read as "greater".
        let mask: UInt16 = width == 2 ? 0xFFFF : 0x00FF
        let r = Int(reg & mask) - Int(operand & mask)
        fCarry = r >= 0
        setNZ(UInt16(truncatingIfNeeded: r), width: width)
    }

    private func opBIT(_ v: UInt16, width: Int) {
        let mask: UInt16 = width == 2 ? 0xFFFF : 0xFF
        fZero = (a & v & mask) == 0
        fNegative = v & (width == 2 ? 0x8000 : 0x80) != 0
        fOverflow = v & (width == 2 ? 0x4000 : 0x40) != 0
    }

    private func opASL(_ v: UInt16, width: Int) -> UInt16 {
        fCarry = (width == 2 ? v & 0x8000 : v & 0x80) != 0
        let r = (v << 1) & (width == 2 ? 0xFFFF : 0xFF)
        setNZ(r, width: width)
        return r
    }

    private func opLSR(_ v: UInt16, width: Int) -> UInt16 {
        fCarry = (v & 1) != 0
        let r = v >> 1
        setNZ(r, width: width)
        return r
    }

    private func opROL(_ v: UInt16, width: Int) -> UInt16 {
        let cin: UInt16 = fCarry ? 1 : 0
        fCarry = (width == 2 ? v & 0x8000 : v & 0x80) != 0
        let r = ((v << 1) | cin) & (width == 2 ? 0xFFFF : 0xFF)
        setNZ(r, width: width)
        return r
    }

    private func opROR(_ v: UInt16, width: Int) -> UInt16 {
        let cin: UInt16 = fCarry ? 1 : 0
        fCarry = (v & 1) != 0
        let r = (v >> 1) | (cin << (width == 2 ? 15 : 7))
        setNZ(r, width: width)
        return r
    }

    // MARK: - Interrupts

    private func enterInterrupt(vector: UInt32) {
        if emu {
            push16(pc)
            push(getP() | 0x30)
        } else {
            push(UInt8(k))
            push16(pc)
            push(getP())
            k = 0
        }
        fIRQDisable = true
        pc = read16(vector)
    }

    private func performNMI() {
        nmiPending = false
        waiting = false
        enterInterrupt(vector: emu ? 0xFFFA : 0xFFEA)
    }

    private func performIRQ() {
        irqPending = false
        waiting = false
        enterInterrupt(vector: emu ? 0xFFFE : 0xFFEE)
    }

    // MARK: - Execution

    func step() {
        if waiting {
            // Sleep until something wakes the CPU: an NMI, or an IRQ while
            // interrupts are enabled.
            if nmiPending || (irqPending && !fIRQDisable) {
                waiting = false
            } else {
                cycleDebt = 4
                return
            }
        }
        if nmiPending {
            performNMI()
            cycleDebt = 8
            return
        }
        if irqPending, !fIRQDisable {
            performIRQ()
            cycleDebt = 8
            return
        }
        cycleDebt = 0
        let opcode = fetch8()
        execute(opcode)
        cycleDebt += baseCycles(opcode)
    }

    private func execute(_ op: UInt8) {
        switch op {

        // MARK: LDA
        case 0xA9: setAccum(fetchImm(aw))
        case 0xA5: setAccum(readW(addrZP(), width: aw))
        case 0xB5: setAccum(readW(addrZPX(), width: aw))
        case 0xB2: setAccum(readW(addrIZP(), width: aw))
        case 0xA1: setAccum(readW(addrIZPX(), width: aw))
        case 0xB1: setAccum(readW(addrIZPY(), width: aw))
        case 0xAD: setAccum(readW(addrAbs(), width: aw))
        case 0xBD: setAccum(readW(addrAbsX(), width: aw))
        case 0xB9: setAccum(readW(addrAbsY(), width: aw))
        case 0xA7: setAccum(readW(addrDPLong(), width: aw))
        case 0xB7: setAccum(readW(addrDPLongY(), width: aw))
        case 0xAF: setAccum(readW(addrLong(), width: aw))
        case 0xBF: setAccum(readW(addrLongX(), width: aw))
        case 0xA3: setAccum(readW(addrSR(), width: aw))
        case 0xB3: setAccum(readW(addrSRY(), width: aw))

        // MARK: LDX / LDY
        case 0xA2: setXReg(fetchImm(xw))
        case 0xA6: setXReg(readW(addrZP(), width: xw))
        case 0xB6: setXReg(readW(addrZPY(), width: xw))
        case 0xAE: setXReg(readW(addrAbs(), width: xw))
        case 0xBE: setXReg(readW(addrAbsY(), width: xw))
        case 0xA0: setYReg(fetchImm(xw))
        case 0xA4: setYReg(readW(addrZP(), width: xw))
        case 0xB4: setYReg(readW(addrZPX(), width: xw))
        case 0xAC: setYReg(readW(addrAbs(), width: xw))
        case 0xBC: setYReg(readW(addrAbsX(), width: xw))

        // MARK: STA
        case 0x8D: writeW(addrAbs(), a, width: aw)
        case 0x8F: writeW(addrLong(), a, width: aw)
        case 0x85: writeW(addrZP(), a, width: aw)
        case 0x95: writeW(addrZPX(), a, width: aw)
        case 0x92: writeW(addrIZP(), a, width: aw)
        case 0x81: writeW(addrIZPX(), a, width: aw)
        case 0x91: writeW(addrIZPY(), a, width: aw)
        case 0x87: writeW(addrDPLong(), a, width: aw)
        case 0x97: writeW(addrDPLongY(), a, width: aw)
        case 0x9D: writeW(addrAbsX(), a, width: aw)
        case 0x99: writeW(addrAbsY(), a, width: aw)
        case 0x9F: writeW(addrLongX(), a, width: aw)
        case 0x83: writeW(addrSR(), a, width: aw)
        case 0x93: writeW(addrSRY(), a, width: aw)

        // MARK: STX / STY / STZ
        case 0x8E: writeW(addrAbs(), x, width: xw)
        case 0x86: writeW(addrZP(), x, width: xw)
        case 0x96: writeW(addrZPY(), x, width: xw)
        case 0x8C: writeW(addrAbs(), y, width: xw)
        case 0x84: writeW(addrZP(), y, width: xw)
        case 0x94: writeW(addrZPX(), y, width: xw)
        case 0x9C: writeW(addrAbs(), 0, width: aw)
        case 0x64: writeW(addrZP(), 0, width: aw)
        case 0x74: writeW(addrZPX(), 0, width: aw)
        case 0x9E: writeW(addrAbsX(), 0, width: aw)

        // MARK: ADC
        case 0x69: opADC(fetchImm(aw), width: aw)
        case 0x65: opADC(readW(addrZP(), width: aw), width: aw)
        case 0x75: opADC(readW(addrZPX(), width: aw), width: aw)
        case 0x72: opADC(readW(addrIZP(), width: aw), width: aw)
        case 0x61: opADC(readW(addrIZPX(), width: aw), width: aw)
        case 0x71: opADC(readW(addrIZPY(), width: aw), width: aw)
        case 0x6D: opADC(readW(addrAbs(), width: aw), width: aw)
        case 0x7D: opADC(readW(addrAbsX(), width: aw), width: aw)
        case 0x79: opADC(readW(addrAbsY(), width: aw), width: aw)
        case 0x67: opADC(readW(addrDPLong(), width: aw), width: aw)
        case 0x77: opADC(readW(addrDPLongY(), width: aw), width: aw)
        case 0x6F: opADC(readW(addrLong(), width: aw), width: aw)
        case 0x7F: opADC(readW(addrLongX(), width: aw), width: aw)
        case 0x63: opADC(readW(addrSR(), width: aw), width: aw)
        case 0x73: opADC(readW(addrSRY(), width: aw), width: aw)

        // MARK: SBC
        case 0xE9: opSBC(fetchImm(aw), width: aw)
        case 0xE5: opSBC(readW(addrZP(), width: aw), width: aw)
        case 0xF5: opSBC(readW(addrZPX(), width: aw), width: aw)
        case 0xF2: opSBC(readW(addrIZP(), width: aw), width: aw)
        case 0xE1: opSBC(readW(addrIZPX(), width: aw), width: aw)
        case 0xF1: opSBC(readW(addrIZPY(), width: aw), width: aw)
        case 0xED: opSBC(readW(addrAbs(), width: aw), width: aw)
        case 0xFD: opSBC(readW(addrAbsX(), width: aw), width: aw)
        case 0xF9: opSBC(readW(addrAbsY(), width: aw), width: aw)
        case 0xE7: opSBC(readW(addrDPLong(), width: aw), width: aw)
        case 0xF7: opSBC(readW(addrDPLongY(), width: aw), width: aw)
        case 0xEF: opSBC(readW(addrLong(), width: aw), width: aw)
        case 0xFF: opSBC(readW(addrLongX(), width: aw), width: aw)
        case 0xE3: opSBC(readW(addrSR(), width: aw), width: aw)
        case 0xF3: opSBC(readW(addrSRY(), width: aw), width: aw)

        // MARK: AND
        case 0x29: opAND(fetchImm(aw), width: aw)
        case 0x25: opAND(readW(addrZP(), width: aw), width: aw)
        case 0x35: opAND(readW(addrZPX(), width: aw), width: aw)
        case 0x32: opAND(readW(addrIZP(), width: aw), width: aw)
        case 0x21: opAND(readW(addrIZPX(), width: aw), width: aw)
        case 0x31: opAND(readW(addrIZPY(), width: aw), width: aw)
        case 0x2D: opAND(readW(addrAbs(), width: aw), width: aw)
        case 0x3D: opAND(readW(addrAbsX(), width: aw), width: aw)
        case 0x39: opAND(readW(addrAbsY(), width: aw), width: aw)
        case 0x27: opAND(readW(addrDPLong(), width: aw), width: aw)
        case 0x37: opAND(readW(addrDPLongY(), width: aw), width: aw)
        case 0x2F: opAND(readW(addrLong(), width: aw), width: aw)
        case 0x3F: opAND(readW(addrLongX(), width: aw), width: aw)
        case 0x23: opAND(readW(addrSR(), width: aw), width: aw)
        case 0x33: opAND(readW(addrSRY(), width: aw), width: aw)

        // MARK: ORA
        case 0x09: opORA(fetchImm(aw), width: aw)
        case 0x05: opORA(readW(addrZP(), width: aw), width: aw)
        case 0x15: opORA(readW(addrZPX(), width: aw), width: aw)
        case 0x12: opORA(readW(addrIZP(), width: aw), width: aw)
        case 0x01: opORA(readW(addrIZPX(), width: aw), width: aw)
        case 0x11: opORA(readW(addrIZPY(), width: aw), width: aw)
        case 0x0D: opORA(readW(addrAbs(), width: aw), width: aw)
        case 0x1D: opORA(readW(addrAbsX(), width: aw), width: aw)
        case 0x19: opORA(readW(addrAbsY(), width: aw), width: aw)
        case 0x07: opORA(readW(addrDPLong(), width: aw), width: aw)
        case 0x17: opORA(readW(addrDPLongY(), width: aw), width: aw)
        case 0x0F: opORA(readW(addrLong(), width: aw), width: aw)
        case 0x1F: opORA(readW(addrLongX(), width: aw), width: aw)
        case 0x03: opORA(readW(addrSR(), width: aw), width: aw)
        case 0x13: opORA(readW(addrSRY(), width: aw), width: aw)

        // MARK: EOR
        case 0x49: opEOR(fetchImm(aw), width: aw)
        case 0x45: opEOR(readW(addrZP(), width: aw), width: aw)
        case 0x55: opEOR(readW(addrZPX(), width: aw), width: aw)
        case 0x52: opEOR(readW(addrIZP(), width: aw), width: aw)
        case 0x41: opEOR(readW(addrIZPX(), width: aw), width: aw)
        case 0x51: opEOR(readW(addrIZPY(), width: aw), width: aw)
        case 0x4D: opEOR(readW(addrAbs(), width: aw), width: aw)
        case 0x5D: opEOR(readW(addrAbsX(), width: aw), width: aw)
        case 0x59: opEOR(readW(addrAbsY(), width: aw), width: aw)
        case 0x47: opEOR(readW(addrDPLong(), width: aw), width: aw)
        case 0x57: opEOR(readW(addrDPLongY(), width: aw), width: aw)
        case 0x4F: opEOR(readW(addrLong(), width: aw), width: aw)
        case 0x5F: opEOR(readW(addrLongX(), width: aw), width: aw)
        case 0x43: opEOR(readW(addrSR(), width: aw), width: aw)
        case 0x53: opEOR(readW(addrSRY(), width: aw), width: aw)

        // MARK: CMP / CPX / CPY
        case 0xC9: opCMP(a, fetchImm(aw), width: aw)
        case 0xC5: opCMP(a, readW(addrZP(), width: aw), width: aw)
        case 0xD5: opCMP(a, readW(addrZPX(), width: aw), width: aw)
        case 0xD2: opCMP(a, readW(addrIZP(), width: aw), width: aw)
        case 0xC1: opCMP(a, readW(addrIZPX(), width: aw), width: aw)
        case 0xD1: opCMP(a, readW(addrIZPY(), width: aw), width: aw)
        case 0xCD: opCMP(a, readW(addrAbs(), width: aw), width: aw)
        case 0xDD: opCMP(a, readW(addrAbsX(), width: aw), width: aw)
        case 0xD9: opCMP(a, readW(addrAbsY(), width: aw), width: aw)
        case 0xC7: opCMP(a, readW(addrDPLong(), width: aw), width: aw)
        case 0xD7: opCMP(a, readW(addrDPLongY(), width: aw), width: aw)
        case 0xCF: opCMP(a, readW(addrLong(), width: aw), width: aw)
        case 0xDF: opCMP(a, readW(addrLongX(), width: aw), width: aw)
        case 0xC3: opCMP(a, readW(addrSR(), width: aw), width: aw)
        case 0xD3: opCMP(a, readW(addrSRY(), width: aw), width: aw)
        case 0xE0: opCMP(x, fetchImm(xw), width: xw)
        case 0xE4: opCMP(x, readW(addrZP(), width: xw), width: xw)
        case 0xEC: opCMP(x, readW(addrAbs(), width: xw), width: xw)
        case 0xC0: opCMP(y, fetchImm(xw), width: xw)
        case 0xC4: opCMP(y, readW(addrZP(), width: xw), width: xw)
        case 0xCC: opCMP(y, readW(addrAbs(), width: xw), width: xw)

        // MARK: BIT
        case 0x89: {                       // immediate form touches only Z
            let v = fetchImm(aw)
            fZero = (a & v & (aw == 2 ? 0xFFFF : 0x00FF)) == 0
        }()
        case 0x24: opBIT(readW(addrZP(), width: aw), width: aw)
        case 0x34: opBIT(readW(addrZPX(), width: aw), width: aw)
        case 0x2C: opBIT(readW(addrAbs(), width: aw), width: aw)
        case 0x3C: opBIT(readW(addrAbsX(), width: aw), width: aw)

        // MARK: Shifts / rotates
        case 0x0A: a = fAccum8 ? (a & 0xFF00) | opASL(a, width: 1) : opASL(a, width: 2); setNZ(a, width: aw)
        case 0x4A: a = fAccum8 ? (a & 0xFF00) | opLSR(a, width: 1) : opLSR(a, width: 2); setNZ(a, width: aw)
        case 0x2A: a = fAccum8 ? (a & 0xFF00) | opROL(a, width: 1) : opROL(a, width: 2); setNZ(a, width: aw)
        case 0x6A: a = fAccum8 ? (a & 0xFF00) | opROR(a, width: 1) : opROR(a, width: 2); setNZ(a, width: aw)
        case 0x06: { let addr = addrZP(); writeW(addr, opASL(readW(addr, width: aw), width: aw), width: aw) }()
        case 0x16: { let addr = addrZPX(); writeW(addr, opASL(readW(addr, width: aw), width: aw), width: aw) }()
        case 0x0E: { let addr = addrAbs(); writeW(addr, opASL(readW(addr, width: aw), width: aw), width: aw) }()
        case 0x1E: { let addr = addrAbsX(); writeW(addr, opASL(readW(addr, width: aw), width: aw), width: aw) }()
        case 0x46: { let addr = addrZP(); writeW(addr, opLSR(readW(addr, width: aw), width: aw), width: aw) }()
        case 0x56: { let addr = addrZPX(); writeW(addr, opLSR(readW(addr, width: aw), width: aw), width: aw) }()
        case 0x4E: { let addr = addrAbs(); writeW(addr, opLSR(readW(addr, width: aw), width: aw), width: aw) }()
        case 0x5E: { let addr = addrAbsX(); writeW(addr, opLSR(readW(addr, width: aw), width: aw), width: aw) }()
        case 0x26: { let addr = addrZP(); writeW(addr, opROL(readW(addr, width: aw), width: aw), width: aw) }()
        case 0x36: { let addr = addrZPX(); writeW(addr, opROL(readW(addr, width: aw), width: aw), width: aw) }()
        case 0x2E: { let addr = addrAbs(); writeW(addr, opROL(readW(addr, width: aw), width: aw), width: aw) }()
        case 0x3E: { let addr = addrAbsX(); writeW(addr, opROL(readW(addr, width: aw), width: aw), width: aw) }()
        case 0x66: { let addr = addrZP(); writeW(addr, opROR(readW(addr, width: aw), width: aw), width: aw) }()
        case 0x76: { let addr = addrZPX(); writeW(addr, opROR(readW(addr, width: aw), width: aw), width: aw) }()
        case 0x6E: { let addr = addrAbs(); writeW(addr, opROR(readW(addr, width: aw), width: aw), width: aw) }()
        case 0x7E: { let addr = addrAbsX(); writeW(addr, opROR(readW(addr, width: aw), width: aw), width: aw) }()

        // MARK: INC / DEC
        case 0x1A: a = fAccum8 ? (a & 0xFF00) | ((a &+ 1) & 0xFF) : a &+ 1; setNZ(a, width: aw)
        case 0x3A: a = fAccum8 ? (a & 0xFF00) | ((a &- 1) & 0xFF) : a &- 1; setNZ(a, width: aw)
        case 0xE6: { let addr = addrZP(); writeW(addr, readW(addr, width: aw) &+ 1, width: aw); setNZ(readW(addr, width: aw), width: aw) }()
        case 0xF6: { let addr = addrZPX(); writeW(addr, readW(addr, width: aw) &+ 1, width: aw); setNZ(readW(addr, width: aw), width: aw) }()
        case 0xEE: { let addr = addrAbs(); writeW(addr, readW(addr, width: aw) &+ 1, width: aw); setNZ(readW(addr, width: aw), width: aw) }()
        case 0xFE: { let addr = addrAbsX(); writeW(addr, readW(addr, width: aw) &+ 1, width: aw); setNZ(readW(addr, width: aw), width: aw) }()
        case 0xC6: { let addr = addrZP(); writeW(addr, readW(addr, width: aw) &- 1, width: aw); setNZ(readW(addr, width: aw), width: aw) }()
        case 0xD6: { let addr = addrZPX(); writeW(addr, readW(addr, width: aw) &- 1, width: aw); setNZ(readW(addr, width: aw), width: aw) }()
        case 0xCE: { let addr = addrAbs(); writeW(addr, readW(addr, width: aw) &- 1, width: aw); setNZ(readW(addr, width: aw), width: aw) }()
        case 0xDE: { let addr = addrAbsX(); writeW(addr, readW(addr, width: aw) &- 1, width: aw); setNZ(readW(addr, width: aw), width: aw) }()
        case 0xE8: x = fIndex8 ? (x & 0xFF00) | ((x &+ 1) & 0xFF) : x &+ 1; setNZ(x, width: xw)
        case 0xC8: y = fIndex8 ? (y & 0xFF00) | ((y &+ 1) & 0xFF) : y &+ 1; setNZ(y, width: xw)
        case 0xCA: x = fIndex8 ? (x & 0xFF00) | ((x &- 1) & 0xFF) : x &- 1; setNZ(x, width: xw)
        case 0x88: y = fIndex8 ? (y & 0xFF00) | ((y &- 1) & 0xFF) : y &- 1; setNZ(y, width: xw)

        // MARK: TRB / TSB
        case 0x14: { let addr = addrZP(); let v = readW(addr, width: aw); fZero = (a & v & (aw == 2 ? 0xFFFF : 0xFF)) == 0; writeW(addr, v & ~a, width: aw) }()
        case 0x1C: { let addr = addrAbs(); let v = readW(addr, width: aw); fZero = (a & v & (aw == 2 ? 0xFFFF : 0xFF)) == 0; writeW(addr, v & ~a, width: aw) }()
        case 0x04: { let addr = addrZP(); let v = readW(addr, width: aw); fZero = (a & v & (aw == 2 ? 0xFFFF : 0xFF)) == 0; writeW(addr, v | a, width: aw) }()
        case 0x0C: { let addr = addrAbs(); let v = readW(addr, width: aw); fZero = (a & v & (aw == 2 ? 0xFFFF : 0xFF)) == 0; writeW(addr, v | a, width: aw) }()

        // MARK: Jumps
        case 0x4C: pc = fetch16()
        case 0x6C: pc = UInt16(truncatingIfNeeded: addrAbsInd())
        case 0x7C: pc = UInt16(truncatingIfNeeded: addrAbsIndX())
        case 0xFC: {                       // JSR ($xxxx,X)
            let t = addrAbsIndX()
            push16(pc &- 1)
            pc = UInt16(truncatingIfNeeded: t)
        }()
        case 0x5C: { let t = fetch24(); k = UInt8(truncatingIfNeeded: t >> 16); pc = UInt16(truncatingIfNeeded: t) }()
        case 0xDC: { let t = addrABLLongInd(); k = UInt8(truncatingIfNeeded: t >> 16); pc = UInt16(truncatingIfNeeded: t) }()
        case 0x20: { let t = fetch16(); push16(pc &- 1); pc = t }()
        case 0x22: { let t = fetch24(); push(UInt8(k)); push16(pc &- 1); k = UInt8(truncatingIfNeeded: t >> 16); pc = UInt16(truncatingIfNeeded: t) }()
        case 0x60: pc = pop16() &+ 1
        case 0x6B: pc = pop16() &+ 1; k = pop()
        case 0x40:
            setP(pop())
            if emu { fAccum8 = true; fIndex8 = true }
            pc = pop16()
            if !emu { k = pop() }

        // MARK: Branches
        case 0x80: branch8(true)
        case 0x90: branch8(!fCarry)
        case 0xB0: branch8(fCarry)
        case 0xF0: branch8(fZero)
        case 0xD0: branch8(!fZero)
        case 0x30: branch8(fNegative)
        case 0x10: branch8(!fNegative)
        case 0x50: branch8(!fOverflow)
        case 0x70: branch8(fOverflow)
        case 0x82: { let off = Int16(bitPattern: fetch16()); pc = pc &+ UInt16(bitPattern: off) }()

        // MARK: Flags
        case 0x18: fCarry = false
        case 0x38: fCarry = true
        case 0x58: fIRQDisable = false
        case 0x78: fIRQDisable = true
        case 0xB8: fOverflow = false
        case 0xD8: fDecimal = false
        case 0xF8: fDecimal = true
        case 0xC2:
            let m = fetch8()
            if m & 0x01 != 0 { fCarry = false }
            if m & 0x02 != 0 { fZero = false }
            if m & 0x04 != 0 { fIRQDisable = false }
            if m & 0x08 != 0 { fDecimal = false }
            if !emu {
                if m & 0x10 != 0 { fIndex8 = false }
                if m & 0x20 != 0 { fAccum8 = false }
            }
        case 0xE2:
            let m = fetch8()
            if m & 0x01 != 0 { fCarry = true }
            if m & 0x02 != 0 { fZero = true }
            if m & 0x04 != 0 { fIRQDisable = true }
            if m & 0x08 != 0 { fDecimal = true }
            if !emu {
                if m & 0x10 != 0 { fIndex8 = true }
                if m & 0x20 != 0 { fAccum8 = true }
            }
        case 0xFB: // XCE
            let oldCarry = fCarry
            fCarry = emu
            emu = oldCarry
            if emu {
                fAccum8 = true
                fIndex8 = true
                sp |= 0x0100
            }
        case 0xEB: // XBA
            a = (a << 8) | (a >> 8)
            setNZ(a, width: 1)

        // MARK: Stack
        case 0x48: pushAccum()
        case 0x68: popAccum(); setNZ(a, width: aw)
        case 0x08: push(getP() | (emu ? 0x30 : 0x20))
        case 0x28:
            setP(pop())
            if emu { fAccum8 = true; fIndex8 = true }
        case 0xDA: push(UInt8(truncatingIfNeeded: x))
        case 0x5A: push(UInt8(truncatingIfNeeded: y))
        case 0xFA: setXReg(fIndex8 ? UInt16(pop()) : pop16())
        case 0x7A: setYReg(fIndex8 ? UInt16(pop()) : pop16())
        case 0x8B: push(db)
        case 0x4B: push(k)
        case 0xAB: db = pop(); setNZ(UInt16(db), width: 1)
        case 0x0B: push16(dp)
        case 0x2B: dp = pop16(); setNZ(dp, width: 2)
        case 0xF4: push16(fetch16()) // PEA
        case 0xD4: push16(readDirect16(fetch8())) // PEI
        case 0x62: { let off = Int16(bitPattern: fetch16()); push16(pc &+ UInt16(bitPattern: off)) }() // PER

        // MARK: Transfers
        case 0xAA: setXReg(a)      // TAX
        case 0xA8: setYReg(a)      // TAY
        case 0x8A: setAccum(x)     // TXA
        case 0x98: setAccum(y)     // TYA
        case 0xBA: setXReg(sp)     // TSX
        case 0x9A: sp = x          // TXS
        case 0x9B: setYReg(x)      // TXY
        case 0xBB: setXReg(y)      // TYX
        case 0x5B: dp = a; setNZ(dp, width: 2)
        case 0x7B: a = dp; setNZ(a, width: 2)
        case 0x1B: sp = a
        case 0x3B: a = sp; setNZ(a, width: 2)

        // MARK: Block moves
        case 0x54, 0x44: // MVN / MVP
            let dst = fetch8()
            let src = fetch8()
            let count = fAccum8 ? UInt32(a & 0xFF) + 1 : UInt32(a) + 1
            for _ in 0..<count {
                let v = bus.read((UInt32(src) << 16) | UInt32(x))
                bus.write((UInt32(dst) << 16) | UInt32(y), v)
                if fIndex8 {
                    x = op == 0x54 ? x &+ 1 : x &- 1
                    y = op == 0x54 ? y &+ 1 : y &- 1
                } else {
                    x = op == 0x54 ? x &+ 1 : x &- 1
                    y = op == 0x54 ? y &+ 1 : y &- 1
                }
            }
            a = fAccum8 ? (a & 0xFF00) | 0xFF : 0xFFFF
            db = dst

        // MARK: Interrupts / control
        case 0x00: // BRK
            if emu {
                push16(pc)
                push(getP() | 0x30)
                fIRQDisable = true
                pc = read16(0xFFFE)
            } else {
                enterInterrupt(vector: 0xFFE6)
            }
        case 0x02: // COP
            if emu {
                push16(pc)
                push(getP() | 0x30)
                fIRQDisable = true
                pc = read16(0xFFF4)
            } else {
                enterInterrupt(vector: 0xFFE4)
            }
        case 0xDB: halted = true   // STP
        case 0xCB: waiting = true  // WAI
        case 0x42: break           // WDM (reserved)
        case 0xEA: break           // NOP

        default:
            // Unimplemented opcode: treat as NOP and keep running.
            break
        }
    }

    private func baseCycles(_ op: UInt8) -> Int {
        switch op {
        case 0x18, 0x38, 0x58, 0x78, 0xB8, 0xD8, 0xF8,
             0xAA, 0xA8, 0x8A, 0x98, 0xBA, 0x9A, 0x9B, 0xBB,
             0xCA, 0xE8, 0x88, 0xC8, 0x1A, 0x3A, 0x5A, 0x7A, 0xDA, 0xFA, 0xEA,
             0xEB, 0xFB, 0x5B, 0x7B, 0x1B, 0x3B,
             0x0B, 0x2B, 0x4B, 0x8B, 0x08, 0x28, 0x48, 0x68:
            return 2
        case 0x80, 0x90, 0xB0, 0xF0, 0x30, 0xD0, 0x10, 0x50, 0x70:
            return 3
        case 0x4C: return 3
        case 0x6C: return 5
        case 0x7C, 0xDC: return 6
        case 0x5C, 0x82: return 4
        case 0x20: return 6
        case 0x22, 0xFC: return 8
        case 0x60: return 6
        case 0x6B: return 7
        case 0x40: return 7
        case 0x00, 0x02: return 8
        case 0xDB, 0xCB, 0x42: return 3
        case 0x54, 0x44: return 6
        case 0x62, 0xF4, 0xD4: return 5
        case 0xC2, 0xE2: return 3
        default: return 4
        }
    }
}


// MARK: - Snapshot

extension CPU65816 {

    /// Everything a save state needs to put the CPU back exactly where it was.
    struct Snapshot: Codable {
        var a: UInt16
        var x: UInt16
        var y: UInt16
        var sp: UInt16
        var dp: UInt16
        var db: UInt8
        var k: UInt8
        var pc: UInt16
        var emu: Bool
        var carry: Bool
        var zero: Bool
        var irqDisable: Bool
        var decimal: Bool
        var index8: Bool
        var accum8: Bool
        var overflow: Bool
        var negative: Bool
        var halted: Bool
        var waiting: Bool
        var nmiPending: Bool
        var irqPending: Bool
    }

    func snapshot() -> Snapshot {
        return Snapshot(
            a: a, x: x, y: y, sp: sp, dp: dp, db: db, k: k, pc: pc,
            emu: emu,
            carry: fCarry, zero: fZero, irqDisable: fIRQDisable,
            decimal: fDecimal, index8: fIndex8, accum8: fAccum8,
            overflow: fOverflow, negative: fNegative,
            halted: halted, waiting: waiting, nmiPending: nmiPending,
            irqPending: irqPending
        )
    }

    func restore(_ s: Snapshot) {
        a = s.a
        x = s.x
        y = s.y
        sp = s.sp
        dp = s.dp
        db = s.db
        k = s.k
        pc = s.pc
        emu = s.emu
        fCarry = s.carry
        fZero = s.zero
        fIRQDisable = s.irqDisable
        fDecimal = s.decimal
        fIndex8 = s.index8
        fAccum8 = s.accum8
        fOverflow = s.overflow
        fNegative = s.negative
        halted = s.halted
        waiting = s.waiting
        nmiPending = s.nmiPending
        irqPending = s.irqPending
    }
}
