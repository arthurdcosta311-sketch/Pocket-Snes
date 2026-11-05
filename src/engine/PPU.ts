export class PPU {
  static readonly width = 256;
  static readonly height = 224;

  vram: Uint8Array = new Uint8Array(0x10000); // 64KB
  oam: Uint8Array = new Uint8Array(0x220); // 544 bytes
  cgram: Uint8Array = new Uint8Array(0x200); // 512 bytes = 256 BGR555 colors

  // Registers
  inidisp: number = 0; // $2100
  obisel: number = 0; // $2101
  bgmode: number = 0; // $2105
  mosaic: number = 0; // $2106
  bgsc: number[] = [0, 0, 0, 0]; // $2107-$210A
  bg12ba: number = 0; // $210B
  bg34ba: number = 0; // $210C
  bgx: number[] = [0, 0, 0, 0];
  bgy: number[] = [0, 0, 0, 0];
  tm: number = 0; // $212C
  ts: number = 0; // $212D
  cgwsel: number = 0; // $212A
  cgadsub: number = 0; // $212B
  fixedColorR: number = 0;
  fixedColorG: number = 0;
  fixedColorB: number = 0;
  m7a: number = 0;
  m7b: number = 0;

  // Internal state
  vramAddr: number = 0;
  vramIncrement: number = 1;
  vramRemapMode: number = 0;
  vramIncOnHigh: boolean = true;
  vramReadBuffer: number = 0;
  cgAddr: number = 0;
  cgLatchHigh: boolean = false;
  cgReadBuffer: number = 0;
  oamAddr: number = 0;
  hCounterLatch: number = 0;
  vCounterLatch: number = 0;
  hCounterLatchHigh: boolean = false;
  vCounterLatchHigh: boolean = false;
  scrollLatch: boolean[] = [true, true, true, true, true, true, true, true];

  scanline: number = 0;
  vblankFlag: boolean = false;

  // RGBA8 256x224 buffer
  frame: Uint8ClampedArray = new Uint8ClampedArray(256 * 224 * 4);

  static readonly spriteSizes: [number, number][] = [
    [8, 16], [8, 32], [8, 64], [16, 32],
    [16, 64], [32, 64], [16, 32], [16, 32]
  ];

  constructor() {
    this.reset();
  }

  reset() {
    this.vram.fill(0);
    this.oam.fill(0);
    this.cgram.fill(0);
    this.inidisp = 0x0f; // Screen on by default
    this.obisel = 0;
    this.bgmode = 0;
    this.mosaic = 0;
    this.bgsc = [0, 0, 0, 0];
    this.bg12ba = 0;
    this.bg34ba = 0;
    this.bgx = [0, 0, 0, 0];
    this.bgy = [0, 0, 0, 0];
    this.tm = 0x1f; // Main screen enable
    this.ts = 0;
    this.vramAddr = 0;
    this.vramIncrement = 1;
    this.vramRemapMode = 0;
    this.vramIncOnHigh = true;
    this.scanline = 0;
    this.vblankFlag = false;
  }

  writeRegister(reg: number, value: number) {
    switch (reg) {
      case 0x00: this.inidisp = value; break;
      case 0x01: this.obisel = value; break;
      case 0x02: this.oamAddr = (this.oamAddr & 0x0200) | ((value << 1) & 0x01fe); break;
      case 0x03: this.oamAddr = (this.oamAddr & 0x01fe) | ((value & 1) << 9); break;
      case 0x04: this.oamWrite(value); break;
      case 0x05: this.bgmode = value; break;
      case 0x06: this.mosaic = value; break;
      case 0x07: this.bgsc[0] = value; break;
      case 0x08: this.bgsc[1] = value; break;
      case 0x09: this.bgsc[2] = value; break;
      case 0x0a: this.bgsc[3] = value; break;
      case 0x0b: this.bg12ba = value; break;
      case 0x0c: this.bg34ba = value; break;
      case 0x0d: case 0x0e: case 0x0f: case 0x10:
      case 0x11: case 0x12: case 0x13: case 0x14:
        this.writeScroll(reg, value);
        break;
      case 0x15:
        this.vramIncrement = [1, 32, 128, 128][value & 3];
        this.vramRemapMode = (value >> 2) & 3;
        this.vramIncOnHigh = (value & 0x80) !== 0;
        break;
      case 0x16: // VMADDL (low)
        this.vramAddr = (this.vramAddr & 0xff00) | value;
        this.vramReadBuffer = this.readVRAMWord(this.vramAddr);
        break;
      case 0x17: // VMADDH (high)
        this.vramAddr = ((value << 8) | (this.vramAddr & 0x00ff)) & 0xffff;
        this.vramReadBuffer = this.readVRAMWord(this.vramAddr);
        break;
      case 0x18: this.vramWriteLo(value); break;
      case 0x19: this.vramWriteHi(value); break;
      case 0x1b: this.m7a = (this.m7a & 0xff00) | value; break;
      case 0x1c: this.m7a = (this.m7a & 0x00ff) | (value << 8); break;
      case 0x1d: this.m7b = value; break;
      case 0x21:
        this.cgAddr = value & 0xff;
        this.cgLatchHigh = false;
        break;
      case 0x22: this.cgWrite(value); break;
      case 0x2c: this.tm = value; break;
      case 0x2d: this.ts = value; break;
      case 0x30: this.cgwsel = value; break;
      case 0x31: this.cggadsub(value); break;
      case 0x32:
        if (value & 0x20) this.fixedColorR = value & 0x1f;
        if (value & 0x40) this.fixedColorG = value & 0x1f;
        if (value & 0x80) this.fixedColorB = value & 0x1f;
        break;
      default: break;
    }
  }

  private cggadsub(value: number) {
    this.cgadsub = value;
  }

  readRegister(reg: number): number {
    switch (reg) {
      case 0x04:
      case 0x38: {
        const v = this.oam[this.oamAddr & 0x03ff];
        this.oamAddr = (this.oamAddr + 1) & 0x03ff;
        return v;
      }
      case 0x34:
      case 0x35:
      case 0x36: {
        const m7aSigned = (this.m7a << 16) >> 16;
        const m7bSigned = (this.m7b << 24) >> 24;
        const product = m7aSigned * m7bSigned;
        const shift = (reg - 0x34) * 8;
        return (product >> shift) & 0xff;
      }
      case 0x37:
        this.hCounterLatch = 0;
        this.vCounterLatch = this.scanline;
        this.hCounterLatchHigh = false;
        this.vCounterLatchHigh = false;
        return 0;
      case 0x39: {
        const v = this.vramReadBuffer & 0xff;
        this.vramReadBuffer = this.readVRAMWord(this.vramAddr);
        if (!this.vramIncOnHigh) this.vramAddr = (this.vramAddr + this.vramIncrement) & 0xffff;
        return v;
      }
      case 0x3a: {
        const hi = (this.vramReadBuffer >> 8) & 0xff;
        this.vramReadBuffer = this.readVRAMWord(this.vramAddr);
        if (this.vramIncOnHigh) this.vramAddr = (this.vramAddr + this.vramIncrement) & 0xffff;
        return hi;
      }
      case 0x3b: {
        const v = this.cgLatchHigh
          ? (this.cgReadBuffer >> 8) & 0xff
          : this.cgReadBuffer & 0xff;
        if (this.cgLatchHigh) this.cgAddr = (this.cgAddr + 1) & 0xff;
        this.cgReadBuffer = this.cgramColor(this.cgAddr);
        this.cgLatchHigh = !this.cgLatchHigh;
        return v;
      }
      case 0x3c: {
        const v = this.hCounterLatchHigh
          ? (this.hCounterLatch >> 8) & 1
          : this.hCounterLatch & 0xff;
        this.hCounterLatchHigh = !this.hCounterLatchHigh;
        return v;
      }
      case 0x3d: {
        const v = this.vCounterLatchHigh
          ? (this.vCounterLatch >> 8) & 1
          : this.vCounterLatch & 0xff;
        this.vCounterLatchHigh = !this.vCounterLatchHigh;
        return v;
      }
      case 0x3e: return 0x01; // PPU1 version 1
      case 0x3f: {
        this.hCounterLatchHigh = false;
        this.vCounterLatchHigh = false;
        let v = 0x02; // PPU2 version 2, NTSC
        if (this.vblankFlag) v |= 0x80;
        return v;
      }
      default: return 0;
    }
  }

  remap(a: number): number {
    switch (this.vramRemapMode) {
      case 1: return (a & 0xff00) | ((a & 0x1c) << 3) | (a & 3);
      case 2: return (a & 0xff00) | ((a & 1) << 8) | ((a >> 1) & 0x7f);
      case 3: return (a & 0xfe00) | ((a & 1) << 8) | ((a >> 1) & 0xff);
      default: return a & 0x7fff;
    }
  }

  vramWriteLo(v: number) {
    this.vram[(this.remap(this.vramAddr) << 1) & 0xffff] = v & 0xff;
    if (!this.vramIncOnHigh) {
      this.vramAddr = (this.vramAddr + this.vramIncrement) & 0xffff;
    }
  }

  vramWriteHi(v: number) {
    this.vram[((this.remap(this.vramAddr) << 1) | 1) & 0xffff] = v & 0xff;
    if (this.vramIncOnHigh) {
      this.vramAddr = (this.vramAddr + this.vramIncrement) & 0xffff;
    }
  }

  readVRAMWord(wordAddr: number): number {
    const b = (this.remap(wordAddr) << 1) & 0xffff;
    return this.vram[b] | (this.vram[(b + 1) & 0xffff] << 8);
  }

  oamWrite(v: number) {
    this.oam[this.oamAddr & 0x03ff] = v & 0xff;
    this.oamAddr = (this.oamAddr + 1) & 0x03ff;
  }

  cgWrite(v: number) {
    const index = (this.cgAddr * 2 + (this.cgLatchHigh ? 1 : 0)) & 0x1ff;
    this.cgram[index] = v & 0xff;
    if (this.cgLatchHigh) {
      this.cgAddr = (this.cgAddr + 1) & 0xff;
    }
    this.cgLatchHigh = !this.cgLatchHigh;
  }

  cgramColor(index: number): number {
    const a = (index * 2) & 0x1ff;
    return this.cgram[a] | (this.cgram[a + 1] << 8);
  }

  writeScroll(reg: number, value: number) {
    const index = reg - 0x0d;
    const layer = Math.floor(index / 2);
    const isX = index % 2 === 0;

    if (isX) {
      if (this.scrollLatch[index]) {
        this.bgx[layer] = (this.bgx[layer] & 0x0300) | value;
      } else {
        this.bgx[layer] = (this.bgx[layer] & 0x00ff) | ((value & 0x03) << 8);
      }
    } else {
      if (this.scrollLatch[index]) {
        this.bgy[layer] = (this.bgy[layer] & 0x0300) | value;
      } else {
        this.bgy[layer] = (this.bgy[layer] & 0x00ff) | ((value & 0x03) << 8);
      }
    }
    this.scrollLatch[index] = !this.scrollLatch[index];
  }

  startFrame() {
    this.vblankFlag = false;
  }

  runScanline(line: number) {
    this.scanline = line;
    if (line === 225) {
      this.vblankFlag = true;
      return;
    }
    if (line < PPU.height) {
      this.renderLine(line);
    }
  }

  private renderLine(line: number) {
    // Screen blanked?
    if (this.inidisp & 0x80) {
      this.fillLine(line, 0);
      return;
    }

    const buf = new Uint16Array(256);
    const pri = new Int8Array(256).fill(-1);
    const lay = new Int8Array(256).fill(-1);

    let mode = this.bgmode & 0x07;
    if (mode >= 2) mode = 1;

    for (let layer = 3; layer >= 0; layer--) {
      if ((this.tm & (1 << layer)) === 0) continue;
      if (mode === 1 && layer === 3) continue;
      this.renderBG(layer, line, mode, buf, pri, lay);
    }
    this.renderSprites(line, buf, pri, lay);

    const backdrop = this.cgramColor(0);
    for (let x = 0; x < 256; x++) {
      let color = backdrop;
      if (lay[x] >= 0) {
        color = this.applyColorMath(buf[x], lay[x]);
      }
      this.setFramePixel(line, x, this.applyBrightness(color));
    }
  }

  private renderBG(
    layer: number,
    line: number,
    mode: number,
    buf: Uint16Array,
    pri: Int8Array,
    lay: Int8Array
  ) {
    const bpp2 = mode === 0 || (mode === 1 && layer === 2);
    const cbase = this.charBaseFor(mode, layer);
    const size16 = (this.bgmode & (1 << (3 + layer))) !== 0;
    const shift = size16 ? 4 : 3;
    const scrollX = this.bgx[layer];
    const scrollY = this.bgy[layer];

    for (let px = 0; px < 256; px++) {
      const sx = px + scrollX;
      const sy = line + scrollY;
      const tx = (sx >> shift) & 63;
      const ty = (sy >> shift) & 63;
      const entry = this.mapEntry(layer, tx, ty);
      const color = this.pixelColor(entry, cbase, bpp2, sx, sy, size16);
      if (color < 0) continue;

      const p = (entry & 0x2000 ? 7 : 0) + (3 - layer);
      if (p >= pri[px]) {
        buf[px] = color;
        pri[px] = p;
        lay[px] = layer;
      }
    }
  }

  private charBaseFor(mode: number, layer: number): number {
    const nib = (v: number, high: boolean) => (high ? (v >> 4) & 0xf : v & 0xf);
    switch (layer) {
      case 0: return nib(this.bg12ba, false) << 13;
      case 1: return nib(this.bg12ba, true) << 13;
      case 2: return nib(this.bg34ba, false) << 13;
      default: return nib(this.bg34ba, true) << 13;
    }
  }

  private mapEntry(layer: number, tx: number, ty: number): number {
    const sc = this.bgsc[layer];
    const base = (sc & 0xfc) << 9;
    const size = sc & 0x03;
    const wide = (size & 0x01) !== 0;
    const tall = (size & 0x02) !== 0;
    let x = tx;
    let y = ty;
    let quadrant = 0;
    if (tx >= 32) {
      if (wide) quadrant |= 1;
      x = tx & 31;
    }
    if (ty >= 32) {
      if (tall) quadrant |= 2;
      y = ty & 31;
    }
    const columns = wide ? 2 : 1;
    const quadrantOffset = ((quadrant & 1) + ((quadrant >> 1) * columns)) << 11;
    const addr = (base + quadrantOffset + ((y & 31) << 6) + ((x & 31) << 1)) & 0xffff;
    return this.vram[addr] | (this.vram[(addr + 1) & 0xffff] << 8);
  }

  private pixelColor(
    entry: number,
    charBase: number,
    bpp2: boolean,
    sx: number,
    sy: number,
    size16: boolean
  ): number {
    let tile = entry & 0x3ff;
    const hflip = (entry & 0x4000) !== 0;
    const vflip = (entry & 0x8000) !== 0;
    const pal = (entry >> 10) & 7;

    const mask = size16 ? 15 : 7;
    let cx = sx & mask;
    let cy = sy & mask;
    if (hflip) cx = mask - cx;
    if (vflip) cy = mask - cy;

    if (size16) {
      const col = (cx >> 3) & 1;
      const row = (cy >> 3) & 1;
      tile += col + row * 16;
    }

    const bit = 7 - (cx & 7);
    const rowAddr = (charBase + tile * (bpp2 ? 16 : 32) + (cy & 7)) & 0xffff;
    const p0 = this.vram[rowAddr];
    const p1 = this.vram[(rowAddr + 8) & 0xffff];
    let value = ((p0 >> bit) & 1) | (((p1 >> bit) & 1) << 1);

    if (!bpp2) {
      const p2 = this.vram[(rowAddr + 16) & 0xffff];
      const p3 = this.vram[(rowAddr + 24) & 0xffff];
      value |= (((p2 >> bit) & 1) << 2) | (((p3 >> bit) & 1) << 3);
    }

    if (value === 0) return -1;
    const colorIndex = bpp2 ? pal * 4 + value : pal * 16 + value;
    return this.cgramColor(colorIndex);
  }

  private renderSprites(
    line: number,
    buf: Uint16Array,
    pri: Int8Array,
    lay: Int8Array
  ) {
    if ((this.tm & 0x10) === 0) return;

    const sizeIndex = (this.obisel >> 5) & 7;
    const nameBase = (this.obisel & 0x7) << 14;
    const small = PPU.spriteSizes[sizeIndex][0];
    const large = PPU.spriteSizes[sizeIndex][1];

    for (let i = 127; i >= 0; i--) {
      const o = i * 4;
      let x = this.oam[o];
      const y = this.oam[o + 1];
      let tile = this.oam[o + 2];
      const attr = this.oam[o + 3];

      const h = this.oam[0x200 + (i >> 1)];
      const shift = (i & 1) * 2;
      x |= ((h >> shift) & 1) << 8;
      tile |= ((h >> (shift + 1)) & 1) << 8;

      const sw = (attr & 0x80) !== 0 ? large : small;
      const sh = (attr & 0x80) !== 0 ? large : small;

      const sy = ((line - y - 1) % 256 + 256) % 256;
      if (sy >= sh) continue;

      const row = (attr & 0x40) !== 0 ? sh - 1 - sy : sy;
      const pal = attr & 0x7;
      const rawSprio = (attr >> 4) & 0x03;
      const sprio = rawSprio === 3 ? 11 : 4 + rawSprio;
      const hflip = (attr & 0x20) !== 0;

      for (let px = 0; px < sw; px++) {
        const sx = x + px;
        if (sx >= 256) continue;
        const col = hflip ? sw - 1 - px : px;
        const tileN = (tile + (col >> 3) + (row >> 3) * 16) & 0x1ff;

        const rowAddr = (nameBase + tileN * 32 + (row & 7)) & 0xffff;
        const bit = 7 - (col & 7);
        const p0 = this.vram[rowAddr];
        const p1 = this.vram[(rowAddr + 8) & 0xffff];
        const p2 = this.vram[(rowAddr + 16) & 0xffff];
        const p3 = this.vram[(rowAddr + 24) & 0xffff];

        let val = ((p0 >> bit) & 1) | (((p1 >> bit) & 1) << 1);
        val |= (((p2 >> bit) & 1) << 2) | (((p3 >> bit) & 1) << 3);
        if (val === 0) continue;

        const color = this.cgramColor(128 + pal * 16 + val);
        if (sprio >= pri[sx]) {
          buf[sx] = color;
          pri[sx] = sprio;
          lay[sx] = 4;
        }
      }
    }
  }

  private applyColorMath(color: number, layer: number): number {
    if ((this.cgwsel & 0x02) === 0) return color;
    const bit = layer < 4 ? 1 << layer : 0x10;
    if ((this.cgadsub & bit) === 0) return color;

    const fixed = this.fixedColorR | (this.fixedColorG << 5) | (this.fixedColorB << 10);
    const sub = (this.cgadsub & 0x80) !== 0;
    const half = (this.cgadsub & 0x40) !== 0;

    let r = color & 0x1f;
    let g = (color >> 5) & 0x1f;
    let b = (color >> 10) & 0x1f;

    const fr = fixed & 0x1f;
    const fg = (fixed >> 5) & 0x1f;
    const fb = (fixed >> 10) & 0x1f;

    if (sub) {
      r = Math.max(0, r - fr);
      g = Math.max(0, g - fg);
      b = Math.max(0, b - fb);
    } else {
      r = Math.min(0x1f, r + fr);
      g = Math.min(0x1f, g + fg);
      b = Math.min(0x1f, b + fb);
    }

    if (half) {
      r = Math.floor(r / 2);
      g = Math.floor(g / 2);
      b = Math.floor(b / 2);
    }

    return r | (g << 5) | (b << 10);
  }

  private applyBrightness(color: number): number {
    const level = this.inidisp & 0x0f;
    if (level >= 15) return color;
    const r = Math.floor(((color & 0x1f) * level) / 15);
    const g = Math.floor((((color >> 5) & 0x1f) * level) / 15);
    const b = Math.floor((((color >> 10) & 0x1f) * level) / 15);
    return r | (g << 5) | (b << 10);
  }

  private setFramePixel(line: number, x: number, color555: number) {
    const i = (line * 256 + x) * 4;
    const r5 = color555 & 0x1f;
    const g5 = (color555 >> 5) & 0x1f;
    const b5 = (color555 >> 10) & 0x1f;
    this.frame[i] = (r5 << 3) | (r5 >> 2);
    this.frame[i + 1] = (g5 << 3) | (g5 >> 2);
    this.frame[i + 2] = (b5 << 3) | (b5 >> 2);
    this.frame[i + 3] = 255;
  }

  private fillLine(line: number, color555: number) {
    for (let x = 0; x < 256; x++) {
      this.setFramePixel(line, x, color555);
    }
  }

  write(address: number, value: number) {
    this.writeRegister(address & 0x3f, value);
  }

  read(address: number): number {
    return this.readRegister(address & 0x3f);
  }

  renderScanline(line: number) {
    this.runScanline(line);
  }

  get vcounter(): number {
    return this.scanline;
  }

  set vcounter(v: number) {
    this.scanline = v;
  }

  get hcounter(): number {
    return this.hCounterLatch;
  }

  get framebuffer(): Uint32Array {
    return new Uint32Array(this.frame.buffer);
  }

  get vmadd(): number {
    return this.vramAddr;
  }

  set vmadd(v: number) {
    this.vramAddr = v;
  }

  get vmain(): number {
    return this.vramIncrement;
  }

  set vmain(v: number) {
    this.vramIncrement = v;
  }

  get cgadd(): number {
    return this.cgAddr;
  }

  set cgadd(v: number) {
    this.cgAddr = v;
  }
}
