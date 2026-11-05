export class Cartridge {
  rom: Uint8Array;
  isHiRom: boolean;
  title: string;
  sram: Uint8Array;

  constructor(rawRom: Uint8Array) {
    const cleaned = Cartridge.strippedOfCopierHeader(rawRom);
    this.rom = cleaned;
    this.isHiRom = Cartridge.detectHiRom(cleaned);
    this.title = Cartridge.readTitle(cleaned, this.isHiRom);
    this.sram = new Uint8Array(0x8000); // 32KB battery-backed RAM
  }

  static strippedOfCopierHeader(rom: Uint8Array): Uint8Array {
    if (rom.length > 512 && rom.length % 0x400 === 512) {
      return rom.slice(512);
    }
    return rom;
  }

  romIndex(bank: number, off: number): number | null {
    if (this.isHiRom) {
      if ((bank >= 0x00 && bank <= 0x3f) || (bank >= 0x80 && bank <= 0xbf)) {
        if (off < 0x8000) return null;
        return ((bank & 0x3f) << 16) | off;
      } else if ((bank >= 0x40 && bank <= 0x7d) || (bank >= 0xc0 && bank <= 0xff)) {
        return ((bank & 0x3f) << 16) | off;
      }
      return null;
    } else {
      if (off < 0x8000) return null;
      if ((bank >= 0x00 && bank <= 0x7d) || (bank >= 0x80 && bank <= 0xff)) {
        return ((bank & 0x7f) << 15) | (off & 0x7fff);
      }
      return null;
    }
  }

  static detectHiRom(rom: Uint8Array): boolean {
    const score = (offset: number): number => {
      if (rom.length < offset + 0x40) return -1000;
      let s = 0;
      const complement = rom[offset + 0x1c] | (rom[offset + 0x1d] << 8);
      const checksum = rom[offset + 0x1e] | (rom[offset + 0x1f] << 8);
      if ((complement ^ 0xffff) === checksum) {
        s += 10;
      }
      const mode = rom[offset + 0x15];
      if ((mode & 0x20) !== 0) s += 3;
      if (offset === 0xffc0) {
        if ((mode & 1) !== 0) s += 4;
        else s -= 4;
      } else {
        if ((mode & 1) === 0) s += 4;
        else s -= 4;
      }
      const romSize = rom[offset + 0x17];
      if (romSize >= 0x07 && romSize <= 0x0e) s += 3;

      const reset = rom[offset + 0x3c] | (rom[offset + 0x3d] << 8);
      if (reset >= 0x8000) s += 6;

      let printable = 0;
      for (let i = 0; i < 21; i++) {
        const b = rom[offset + i];
        if (b >= 0x20 && b <= 0x7e) printable++;
      }
      s += Math.floor(printable / 4);
      return s;
    };

    return score(0xffc0) > score(0x7fc0);
  }

  get isHiROM(): boolean {
    return this.isHiRom;
  }

  read(bank: number, address: number): number {
    const idx = this.romIndex(bank, address);
    if (idx !== null && idx >= 0 && idx < this.rom.length) {
      return this.rom[idx];
    }
    return 0;
  }

  get resetVector(): number {
    const off = this.isHiRom ? 0xfffc : 0x7ffc;
    if (this.rom.length > off + 1) return this.rom[off] | (this.rom[off + 1] << 8);
    return 0x8000;
  }

  get nmiVector(): number {
    const off = this.isHiRom ? 0xffea : 0x7fea;
    if (this.rom.length > off + 1) return this.rom[off] | (this.rom[off + 1] << 8);
    return 0x8020;
  }

  get checksumComplement(): number {
    const off = this.isHiRom ? 0xffdc : 0x7fdc;
    if (this.rom.length > off + 1) return this.rom[off] | (this.rom[off + 1] << 8);
    return 0xffff;
  }

  static readTitle(rom: Uint8Array, hiRom: boolean): string {
    const offset = hiRom ? 0xffc0 : 0x7fc0;
    if (rom.length < offset + 21) return 'UNKNOWN';
    let title = '';
    for (let i = 0; i < 21; i++) {
      const b = rom[offset + i];
      if (b >= 0x20 && b <= 0x7e) {
        title += String.fromCharCode(b);
      } else {
        title += ' ';
      }
    }
    title = title.trim();
    return title.length === 0 ? 'UNKNOWN' : title;
  }
}
