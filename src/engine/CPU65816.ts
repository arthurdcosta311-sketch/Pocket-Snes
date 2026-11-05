import type { Bus } from './Bus.ts';

export class CPU65816 {
  bus: Bus;

  // Registers
  a: number = 0; // 16-bit Accumulator
  x: number = 0; // 16-bit X
  y: number = 0; // 16-bit Y
  sp: number = 0x01ff; // Stack pointer
  dp: number = 0; // Direct page
  db: number = 0; // Data bank
  k: number = 0; // Program bank
  pc: number = 0; // Program counter
  emu: boolean = true; // Emulation mode (E)

  // Status flags
  fCarry: boolean = false;
  fZero: boolean = false;
  fIRQDisable: boolean = true;
  fDecimal: boolean = false;
  fIndex8: boolean = true;
  fAccum8: boolean = true;
  fOverflow: boolean = false;
  fNegative: boolean = false;

  halted: boolean = false;
  waiting: boolean = false;
  cycleDebt: number = 0;

  nmiPending: boolean = false;
  irqPending: boolean = false;

  constructor(bus: Bus) {
    this.bus = bus;
    this.reset();
  }

  reset() {
    this.emu = true;
    this.fAccum8 = true;
    this.fIndex8 = true;
    this.fIRQDisable = true;
    this.fDecimal = false;
    this.sp = 0x01ff;
    this.k = 0;
    this.pc = this.read16(0xfffc);
    this.db = 0;
    this.dp = 0;
    this.halted = false;
    this.waiting = false;
    this.nmiPending = false;
    this.irqPending = false;
  }

  get aw(): number {
    return this.fAccum8 ? 1 : 2;
  }
  get xw(): number {
    return this.fIndex8 ? 1 : 2;
  }

  get pb(): number { return this.k; }
  set pb(v: number) { this.k = v; }

  get emulationMode(): boolean { return this.emu; }
  set emulationMode(v: boolean) { this.emu = v; }

  get mf(): boolean { return this.fAccum8; }
  set mf(v: boolean) { this.fAccum8 = v; }

  get xf(): boolean { return this.fIndex8; }
  set xf(v: boolean) { this.fIndex8 = v; }

  get waitingForInterrupt(): boolean { return this.waiting; }
  set waitingForInterrupt(v: boolean) { this.waiting = v; }

  get stopped(): boolean { return this.halted; }
  set stopped(v: boolean) { this.halted = v; }

  fetch8(): number {
    const v = this.bus.read((this.k << 16) | this.pc);
    this.pc = (this.pc + 1) & 0xffff;
    return v;
  }

  fetch16(): number {
    return this.fetch8() | (this.fetch8() << 8);
  }

  fetch24(): number {
    return this.fetch16() | (this.fetch8() << 16);
  }

  fetchImm(width: number): number {
    return width === 2 ? this.fetch16() : this.fetch8();
  }

  read16(addr: number): number {
    return this.bus.read(addr) | (this.bus.read((addr + 1) & 0xffffff) << 8);
  }

  readW(addr: number, width: number): number {
    return width === 2
      ? this.bus.read(addr) | (this.bus.read((addr + 1) & 0xffffff) << 8)
      : this.bus.read(addr);
  }

  writeW(addr: number, v: number, width: number) {
    if (width === 2) {
      this.bus.write(addr, v & 0xff);
      this.bus.write((addr + 1) & 0xffffff, (v >> 8) & 0xff);
    } else {
      this.bus.write(addr, v & 0xff);
    }
  }

  push(v: number) {
    this.bus.write(this.sp, v & 0xff);
    this.sp = (this.sp - 1) & 0xffff;
    if (this.emu && this.sp < 0x0100) this.sp |= 0x0100;
  }

  pop(): number {
    this.sp = (this.sp + 1) & 0xffff;
    if (this.emu && this.sp > 0x01ff) this.sp = 0x0100;
    return this.bus.read(this.sp);
  }

  push16(v: number) {
    this.push((v >> 8) & 0xff);
    this.push(v & 0xff);
  }

  pop16(): number {
    const lo = this.pop();
    return (this.pop() << 8) | lo;
  }

  pushAccum() {
    if (this.fAccum8) {
      this.push(this.a & 0xff);
    } else {
      this.push((this.a >> 8) & 0xff);
      this.push(this.a & 0xff);
    }
  }

  popAccum() {
    if (this.fAccum8) {
      this.a = (this.a & 0xff00) | this.pop();
    } else {
      const lo = this.pop();
      const hi = this.pop();
      this.a = (hi << 8) | lo;
    }
  }

  getP(): number {
    let p = 0;
    if (this.fCarry) p |= 0x01;
    if (this.fZero) p |= 0x02;
    if (this.fIRQDisable) p |= 0x04;
    if (this.fDecimal) p |= 0x08;
    if (this.fIndex8) p |= 0x10;
    if (this.fAccum8) p |= 0x20;
    if (this.fOverflow) p |= 0x40;
    if (this.fNegative) p |= 0x80;
    return p;
  }

  setP(v: number) {
    this.fCarry = (v & 0x01) !== 0;
    this.fZero = (v & 0x02) !== 0;
    this.fIRQDisable = (v & 0x04) !== 0;
    this.fDecimal = (v & 0x08) !== 0;
    this.fIndex8 = (v & 0x10) !== 0;
    this.fAccum8 = (v & 0x20) !== 0;
    this.fOverflow = (v & 0x40) !== 0;
    this.fNegative = (v & 0x80) !== 0;
  }

  setNZ(v: number, width: number) {
    if (width === 2) {
      const w = v & 0xffff;
      this.fZero = w === 0;
      this.fNegative = (w & 0x8000) !== 0;
    } else {
      const b = v & 0xff;
      this.fZero = b === 0;
      this.fNegative = (b & 0x80) !== 0;
    }
  }

  setAccum(value: number) {
    this.a = this.fAccum8 ? (this.a & 0xff00) | (value & 0xff) : value & 0xffff;
    this.setNZ(this.a, this.aw);
  }

