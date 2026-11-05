import { Cartridge } from './Cartridge';
import { PPU } from './PPU';
import { APU } from './APU';
import { CPU65816 } from './CPU65816';

interface DMAChannel {
  control: number;
  destRegister: number;
  sourceAddress: number;
  sourceBank: number;
  transferSize: number;
  indirectBank: number;
  hdmaTableAddress: number;
  lineCounter: number;
  active: boolean;
  hdmaActive: boolean;
}

export class Bus {
  cartridge?: Cartridge;
  ppu: PPU;
  apu: APU;
  cpu?: CPU65816;

  wram = new Uint8Array(128 * 1024);
  sram = new Uint8Array(64 * 1024);

  // WRAM port registers ($2180-$2183)
  wmadd: number = 0; // 24-bit pointer into WRAM

  nmitimen: number = 0;
  vblankActive: boolean = false;
  irqActive: boolean = false;
  hTimer: number = 0;
  vTimer: number = 0;

  // Joypad states (16-bit)
  joypads: [number, number] = [0, 0];
  joypadShift: [number, number] = [0, 0];
  joypadAutoRead: boolean = true;

  // Math registers
  mpyA: number = 0xFF;
  mpyB: number = 0xFF;
  divDividend: number = 0xFFFF;
  divDivisor: number = 0xFF;
  divQuotient: number = 0;
  divRemainder: number = 0;

  channels: DMAChannel[] = Array.from({ length: 8 }, () => ({
    control: 0,
    destRegister: 0,
    sourceAddress: 0,
    sourceBank: 0,
    transferSize: 0,
    indirectBank: 0,
    hdmaTableAddress: 0,
    lineCounter: 0,
    active: false,
    hdmaActive: false
  }));

  constructor(ppu: PPU, apu: APU) {
    this.ppu = ppu;
    this.apu = apu;
  }

  attachCPU(cpu: CPU65816) {
    this.cpu = cpu;
  }

  insertCartridge(cartridge: Cartridge) {
    this.cartridge = cartridge;
    this.sram.fill(0);
  }

  read(bankOrAddr: number, address?: number): number {
    let bank: number;
    let addr: number;
    if (address === undefined) {
      bank = (bankOrAddr >> 16) & 0xFF;
      addr = bankOrAddr & 0xFFFF;
    } else {
      bank = bankOrAddr & 0xFF;
      addr = address & 0xFFFF;
    }

    // Banks $00-$3F and $80-$BF: System Area
    if ((bank <= 0x3F) || (bank >= 0x80 && bank <= 0xBF)) {
      if (addr < 0x2000) {
        // Low 8KB WRAM mirror
        return this.wram[addr];
      }

      if (addr >= 0x2100 && addr <= 0x213F) {
        return this.ppu.read(addr);
      }

      if (addr >= 0x2140 && addr <= 0x217F) {
        return this.apu.read(addr & 3);
      }

      if (addr === 0x2180) {
        // WMDATA read
        const val = this.wram[this.wmadd & 0x1FFFF];
        this.wmadd = (this.wmadd + 1) & 0x1FFFF;
        return val;
      }

      if (addr >= 0x4200 && addr <= 0x421F) {
        return this.readCPURegister(addr);
      }

      if (addr >= 0x4300 && addr <= 0x437F) {
        return this.readDMARegister(addr);
      }

      if (this.cartridge) {
        // Cartridge ROM/SRAM mapping
        if (this.cartridge.isHiROM) {
          if (addr >= 0x6000 && addr <= 0x7FFF) {
            // HiROM SRAM
            const sramAddr = ((bank & 0x1F) << 13) | (addr - 0x6000);
            return this.sram[sramAddr % Math.max(1, this.sram.length)];
          }
          if (addr >= 0x8000) {
            return this.cartridge.read(bank, addr);
          }
        } else {
          // LoROM
          if (addr >= 0x7000 && addr <= 0x7DFF) {
            const sramAddr = ((bank & 0x0F) << 15) | (addr - 0x7000);
            return this.sram[sramAddr % Math.max(1, this.sram.length)];
          }
          if (addr >= 0x8000) {
            return this.cartridge.read(bank, addr);
          }
        }
      }

      return 0x00;
    }

    // Banks $40-$7D: ROM
    if (bank >= 0x40 && bank <= 0x7D) {
      if (this.cartridge) {
        return this.cartridge.read(bank, addr);
      }
      return 0x00;
    }

    // Banks $7E-$7F: Full 128KB WRAM
    if (bank === 0x7E) {
      return this.wram[addr];
    }
    if (bank === 0x7F) {
      return this.wram[0x10000 + addr];
    }

    // Banks $C0-$FF: ROM / SRAM
    if (bank >= 0xC0) {
      if (this.cartridge) {
        return this.cartridge.read(bank, addr);
      }
    }

    return 0x00;
  }

