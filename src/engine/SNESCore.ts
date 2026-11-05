import { CPU65816 } from './CPU65816';
import { PPU } from './PPU';
import { APU } from './APU';
import { Bus } from './Bus';
import { Cartridge } from './Cartridge';
import { ButtonMask } from '../types';

export class SNESCore {
  bus: Bus;
  cpu: CPU65816;
  ppu: PPU;
  apu: APU;
  cartridge?: Cartridge;

  cyclesPerScanline: number = 1364; // Master clock cycles / 4
  scanlinesPerFrame: number = 262;

  totalFrames: number = 0;
  fps: number = 60;
  private lastFpsTime: number = performance.now();
  private framesCount: number = 0;

  constructor() {
    this.ppu = new PPU();
    this.apu = new APU();
    this.bus = new Bus(this.ppu, this.apu);
    this.cpu = new CPU65816(this.bus);
    this.bus.attachCPU(this.cpu);
  }

  loadROM(data: Uint8Array): Cartridge {
    this.cartridge = new Cartridge(data);
    this.bus.insertCartridge(this.cartridge);
    this.reset();
    return this.cartridge;
  }

  reset() {
    this.ppu.reset();
    this.apu.reset();
    this.cpu.reset();
    this.totalFrames = 0;
  }

  runFrame(buttonState: number = 0): Uint32Array {
    this.bus.setJoypadState(0, buttonState);

    for (let scanline = 0; scanline < this.scanlinesPerFrame; scanline++) {
      this.ppu.vcounter = scanline;

      // Scanline 225 is the start of VBLANK
      if (scanline === 225) {
        this.bus.vblankActive = true;
        // Check if NMI is enabled in NMITIMEN bit 7
        if ((this.bus.nmitimen & 0x80) !== 0) {
          this.cpu.nmiPending = true;
        }
      }

      // Check V-Timer / H-Timer IRQ
      if ((this.bus.nmitimen & 0x20) !== 0 && scanline === this.bus.vTimer) {
        this.bus.irqActive = true;
        this.cpu.irqPending = true;
      }

      // Render visible scanline
      if (scanline < 224) {
        this.ppu.renderScanline(scanline);
      }

      // Execute CPU instructions for this scanline (~341 CPU cycles)
      let cyclesRemaining = 341;
      while (cyclesRemaining > 0 && !this.cpu.waitingForInterrupt && !this.cpu.stopped) {
        const cycles = this.cpu.step();
        cyclesRemaining -= cycles;
      }

      // If waiting for interrupt, advance cycles
      if (this.cpu.waitingForInterrupt || this.cpu.stopped) {
        // Wait until NMI or IRQ wakes it up
      }

      // Tick APU / DSP synthesis
      this.apu.step(128);
    }

    this.totalFrames++;
    this.framesCount++;

    const now = performance.now();
    if (now - this.lastFpsTime >= 1000) {
      this.fps = Math.round((this.framesCount * 1000) / (now - this.lastFpsTime));
      this.framesCount = 0;
      this.lastFpsTime = now;
    }

    return this.ppu.framebuffer;
  }

  setButton(button: ButtonMask, pressed: boolean) {
    if (pressed) {
      this.bus.joypads[0] |= button;
    } else {
      this.bus.joypads[0] &= ~button;
    }
  }

  getAudioSamples(): Float32Array {
    return this.apu.getAudioBuffer();
  }

  saveState(): string {
    const state = {
      cpu: {
        a: this.cpu.a,
        x: this.cpu.x,
        y: this.cpu.y,
        sp: this.cpu.sp,
        dp: this.cpu.dp,
        db: this.cpu.db,
        pb: this.cpu.pb,
        pc: this.cpu.pc,
        p: this.cpu.getP(),
        emulationMode: this.cpu.emulationMode
      },
      ppu: {
        inidisp: this.ppu.inidisp,
        bgmode: this.ppu.bgmode,
        cgadd: this.ppu.cgadd,
        vmain: this.ppu.vmain,
        vmadd: this.ppu.vmadd,
        cgram: Array.from(this.ppu.cgram)
      },
      wramPreview: Array.from(this.bus.wram.subarray(0, 512)),
      totalFrames: this.totalFrames,
      timestamp: Date.now()
    };
    return JSON.stringify(state);
  }

  loadState(stateJson: string): boolean {
    try {
      const state = JSON.parse(stateJson);
      this.cpu.a = state.cpu.a;
      this.cpu.x = state.cpu.x;
      this.cpu.y = state.cpu.y;
      this.cpu.sp = state.cpu.sp;
      this.cpu.dp = state.cpu.dp;
      this.cpu.db = state.cpu.db;
      this.cpu.pb = state.cpu.pb;
      this.cpu.pc = state.cpu.pc;
      this.cpu.setP(state.cpu.p);
      this.cpu.emulationMode = state.cpu.emulationMode;

      this.ppu.inidisp = state.ppu.inidisp;
      this.ppu.bgmode = state.ppu.bgmode;
      this.ppu.cgadd = state.ppu.cgadd;
      this.ppu.vmain = state.ppu.vmain;
      this.ppu.vmadd = state.ppu.vmadd;
      if (state.ppu.cgram) {
        this.ppu.cgram.set(state.ppu.cgram);
      }
      return true;
    } catch {
      return false;
    }
  }
}