  setXReg(value: number) {
    this.x = this.fIndex8 ? value & 0xff : value & 0xffff;
    this.setNZ(this.x, this.xw);
  }

  setYReg(value: number) {
    this.y = this.fIndex8 ? value & 0xff : value & 0xffff;
    this.setNZ(this.y, this.xw);
  }

  // Addressing modes
  dataAddr(offset: number): number {
    return ((this.db << 16) | (offset & 0xffff)) >>> 0;
  }

  direct(offset: number): number {
    return (this.dp + offset) & 0xffff;
  }

  readDirect16(offset: number): number {
    const p = this.direct(offset);
    return this.bus.read(p) | (this.bus.read((p + 1) & 0xffff) << 8);
  }

  addrZP(): number {
    return this.direct(this.fetch8());
  }
  addrZPX(): number {
    return this.direct((this.fetch8() + (this.x & 0xff)) & 0xff);
  }
  addrZPY(): number {
    return this.direct((this.fetch8() + (this.y & 0xff)) & 0xff);
  }
  addrAbs(): number {
    return this.dataAddr(this.fetch16());
  }

  indexX(): number {
    return this.fIndex8 ? this.x & 0xff : this.x;
  }
  indexY(): number {
    return this.fIndex8 ? this.y & 0xff : this.y;
  }

  addrAbsX(): number {
    return this.dataAddr(this.fetch16() + this.indexX());
  }
  addrAbsY(): number {
    return this.dataAddr(this.fetch16() + this.indexY());
  }

  addrIZP(): number {
    return this.dataAddr(this.readDirect16(this.fetch8()));
  }
  addrIZPY(): number {
    return this.dataAddr(this.readDirect16(this.fetch8()) + this.indexY());
  }
  addrIZPX(): number {
    const p = this.direct((this.fetch8() + (this.x & 0xff)) & 0xff);
    return this.dataAddr(this.bus.read(p) | (this.bus.read((p + 1) & 0xffff) << 8));
  }

  addrAbsInd(): number {
    const p = this.fetch16();
    const lo = this.bus.read(p);
    const hi = this.bus.read((p + 1) & 0xffff);
    return this.dataAddr(lo | (hi << 8));
  }

  addrAbsIndX(): number {
    const p = ((this.k << 16) | ((this.fetch16() + this.indexX()) & 0xffff)) >>> 0;
    const lo = this.bus.read(p);
    const hi = this.bus.read((this.k << 16) | (((p & 0xffff) + 1) & 0xffff));
    return ((this.k << 16) | (lo | (hi << 8))) >>> 0;
  }

  addrLong(): number {
    return this.fetch24();
  }
  addrLongX(): number {
    return (this.fetch24() + this.x) & 0xffffff;
  }

  addrDPLong(): number {
    const p = this.direct(this.fetch8());
    let v = this.bus.read(p);
    v |= this.bus.read((p + 1) & 0xffff) << 8;
    v |= this.bus.read((p + 2) & 0xffff) << 16;
    return v >>> 0;
  }

  addrDPLongY(): number {
    return (this.addrDPLong() + this.y) & 0xffffff;
  }

  addrABLLongInd(): number {
    const p = this.fetch16();
    let v = this.bus.read(p);
    v |= this.bus.read((p + 1) & 0xffff) << 8;
    v |= this.bus.read((p + 2) & 0xffff) << 16;
    return v >>> 0;
  }

  addrSR(): number {
    const o = this.fetch8();
    return (this.sp + 1 + o) & 0xffff;
  }

  addrSRY(): number {
    const o = this.fetch8();
    const ptr = (this.sp + 1 + o) & 0xffff;
    const lo = this.bus.read(ptr);
    const hi = this.bus.read((ptr + 1) & 0xffff);
    const targetOff = ((lo | (hi << 8)) + this.indexY()) & 0xffff;
    return this.dataAddr(targetOff);
  }

  branch8(condition: boolean) {
    const offset = (this.fetch8() << 24) >> 24; // signed 8-bit
    if (condition) {
      this.cycleDebt += 2;
      this.pc = (this.pc + offset) & 0xffff;
    }
  }

  // Arithmetic & logic
  opADC(operand: number, width: number) {
    if (width === 2) {
      const r = this.a + operand + (this.fCarry ? 1 : 0);
      this.fOverflow = (~(this.a ^ operand) & (this.a ^ r) & 0x8000) !== 0;
      this.fCarry = r > 0xffff;
      this.a = r & 0xffff;
      this.setNZ(this.a, 2);
    } else {
      const op = operand & 0xff;
      if (this.fDecimal) {
        let al = (this.a & 0x0f) + (op & 0x0f) + (this.fCarry ? 1 : 0);
        if (al > 9) al += 6;
        let ah = ((this.a >> 4) & 0x0f) + ((op >> 4) & 0x0f) + (al > 0x0f ? 1 : 0);
        this.fZero = ((this.a + op + (this.fCarry ? 1 : 0)) & 0xff) === 0;
        this.fNegative = (ah & 0x08) !== 0;
        this.fOverflow = (~(this.a ^ op) & (this.a ^ (ah << 4)) & 0x80) !== 0;
        if (ah > 9) ah += 6;
        this.fCarry = ah > 0x0f;
        this.a = (this.a & 0xff00) | ((ah & 0x0f) << 4) | (al & 0x0f);
      } else {
        const r = (this.a & 0xff) + op + (this.fCarry ? 1 : 0);
        this.fOverflow = (~(this.a ^ op) & (this.a ^ r) & 0x80) !== 0;
        this.fCarry = r > 0xff;
        this.a = (this.a & 0xff00) | (r & 0xff);
        this.setNZ(this.a, 1);
      }
    }
  }