  write(bankOrAddr: number, addrOrVal: number, value?: number) {
    let bank: number;
    let address: number;
    let val: number;
    if (value === undefined) {
      bank = (bankOrAddr >> 16) & 0xFF;
      address = bankOrAddr & 0xFFFF;
      val = addrOrVal & 0xFF;
    } else {
      bank = bankOrAddr & 0xFF;
      address = addrOrVal & 0xFFFF;
      val = value & 0xFF;
    }

    if ((bank <= 0x3F) || (bank >= 0x80 && bank <= 0xBF)) {
      if (address < 0x2000) {
        this.wram[address] = val;
        return;
      }

      if (address >= 0x2100 && address <= 0x213F) {
        this.ppu.write(address, val);
        return;
      }

      if (address >= 0x2140 && address <= 0x217F) {
        this.apu.write(address & 3, val);
        return;
      }

      if (address === 0x2180) {
        this.wram[this.wmadd & 0x1FFFF] = val;
        this.wmadd = (this.wmadd + 1) & 0x1FFFF;
        return;
      }

      if (address === 0x2181) {
        this.wmadd = (this.wmadd & 0x1FF00) | val;
        return;
      }

      if (address === 0x2182) {
        this.wmadd = (this.wmadd & 0x100FF) | (val << 8);
        return;
      }

      if (address === 0x2183) {
        this.wmadd = (this.wmadd & 0x0FFFF) | ((val & 1) << 16);
        return;
      }

      if (address >= 0x4200 && address <= 0x421F) {
        this.writeCPURegister(address, val);
        return;
      }

      if (address >= 0x4300 && address <= 0x437F) {
        this.writeDMARegister(address, val);
        return;
      }

      if (this.cartridge) {
        if (this.cartridge.isHiROM) {
          if (address >= 0x6000 && address <= 0x7FFF) {
            const sramAddr = ((bank & 0x1F) << 13) | (address - 0x6000);
            this.sram[sramAddr % Math.max(1, this.sram.length)] = val;
          }
        } else {
          if (address >= 0x7000 && address <= 0x7DFF) {
            const sramAddr = ((bank & 0x0F) << 15) | (address - 0x7000);
            this.sram[sramAddr % Math.max(1, this.sram.length)] = val;
          }
        }
      }
      return;
    }

    if (bank === 0x7E) {
      this.wram[address] = val;
      return;
    }

    if (bank === 0x7F) {
      this.wram[0x10000 + address] = val;
      return;
    }
  }

  read16(bank: number, address: number): number {
    const low = this.read(bank, address);
    const high = this.read(bank, address + 1);
    return (high << 8) | low;
  }

  write16(bank: number, address: number, value: number) {
    this.write(bank, address, value & 0xFF);
    this.write(bank, address + 1, (value >> 8) & 0xFF);
  }

  readCPURegister(address: number): number {
    switch (address) {
      case 0x4210: {
        // RDNMI: NMI Flag and CPU 5A22 version
        let val = 0x02; // CPU version 2
        if (this.vblankActive) val |= 0x80;
        this.vblankActive = false;
        return val;
      }
      case 0x4211: {
        // TIMEUP: IRQ Flag
        const val = this.irqActive ? 0x80 : 0x00;
        this.irqActive = false;
        return val;
      }
      case 0x4212: {
        // HVBJOY: Status
        let val = 0;
        if (this.ppu.vcounter >= 225) val |= 0x80; // VBlank
        if (this.ppu.hcounter < 4 || this.ppu.hcounter > 260) val |= 0x40; // HBlank
        return val;
      }
      case 0x4214: return this.divQuotient & 0xFF;
      case 0x4215: return (this.divQuotient >> 8) & 0xFF;
      case 0x4216: return this.divRemainder & 0xFF;
      case 0x4217: return (this.divRemainder >> 8) & 0xFF;
      case 0x4218: return this.joypads[0] & 0xFF;
      case 0x4219: return (this.joypads[0] >> 8) & 0xFF;
      case 0x421A: return this.joypads[1] & 0xFF;
      case 0x421B: return (this.joypads[1] >> 8) & 0xFF;
      default: return 0;
    }
  }