  opSBC(operand: number, width: number) {
    if (this.fDecimal && width === 1) {
      const op = operand & 0xff;
      const borrow = this.fCarry ? 0 : 1;
      let al = (this.a & 0x0f) - (op & 0x0f) - borrow;
      let ah = ((this.a >> 4) & 0x0f) - ((op >> 4) & 0x0f);
      this.fOverflow = (~(this.a ^ op) & (this.a ^ (this.a - op - borrow)) & 0x80) !== 0;
      this.fNegative = (ah & 0x08) !== 0;
      this.fZero = ((this.a - op - borrow) & 0xff) === 0;
      if (al < 0) {
        al -= 6;
        ah -= 1;
      }
      if (ah < 0) ah -= 6;
      this.fCarry = this.a - op - borrow >= 0;
      this.a = (this.a & 0xff00) | ((ah & 0x0f) << 4) | (al & 0x0f);
      return;
    }
    if (width === 2) {
      this.opADC((~operand) & 0xffff, 2);
    } else {
      this.opADC((~operand) & 0xff, 1);
    }
  }

  opAND(operand: number, width: number) {
    this.a = width === 2 ? (this.a & operand) & 0xffff : (this.a & 0xff00) | (this.a & operand & 0xff);
    this.setNZ(this.a, width);
  }

  opORA(operand: number, width: number) {
    this.a = width === 2 ? (this.a | operand) & 0xffff : (this.a & 0xff00) | ((this.a | operand) & 0xff);
    this.setNZ(this.a, width);
  }

  opEOR(operand: number, width: number) {
    this.a = width === 2 ? (this.a ^ operand) & 0xffff : (this.a & 0xff00) | ((this.a ^ operand) & 0xff);
    this.setNZ(this.a, width);
  }

  opCMP(reg: number, operand: number, width: number) {
    const mask = width === 2 ? 0xffff : 0x00ff;
    const r = (reg & mask) - (operand & mask);
    this.fCarry = r >= 0;
    this.setNZ(r & mask, width);
  }

  opBIT(v: number, width: number) {
    const mask = width === 2 ? 0xffff : 0xff;
    this.fZero = (this.a & v & mask) === 0;
    this.fNegative = (v & (width === 2 ? 0x8000 : 0x80)) !== 0;
    this.fOverflow = (v & (width === 2 ? 0x4000 : 0x40)) !== 0;
  }

  opASL(v: number, width: number): number {
    this.fCarry = (v & (width === 2 ? 0x8000 : 0x80)) !== 0;
    const r = (v << 1) & (width === 2 ? 0xffff : 0xff);
    this.setNZ(r, width);
    return r;
  }

  opLSR(v: number, width: number): number {
    this.fCarry = (v & 1) !== 0;
    const r = v >>> 1;
    this.setNZ(r, width);
    return r;
  }

  opROL(v: number, width: number): number {
    const cin = this.fCarry ? 1 : 0;
    this.fCarry = (v & (width === 2 ? 0x8000 : 0x80)) !== 0;
    const r = ((v << 1) | cin) & (width === 2 ? 0xffff : 0xff);
    this.setNZ(r, width);
    return r;
  }

  opROR(v: number, width: number): number {
    const cin = this.fCarry ? 1 : 0;
    this.fCarry = (v & 1) !== 0;
    const r = (v >>> 1) | (cin << (width === 2 ? 15 : 7));
    this.setNZ(r, width);
    return r;
  }

  // Interrupts
  enterInterrupt(vector: number) {
    if (this.emu) {
      this.push16(this.pc);
      this.push(this.getP() | 0x30);
    } else {
      this.push(this.k & 0xff);
      this.push16(this.pc);
      this.push(this.getP());
      this.k = 0;
    }
    this.fIRQDisable = true;
    this.pc = this.read16(vector);
  }

  performNMI() {
    this.nmiPending = false;
    this.waiting = false;
    this.enterInterrupt(this.emu ? 0xfffa : 0xffea);
  }

  performIRQ() {
    this.irqPending = false;
    this.waiting = false;
    this.enterInterrupt(this.emu ? 0xfffe : 0xffee);
  }

  step(): number {
    if (this.waiting) {
      if (this.nmiPending || (this.irqPending && !this.fIRQDisable)) {
        this.waiting = false;
      } else {
        this.cycleDebt = 4;
        return this.cycleDebt;
      }
    }
    if (this.nmiPending) {
      this.performNMI();
      this.cycleDebt = 8;
      return this.cycleDebt;
    }
    if (this.irqPending && !this.fIRQDisable) {
      this.performIRQ();
      this.cycleDebt = 8;
      return this.cycleDebt;
    }
    this.cycleDebt = 0;
    const opcode = this.fetch8();
    this.execute(opcode);
    this.cycleDebt += this.baseCycles(opcode);
    return this.cycleDebt;
  }

  execute(op: number) {
    const aw = this.aw;
    const xw = this.xw;

    switch (op) {
      // LDA
      case 0xa9: this.setAccum(this.fetchImm(aw)); break;
      case 0xa5: this.setAccum(this.readW(this.addrZP(), aw)); break;
      case 0xb5: this.setAccum(this.readW(this.addrZPX(), aw)); break;
      case 0xb2: this.setAccum(this.readW(this.addrIZP(), aw)); break;
      case 0xa1: this.setAccum(this.readW(this.addrIZPX(), aw)); break;
      case 0xb1: this.setAccum(this.readW(this.addrIZPY(), aw)); break;
      case 0xad: this.setAccum(this.readW(this.addrAbs(), aw)); break;
      case 0xbd: this.setAccum(this.readW(this.addrAbsX(), aw)); break;
      case 0xb9: this.setAccum(this.readW(this.addrAbsY(), aw)); break;
      case 0xa7: this.setAccum(this.readW(this.addrDPLong(), aw)); break;
      case 0xb7: this.setAccum(this.readW(this.addrDPLongY(), aw)); break;
      case 0xaf: this.setAccum(this.readW(this.addrLong(), aw)); break;
      case 0xbf: this.setAccum(this.readW(this.addrLongX(), aw)); break;
      case 0xa3: this.setAccum(this.readW(this.addrSR(), aw)); break;
      case 0xb3: this.setAccum(this.readW(this.addrSRY(), aw)); break;

      // LDX / LDY
      case 0xa2: this.setXReg(this.fetchImm(xw)); break;
      case 0xa6: this.setXReg(this.readW(this.addrZP(), xw)); break;
      case 0xb6: this.setXReg(this.readW(this.addrZPY(), xw)); break;
      case 0xae: this.setXReg(this.readW(this.addrAbs(), xw)); break;
      case 0xbe: this.setXReg(this.readW(this.addrAbsY(), xw)); break;
      case 0xa0: this.setYReg(this.fetchImm(xw)); break;
      case 0xa4: this.setYReg(this.readW(this.addrZP(), xw)); break;
      case 0xb4: this.setYReg(this.readW(this.addrZPX(), xw)); break;
      case 0xac: this.setYReg(this.readW(this.addrAbs(), xw)); break;
      case 0xbc: this.setYReg(this.readW(this.addrAbsX(), xw)); break;

      // STA
      case 0x8d: this.writeW(this.addrAbs(), this.a, aw); break;
      case 0x8f: this.writeW(this.addrLong(), this.a, aw); break;
      case 0x85: this.writeW(this.addrZP(), this.a, aw); break;
      case 0x95: this.writeW(this.addrZPX(), this.a, aw); break;
      case 0x92: this.writeW(this.addrIZP(), this.a, aw); break;
      case 0x81: this.writeW(this.addrIZPX(), this.a, aw); break;
      case 0x91: this.writeW(this.addrIZPY(), this.a, aw); break;
      case 0x87: this.writeW(this.addrDPLong(), this.a, aw); break;
      case 0x97: this.writeW(this.addrDPLongY(), this.a, aw); break;
      case 0x9d: this.writeW(this.addrAbsX(), this.a, aw); break;
      case 0x99: this.writeW(this.addrAbsY(), this.a, aw); break;
      case 0x9f: this.writeW(this.addrLongX(), this.a, aw); break;
      case 0x83: this.writeW(this.addrSR(), this.a, aw); break;
      case 0x93: this.writeW(this.addrSRY(), this.a, aw); break;

      // STX / STY / STZ
      case 0x8e: this.writeW(this.addrAbs(), this.x, xw); break;
      case 0x86: this.writeW(this.addrZP(), this.x, xw); break;
      case 0x96: this.writeW(this.addrZPY(), this.x, xw); break;
      case 0x8c: this.writeW(this.addrAbs(), this.y, xw); break;
      case 0x84: this.writeW(this.addrZP(), this.y, xw); break;
      case 0x94: this.writeW(this.addrZPX(), this.y, xw); break;
      case 0x9c: this.writeW(this.addrAbs(), 0, aw); break;
      case 0x64: this.writeW(this.addrZP(), 0, aw); break;
      case 0x74: this.writeW(this.addrZPX(), 0, aw); break;
      case 0x9e: this.writeW(this.addrAbsX(), 0, aw); break;

      // ADC
      case 0x69: this.opADC(this.fetchImm(aw), aw); break;
      case 0x65: this.opADC(this.readW(this.addrZP(), aw), aw); break;
      case 0x75: this.opADC(this.readW(this.addrZPX(), aw), aw); break;
      case 0x72: this.opADC(this.readW(this.addrIZP(), aw), aw); break;
      case 0x61: this.opADC(this.readW(this.addrIZPX(), aw), aw); break;
      case 0x71: this.opADC(this.readW(this.addrIZPY(), aw), aw); break;
      case 0x6d: this.opADC(this.readW(this.addrAbs(), aw), aw); break;
      case 0x7d: this.opADC(this.readW(this.addrAbsX(), aw), aw); break;
      case 0x79: this.opADC(this.readW(this.addrAbsY(), aw), aw); break;
      case 0x67: this.opADC(this.readW(this.addrDPLong(), aw), aw); break;
      case 0x77: this.opADC(this.readW(this.addrDPLongY(), aw), aw); break;
      case 0x6f: this.opADC(this.readW(this.addrLong(), aw), aw); break;
      case 0x7f: this.opADC(this.readW(this.addrLongX(), aw), aw); break;
      case 0x63: this.opADC(this.readW(this.addrSR(), aw), aw); break;
      case 0x73: this.opADC(this.readW(this.addrSRY(), aw), aw); break;

      // SBC
      case 0xe9: this.opSBC(this.fetchImm(aw), aw); break;
      case 0xe5: this.opSBC(this.readW(this.addrZP(), aw), aw); break;
      case 0xf5: this.opSBC(this.readW(this.addrZPX(), aw), aw); break;
      case 0xf2: this.opSBC(this.readW(this.addrIZP(), aw), aw); break;
      case 0xe1: this.opSBC(this.readW(this.addrIZPX(), aw), aw); break;
      case 0xf1: this.opSBC(this.readW(this.addrIZPY(), aw), aw); break;
      case 0xed: this.opSBC(this.readW(this.addrAbs(), aw), aw); break;
      case 0xfd: this.opSBC(this.readW(this.addrAbsX(), aw), aw); break;
      case 0xf9: this.opSBC(this.readW(this.addrAbsY(), aw), aw); break;
      case 0xe7: this.opSBC(this.readW(this.addrDPLong(), aw), aw); break;
      case 0xf7: this.opSBC(this.readW(this.addrDPLongY(), aw), aw); break;
      case 0xef: this.opSBC(this.readW(this.addrLong(), aw), aw); break;
      case 0xff: this.opSBC(this.readW(this.addrLongX(), aw), aw); break;
      case 0xe3: this.opSBC(this.readW(this.addrSR(), aw), aw); break;
      case 0xf3: this.opSBC(this.readW(this.addrSRY(), aw), aw); break;

      // AND
      case 0x29: this.opAND(this.fetchImm(aw), aw); break;
      case 0x25: this.opAND(this.readW(this.addrZP(), aw), aw); break;
      case 0x35: this.opAND(this.readW(this.addrZPX(), aw), aw); break;
      case 0x32: this.opAND(this.readW(this.addrIZP(), aw), aw); break;
      case 0x21: this.opAND(this.readW(this.addrIZPX(), aw), aw); break;
      case 0x31: this.opAND(this.readW(this.addrIZPY(), aw), aw); break;
      case 0x2d: this.opAND(this.readW(this.addrAbs(), aw), aw); break;
      case 0x3d: this.opAND(this.readW(this.addrAbsX(), aw), aw); break;
      case 0x39: this.opAND(this.readW(this.addrAbsY(), aw), aw); break;
      case 0x27: this.opAND(this.readW(this.addrDPLong(), aw), aw); break;
      case 0x37: this.opAND(this.readW(this.addrDPLongY(), aw), aw); break;
      case 0x2f: this.opAND(this.readW(this.addrLong(), aw), aw); break;
      case 0x3f: this.opAND(this.readW(this.addrLongX(), aw), aw); break;
      case 0x23: this.opAND(this.readW(this.addrSR(), aw), aw); break;
      case 0x33: this.opAND(this.readW(this.addrSRY(), aw), aw); break;

      // ORA
      case 0x09: this.opORA(this.fetchImm(aw), aw); break;
      case 0x05: this.opORA(this.readW(this.addrZP(), aw), aw); break;
      case 0x15: this.opORA(this.readW(this.addrZPX(), aw), aw); break;
      case 0x12: this.opORA(this.readW(this.addrIZP(), aw), aw); break;
      case 0x01: this.opORA(this.readW(this.addrIZPX(), aw), aw); break;
      case 0x11: this.opORA(this.readW(this.addrIZPY(), aw), aw); break;
      case 0x0d: this.opORA(this.readW(this.addrAbs(), aw), aw); break;
      case 0x1d: this.opORA(this.readW(this.addrAbsX(), aw), aw); break;
      case 0x19: this.opORA(this.readW(this.addrAbsY(), aw), aw); break;
      case 0x07: this.opORA(this.readW(this.addrDPLong(), aw), aw); break;
      case 0x17: this.opORA(this.readW(this.addrDPLongY(), aw), aw); break;
      case 0x0f: this.opORA(this.readW(this.addrLong(), aw), aw); break;
      case 0x1f: this.opORA(this.readW(this.addrLongX(), aw), aw); break;
      case 0x03: this.opORA(this.readW(this.addrSR(), aw), aw); break;
      case 0x13: this.opORA(this.readW(this.addrSRY(), aw), aw); break;

      // EOR
      case 0x49: this.opEOR(this.fetchImm(aw), aw); break;
      case 0x45: this.opEOR(this.readW(this.addrZP(), aw), aw); break;
      case 0x55: this.opEOR(this.readW(this.addrZPX(), aw), aw); break;
      case 0x52: this.opEOR(this.readW(this.addrIZP(), aw), aw); break;
      case 0x41: this.opEOR(this.readW(this.addrIZPX(), aw), aw); break;
      case 0x51: this.opEOR(this.readW(this.addrIZPY(), aw), aw); break;
      case 0x4d: this.opEOR(this.readW(this.addrAbs(), aw), aw); break;
      case 0x5d: this.opEOR(this.readW(this.addrAbsX(), aw), aw); break;
      case 0x59: this.opEOR(this.readW(this.addrAbsY(), aw), aw); break;
      case 0x47: this.opEOR(this.readW(this.addrDPLong(), aw), aw); break;
      case 0x57: this.opEOR(this.readW(this.addrDPLongY(), aw), aw); break;
      case 0x4f: this.opEOR(this.readW(this.addrLong(), aw), aw); break;
      case 0x5f: this.opEOR(this.readW(this.addrLongX(), aw), aw); break;
      case 0x43: this.opEOR(this.readW(this.addrSR(), aw), aw); break;
      case 0x53: this.opEOR(this.readW(this.addrSRY(), aw), aw); break;

      // CMP / CPX / CPY
      case 0xc9: this.opCMP(this.a, this.fetchImm(aw), aw); break;
      case 0xc5: this.opCMP(this.a, this.readW(this.addrZP(), aw), aw); break;
      case 0xd5: this.opCMP(this.a, this.readW(this.addrZPX(), aw), aw); break;
      case 0xd2: this.opCMP(this.a, this.readW(this.addrIZP(), aw), aw); break;
      case 0xc1: this.opCMP(this.a, this.readW(this.addrIZPX(), aw), aw); break;
      case 0xd1: this.opCMP(this.a, this.readW(this.addrIZPY(), aw), aw); break;
      case 0xcd: this.opCMP(this.a, this.readW(this.addrAbs(), aw), aw); break;
      case 0xdd: this.opCMP(this.a, this.readW(this.addrAbsX(), aw), aw); break;
      case 0xd9: this.opCMP(this.a, this.readW(this.addrAbsY(), aw), aw); break;
      case 0xc7: this.opCMP(this.a, this.readW(this.addrDPLong(), aw), aw); break;
      case 0xd7: this.opCMP(this.a, this.readW(this.addrDPLongY(), aw), aw); break;
      case 0xcf: this.opCMP(this.a, this.readW(this.addrLong(), aw), aw); break;
      case 0xdf: this.opCMP(this.a, this.readW(this.addrLongX(), aw), aw); break;
      case 0xc3: this.opCMP(this.a, this.readW(this.addrSR(), aw), aw); break;
      case 0xd3: this.opCMP(this.a, this.readW(this.addrSRY(), aw), aw); break;
      case 0xe0: this.opCMP(this.x, this.fetchImm(xw), xw); break;
      case 0xe4: this.opCMP(this.x, this.readW(this.addrZP(), xw), xw); break;
      case 0xec: this.opCMP(this.x, this.readW(this.addrAbs(), xw), xw); break;
      case 0xc0: this.opCMP(this.y, this.fetchImm(xw), xw); break;
      case 0xc4: this.opCMP(this.y, this.readW(this.addrZP(), xw), xw); break;
      case 0xcc: this.opCMP(this.y, this.readW(this.addrAbs(), xw), xw); break;

      // BIT
      case 0x89: {
        const v = this.fetchImm(aw);
        this.fZero = (this.a & v & (aw === 2 ? 0xffff : 0x00ff)) === 0;
        break;
      }
      case 0x24: this.opBIT(this.readW(this.addrZP(), aw), aw); break;
      case 0x34: this.opBIT(this.readW(this.addrZPX(), aw), aw); break;
      case 0x2c: this.opBIT(this.readW(this.addrAbs(), aw), aw); break;
      case 0x3c: this.opBIT(this.readW(this.addrAbsX(), aw), aw); break;

      // Shifts / rotates
      case 0x0a:
        this.a = this.fAccum8 ? (this.a & 0xff00) | this.opASL(this.a, 1) : this.opASL(this.a, 2);
        this.setNZ(this.a, aw);
        break;
      case 0x4a:
        this.a = this.fAccum8 ? (this.a & 0xff00) | this.opLSR(this.a, 1) : this.opLSR(this.a, 2);
        this.setNZ(this.a, aw);
        break;
      case 0x2a:
        this.a = this.fAccum8 ? (this.a & 0xff00) | this.opROL(this.a, 1) : this.opROL(this.a, 2);
        this.setNZ(this.a, aw);
        break;
      case 0x6a:
        this.a = this.fAccum8 ? (this.a & 0xff00) | this.opROR(this.a, 1) : this.opROR(this.a, 2);
        this.setNZ(this.a, aw);
        break;
      case 0x06: { const a = this.addrZP(); this.writeW(a, this.opASL(this.readW(a, aw), aw), aw); break; }
      case 0x16: { const a = this.addrZPX(); this.writeW(a, this.opASL(this.readW(a, aw), aw), aw); break; }
      case 0x0e: { const a = this.addrAbs(); this.writeW(a, this.opASL(this.readW(a, aw), aw), aw); break; }
      case 0x1e: { const a = this.addrAbsX(); this.writeW(a, this.opASL(this.readW(a, aw), aw), aw); break; }
      case 0x46: { const a = this.addrZP(); this.writeW(a, this.opLSR(this.readW(a, aw), aw), aw); break; }
      case 0x56: { const a = this.addrZPX(); this.writeW(a, this.opLSR(this.readW(a, aw), aw), aw); break; }
      case 0x4e: { const a = this.addrAbs(); this.writeW(a, this.opLSR(this.readW(a, aw), aw), aw); break; }
      case 0x5e: { const a = this.addrAbsX(); this.writeW(a, this.opLSR(this.readW(a, aw), aw), aw); break; }
      case 0x26: { const a = this.addrZP(); this.writeW(a, this.opROL(this.readW(a, aw), aw), aw); break; }
      case 0x36: { const a = this.addrZPX(); this.writeW(a, this.opROL(this.readW(a, aw), aw), aw); break; }
      case 0x2e: { const a = this.addrAbs(); this.writeW(a, this.opROL(this.readW(a, aw), aw), aw); break; }
      case 0x3e: { const a = this.addrAbsX(); this.writeW(a, this.opROL(this.readW(a, aw), aw), aw); break; }
      case 0x66: { const a = this.addrZP(); this.writeW(a, this.opROR(this.readW(a, aw), aw), aw); break; }
      case 0x76: { const a = this.addrZPX(); this.writeW(a, this.opROR(this.readW(a, aw), aw), aw); break; }
      case 0x6e: { const a = this.addrAbs(); this.writeW(a, this.opROR(this.readW(a, aw), aw), aw); break; }
      case 0x7e: { const a = this.addrAbsX(); this.writeW(a, this.opROR(this.readW(a, aw), aw), aw); break; }

      // INC / DEC
      case 0x1a:
        this.a = this.fAccum8 ? (this.a & 0xff00) | ((this.a + 1) & 0xff) : (this.a + 1) & 0xffff;
        this.setNZ(this.a, aw);
        break;
      case 0x3a:
        this.a = this.fAccum8 ? (this.a & 0xff00) | ((this.a - 1) & 0xff) : (this.a - 1) & 0xffff;
        this.setNZ(this.a, aw);
        break;
      case 0xe6: { const a = this.addrZP(); const v = (this.readW(a, aw) + 1) & (aw === 2 ? 0xffff : 0xff); this.writeW(a, v, aw); this.setNZ(v, aw); break; }
      case 0xf6: { const a = this.addrZPX(); const v = (this.readW(a, aw) + 1) & (aw === 2 ? 0xffff : 0xff); this.writeW(a, v, aw); this.setNZ(v, aw); break; }
      case 0xee: { const a = this.addrAbs(); const v = (this.readW(a, aw) + 1) & (aw === 2 ? 0xffff : 0xff); this.writeW(a, v, aw); this.setNZ(v, aw); break; }
      case 0xfe: { const a = this.addrAbsX(); const v = (this.readW(a, aw) + 1) & (aw === 2 ? 0xffff : 0xff); this.writeW(a, v, aw); this.setNZ(v, aw); break; }
      case 0xc6: { const a = this.addrZP(); const v = (this.readW(a, aw) - 1) & (aw === 2 ? 0xffff : 0xff); this.writeW(a, v, aw); this.setNZ(v, aw); break; }
      case 0xd6: { const a = this.addrZPX(); const v = (this.readW(a, aw) - 1) & (aw === 2 ? 0xffff : 0xff); this.writeW(a, v, aw); this.setNZ(v, aw); break; }
      case 0xce: { const a = this.addrAbs(); const v = (this.readW(a, aw) - 1) & (aw === 2 ? 0xffff : 0xff); this.writeW(a, v, aw); this.setNZ(v, aw); break; }
      case 0xde: { const a = this.addrAbsX(); const v = (this.readW(a, aw) - 1) & (aw === 2 ? 0xffff : 0xff); this.writeW(a, v, aw); this.setNZ(v, aw); break; }
      case 0xe8:
        this.x = this.fIndex8 ? (this.x & 0xff00) | ((this.x + 1) & 0xff) : (this.x + 1) & 0xffff;
        this.setNZ(this.x, xw);
        break;
      case 0xc8:
        this.y = this.fIndex8 ? (this.y & 0xff00) | ((this.y + 1) & 0xff) : (this.y + 1) & 0xffff;
        this.setNZ(this.y, xw);
        break;
      case 0xca:
        this.x = this.fIndex8 ? (this.x & 0xff00) | ((this.x - 1) & 0xff) : (this.x - 1) & 0xffff;
        this.setNZ(this.x, xw);
        break;
      case 0x88:
        this.y = this.fIndex8 ? (this.y & 0xff00) | ((this.y - 1) & 0xff) : (this.y - 1) & 0xffff;
        this.setNZ(this.y, xw);
        break;

      // TRB / TSB
      case 0x14: { const a = this.addrZP(); const v = this.readW(a, aw); this.fZero = (this.a & v & (aw === 2 ? 0xffff : 0xff)) === 0; this.writeW(a, v & ~this.a, aw); break; }
      case 0x1c: { const a = this.addrAbs(); const v = this.readW(a, aw); this.fZero = (this.a & v & (aw === 2 ? 0xffff : 0xff)) === 0; this.writeW(a, v & ~this.a, aw); break; }
      case 0x04: { const a = this.addrZP(); const v = this.readW(a, aw); this.fZero = (this.a & v & (aw === 2 ? 0xffff : 0xff)) === 0; this.writeW(a, v | this.a, aw); break; }
      case 0x0c: { const a = this.addrAbs(); const v = this.readW(a, aw); this.fZero = (this.a & v & (aw === 2 ? 0xffff : 0xff)) === 0; this.writeW(a, v | this.a, aw); break; }

      // Jumps
      case 0x4c: this.pc = this.fetch16(); break;
      case 0x6c: this.pc = this.addrAbsInd() & 0xffff; break;
      case 0x7c: this.pc = this.addrAbsIndX() & 0xffff; break;
      case 0xfc: {
        const t = this.addrAbsIndX();
        this.push16((this.pc - 1) & 0xffff);
        this.pc = t & 0xffff;
        break;
      }
      case 0x5c: {
        const t = this.fetch24();
        this.k = (t >> 16) & 0xff;
        this.pc = t & 0xffff;
        break;
      }
      case 0xdc: {
        const t = this.addrABLLongInd();
        this.k = (t >> 16) & 0xff;
        this.pc = t & 0xffff;
        break;
      }
      case 0x20: {
        const t = this.fetch16();
        this.push16((this.pc - 1) & 0xffff);
        this.pc = t;
        break;
      }
      case 0x22: {
        const t = this.fetch24();
        this.push(this.k & 0xff);
        this.push16((this.pc - 1) & 0xffff);
        this.k = (t >> 16) & 0xff;
        this.pc = t & 0xffff;
        break;
      }
      case 0x60: this.pc = (this.pop16() + 1) & 0xffff; break;
      case 0x6b: this.pc = (this.pop16() + 1) & 0xffff; this.k = this.pop(); break;
      case 0x40:
        this.setP(this.pop());
        if (this.emu) {
          this.fAccum8 = true;
          this.fIndex8 = true;
        }
        this.pc = this.pop16();
        if (!this.emu) this.k = this.pop();
        break;

      // Branches
      case 0x80: this.branch8(true); break;
      case 0x90: this.branch8(!this.fCarry); break;
      case 0xb0: this.branch8(this.fCarry); break;
      case 0xf0: this.branch8(this.fZero); break;
      case 0xd0: this.branch8(!this.fZero); break;
      case 0x30: this.branch8(this.fNegative); break;
      case 0x10: this.branch8(!this.fNegative); break;
      case 0x50: this.branch8(!this.fOverflow); break;
      case 0x70: this.branch8(this.fOverflow); break;
      case 0x82: {
        const off = (this.fetch16() << 16) >> 16;
        this.pc = (this.pc + off) & 0xffff;
        break;
      }

      // Flags
      case 0x18: this.fCarry = false; break;
      case 0x38: this.fCarry = true; break;
      case 0x58: this.fIRQDisable = false; break;
      case 0x78: this.fIRQDisable = true; break;
      case 0xb8: this.fOverflow = false; break;
      case 0xd8: this.fDecimal = false; break;
      case 0xf8: this.fDecimal = true; break;
      case 0xc2: {
        const m = this.fetch8();
        if (m & 0x01) this.fCarry = false;
        if (m & 0x02) this.fZero = false;
        if (m & 0x04) this.fIRQDisable = false;
        if (m & 0x08) this.fDecimal = false;
        if (!this.emu) {
          if (m & 0x10) this.fIndex8 = false;
          if (m & 0x20) this.fAccum8 = false;
        }
        break;
      }
      case 0xe2: {
        const m = this.fetch8();
        if (m & 0x01) this.fCarry = true;
        if (m & 0x02) this.fZero = true;
        if (m & 0x04) this.fIRQDisable = true;
        if (m & 0x08) this.fDecimal = true;
        if (!this.emu) {
          if (m & 0x10) this.fIndex8 = true;
          if (m & 0x20) this.fAccum8 = true;
        }
        break;
      }
      case 0xfb: { // XCE
        const oldCarry = this.fCarry;
        this.fCarry = this.emu;
        this.emu = oldCarry;
        if (this.emu) {
          this.fAccum8 = true;
          this.fIndex8 = true;
          this.sp |= 0x0100;
        }
        break;
      }
      case 0xeb: // XBA
        this.a = ((this.a << 8) | (this.a >> 8)) & 0xffff;
        this.setNZ(this.a, 1);
        break;

      // Stack
      case 0x48: this.pushAccum(); break;
      case 0x68: this.popAccum(); this.setNZ(this.a, aw); break;
      case 0x08: this.push(this.getP() | (this.emu ? 0x30 : 0x20)); break;
      case 0x28:
        this.setP(this.pop());
        if (this.emu) {
          this.fAccum8 = true;
          this.fIndex8 = true;
        }
        break;
      case 0xda: this.push(this.x & 0xff); break;
      case 0x5a: this.push(this.y & 0xff); break;
      case 0xfa: this.setXReg(this.fIndex8 ? this.pop() : this.pop16()); break;
      case 0x7a: this.setYReg(this.fIndex8 ? this.pop() : this.pop16()); break;
      case 0x8b: this.push(this.db); break;
      case 0x4b: this.push(this.k); break;
      case 0xab: this.db = this.pop(); this.setNZ(this.db, 1); break;
      case 0x0b: this.push16(this.dp); break;
      case 0x2b: this.dp = this.pop16(); this.setNZ(this.dp, 2); break;
      case 0xf4: this.push16(this.fetch16()); break;
      case 0xd4: this.push16(this.readDirect16(this.fetch8())); break;
      case 0x62: {
        const off = (this.fetch16() << 16) >> 16;
        this.push16((this.pc + off) & 0xffff);
        break;
      }

      // Transfers
      case 0xaa: this.setXReg(this.a); break;
      case 0xa8: this.setYReg(this.a); break;
      case 0x8a: this.setAccum(this.x); break;
      case 0x98: this.setAccum(this.y); break;
      case 0xba: this.setXReg(this.sp); break;
      case 0x9a: this.sp = this.x; break;
      case 0x9b: this.setYReg(this.x); break;
      case 0xbb: this.setXReg(this.y); break;
      case 0x5b: this.dp = this.a; this.setNZ(this.dp, 2); break;
      case 0x7b: this.a = this.dp; this.setNZ(this.a, 2); break;
      case 0x1b: this.sp = this.a; break;
      case 0x3b: this.a = this.sp; this.setNZ(this.a, 2); break;

      // Block moves
      case 0x54:
      case 0x44: {
        const dst = this.fetch8();
        const src = this.fetch8();
        const count = this.fAccum8 ? (this.a & 0xff) + 1 : this.a + 1;
        for (let i = 0; i < count; i++) {
          const v = this.bus.read((src << 16) | this.x);
          this.bus.write((dst << 16) | this.y, v);
          if (op === 0x54) {
            this.x = (this.x + 1) & 0xffff;
            this.y = (this.y + 1) & 0xffff;
          } else {
            this.x = (this.x - 1) & 0xffff;
            this.y = (this.y - 1) & 0xffff;
          }
        }
        this.a = this.fAccum8 ? (this.a & 0xff00) | 0xff : 0xffff;
        this.db = dst;
        break;
      }

      // Control
      case 0x00:
        if (this.emu) {
          this.push16(this.pc);
          this.push(this.getP() | 0x30);
          this.fIRQDisable = true;
          this.pc = this.read16(0xfffe);
        } else {
          this.enterInterrupt(0xffe6);
        }
        break;
      case 0x02:
        if (this.emu) {
          this.push16(this.pc);
          this.push(this.getP() | 0x30);
          this.fIRQDisable = true;
          this.pc = this.read16(0xfff4);
        } else {
          this.enterInterrupt(0xffe4);
        }
        break;
      case 0xdb: this.halted = true; break;
      case 0xcb: this.waiting = true; break;
      case 0x42: break;
      case 0xea: break;
      default: break;
    }
  }