  writeCPURegister(address: number, value: number) {
    switch (address) {
      case 0x4200:
        this.nmitimen = value;
        break;
      case 0x4201:
        // WRIO: Programmable I/O Port
        break;
      case 0x4202:
        this.mpyA = value;
        break;
      case 0x4203:
        this.mpyB = value;
        // 8-bit * 8-bit unsigned multiply
        this.divRemainder = this.mpyA * this.mpyB;
        break;
      case 0x4204:
        this.divDividend = (this.divDividend & 0xFF00) | value;
        break;
      case 0x4205:
        this.divDividend = (this.divDividend & 0x00FF) | (value << 8);
        break;
      case 0x4206:
        this.divDivisor = value;
        if (this.divDivisor === 0) {
          this.divQuotient = 0xFFFF;
          this.divRemainder = this.divDividend;
        } else {
          this.divQuotient = Math.floor(this.divDividend / this.divDivisor) & 0xFFFF;
          this.divRemainder = (this.divDividend % this.divDivisor) & 0xFFFF;
        }
        break;
      case 0x4207:
        this.hTimer = (this.hTimer & 0x100) | value;
        break;
      case 0x4208:
        this.hTimer = (this.hTimer & 0x0FF) | ((value & 1) << 8);
        break;
      case 0x4209:
        this.vTimer = (this.vTimer & 0x100) | value;
        break;
      case 0x420A:
        this.vTimer = (this.vTimer & 0x0FF) | ((value & 1) << 8);
        break;
      case 0x420B:
        // MDMAEN: DMA Enable (channels 0-7)
        for (let i = 0; i < 8; i++) {
          if ((value & (1 << i)) !== 0) {
            this.runDMA(i);
          }
        }
        break;
      case 0x420C:
        // HDMAEN: HDMA Enable (channels 0-7)
        for (let i = 0; i < 8; i++) {
          this.channels[i].hdmaActive = (value & (1 << i)) !== 0;
        }
        break;
    }
  }

  readDMARegister(address: number): number {
    const ch = (address >> 4) & 7;
    const reg = address & 0x0F;
    const c = this.channels[ch];

    switch (reg) {
      case 0x00: return c.control;
      case 0x01: return c.destRegister;
      case 0x02: return c.sourceAddress & 0xFF;
      case 0x03: return (c.sourceAddress >> 8) & 0xFF;
      case 0x04: return c.sourceBank;
      case 0x05: return c.transferSize & 0xFF;
      case 0x06: return (c.transferSize >> 8) & 0xFF;
      case 0x07: return c.indirectBank;
      default: return 0;
    }
  }

  writeDMARegister(address: number, value: number) {
    const ch = (address >> 4) & 7;
    const reg = address & 0x0F;
    const c = this.channels[ch];

    switch (reg) {
      case 0x00: c.control = value; break;
      case 0x01: c.destRegister = value; break;
      case 0x02: c.sourceAddress = (c.sourceAddress & 0xFF00) | value; break;
      case 0x03: c.sourceAddress = (c.sourceAddress & 0x00FF) | (value << 8); break;
      case 0x04: c.sourceBank = value; break;
      case 0x05: c.transferSize = (c.transferSize & 0xFF00) | value; break;
      case 0x06: c.transferSize = (c.transferSize & 0x00FF) | (value << 8); break;
      case 0x07: c.indirectBank = value; break;
    }
  }

  runDMA(channelIndex: number) {
    const ch = this.channels[channelIndex];
    let count = ch.transferSize === 0 ? 0x10000 : ch.transferSize;
    const mode = ch.control & 0x07;
    const fixed = (ch.control & 0x08) !== 0;
    const decrement = (ch.control & 0x10) !== 0;
    const step = fixed ? 0 : (decrement ? -1 : 1);

    const bBusBase = 0x2100 + ch.destRegister;

    // Pattern table for DMA transfer units
    const patterns: number[][] = [
      [0],             // 1 register
      [0, 1],          // 2 registers (e.g. VMDATA low/high)
      [0, 0],          // 1 register write twice
      [0, 0, 1, 1],    // 2 registers write twice
      [0, 1, 2, 3]     // 4 registers
    ];
    const pat = patterns[mode % patterns.length] || [0];
    let pIdx = 0;

    while (count > 0) {
      const bAddr = bBusBase + pat[pIdx];
      pIdx = (pIdx + 1) % pat.length;

      const val = this.read(ch.sourceBank, ch.sourceAddress);
      this.write(0x00, bAddr, val);

      // Advance source address wrapping in 16 bits
      ch.sourceAddress = (ch.sourceAddress + step) & 0xFFFF;
      count--;
    }

    ch.transferSize = 0;
  }

  setJoypadState(player: number, state: number) {
    if (player >= 0 && player < 2) {
      this.joypads[player] = state;
    }
  }
}