  baseCycles(op: number): number {
    switch (op) {
      case 0x18: case 0x38: case 0x58: case 0x78: case 0xb8: case 0xd8: case 0xf8:
      case 0xaa: case 0xa8: case 0x8a: case 0x98: case 0xba: case 0x9a: case 0x9b: case 0xbb:
      case 0xca: case 0xe8: case 0x88: case 0xc8: case 0x1a: case 0x3a: case 0x5a: case 0x7a:
      case 0xda: case 0xfa: case 0xea: case 0xeb: case 0xfb: case 0x5b: case 0x7b: case 0x1b: case 0x3b:
      case 0x0b: case 0x2b: case 0x4b: case 0x8b: case 0x08: case 0x28: case 0x48: case 0x68:
        return 2;
      case 0x80: case 0x90: case 0xb0: case 0xf0: case 0x30: case 0xd0: case 0x10: case 0x50: case 0x70:
        return 3;
      case 0x4c: return 3;
      case 0x6c: return 5;
      case 0x7c: case 0xdc: return 6;
      case 0x5c: case 0x82: return 4;
      case 0x20: return 6;
      case 0x22: case 0xfc: return 8;
      case 0x60: return 6;
      case 0x6b: return 7;
      case 0x40: return 7;
      case 0x00: case 0x02: return 8;
      case 0xdb: case 0xcb: case 0x42: return 3;
      case 0x54: case 0x44: return 6;
      case 0x62: case 0xf4: case 0xd4: return 5;
      case 0xc2: case 0xe2: return 3;
      default: return 4;
    }
  }

  snapshot() {
    return {
      a: this.a, x: this.x, y: this.y, sp: this.sp, dp: this.dp, db: this.db, k: this.k, pc: this.pc,
      emu: this.emu, carry: this.fCarry, zero: this.fZero, irqDisable: this.fIRQDisable,
      decimal: this.fDecimal, index8: this.fIndex8, accum8: this.fAccum8, overflow: this.fOverflow,
      negative: this.fNegative, halted: this.halted, waiting: this.waiting,
      nmiPending: this.nmiPending, irqPending: this.irqPending
    };
  }

  restore(s: ReturnType<CPU65816['snapshot']>) {
    this.a = s.a; this.x = s.x; this.y = s.y; this.sp = s.sp; this.dp = s.dp; this.db = s.db;
    this.k = s.k; this.pc = s.pc; this.emu = s.emu; this.fCarry = s.carry; this.fZero = s.zero;
    this.fIRQDisable = s.irqDisable; this.fDecimal = s.decimal; this.fIndex8 = s.index8;
    this.fAccum8 = s.accum8; this.fOverflow = s.overflow; this.fNegative = s.negative;
    this.halted = s.halted; this.waiting = s.waiting; this.nmiPending = s.nmiPending;
    this.irqPending = s.irqPending;
  }
}
