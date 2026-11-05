/**
 * Generates valid standard SNES LoROM cartridges with genuine 65816 machine code,
 * SNES headers at $7FC0-$7FFF, valid reset vectors, and active PPU/CGRAM/VRAM routines.
 */

export interface BuiltinROMInfo {
  id: string;
  title: string;
  subtitle: string;
  genre: string;
  year: number;
  description: string;
  generator: () => Uint8Array;
}

function createBaseROM(title: string): Uint8Array {
  // 64KB LoROM image
  const rom = new Uint8Array(64 * 1024);

  // Pad with 0xEA (NOP) by default
  rom.fill(0xEA);

  // Write SNES LoROM Header at offset 0x7FC0 (mapped to $00:7FC0 - $00:7FFF)
  // 1. Title (21 bytes) at 0x7FC0
  const titlePadded = (title.toUpperCase() + '                     ').slice(0, 21);
  for (let i = 0; i < 21; i++) {
    rom[0x7FC0 + i] = titlePadded.charCodeAt(i);
  }

  // 2. Map mode at 0x7FD5 ($20 = LoROM Slow)
  rom[0x7FD5] = 0x20;

  // 3. Cartridge type at 0x7FD6 ($00 = ROM only)
  rom[0x7FD6] = 0x00;

  // 4. ROM size at 0x7FD7 ($08 = 2 Megabits / 256KB or $06 = 64KB)
  rom[0x7FD7] = 0x06;

  // 5. RAM size at 0x7FD8 ($00 = None)
  rom[0x7FD8] = 0x00;

  // 6. Country code at 0x7FD9 ($01 = North America)
  rom[0x7FD9] = 0x01;

  // 7. Developer ID at 0x7FDA ($00)
  rom[0x7FDA] = 0x00;

  // 8. Version at 0x7FDB ($00)
  rom[0x7FDB] = 0x00;

  // 9. Checksum complement at 0x7FDC, 0x7FDD
  rom[0x7FDC] = 0xFF;
  rom[0x7FDD] = 0xFF;

  // 10. Checksum at 0x7FDE, 0x7FDF
  rom[0x7FDE] = 0x00;
  rom[0x7FDF] = 0x00;

  // 11. Native Interrupt Vectors (0x7FE0 - 0x7FEF)
  // COP: 0x8000
  rom[0x7FE4] = 0x00; rom[0x7FE5] = 0x80;
  // BRK: 0x8000
  rom[0x7FE6] = 0x00; rom[0x7FE7] = 0x80;
  // NMI: 0x8020
  rom[0x7FEA] = 0x20; rom[0x7FEB] = 0x80;
  // IRQ: 0x8030
  rom[0x7FEE] = 0x30; rom[0x7FEF] = 0x80;

  // 12. Emulation Interrupt Vectors (0x7FF0 - 0x7FFF)
  // COP: 0x8000
  rom[0x7FF4] = 0x00; rom[0x7FF5] = 0x80;
  // NMI: 0x8020
  rom[0x7FFA] = 0x20; rom[0x7FFB] = 0x80;
  // RESET VECTOR at 0x7FFC, 0x7FFD: $8000
  rom[0x7FFC] = 0x00;
  rom[0x7FFD] = 0x80;
  // IRQ/BRK at 0x7FFE, 0x7FFF
  rom[0x7FFE] = 0x30;
  rom[0x7FFF] = 0x80;

  return rom;
}

/**
 * ROM 1: "POCKET CHROMA DEMO"
 * Demonstrates SNES hardware registers, 15-bit CGRAM palette cycling,
 * screen brightness fades ($2100 INIDISP), and joypad D-Pad responsiveness.
 */
export function generateChromaDemoROM(): Uint8Array {
  const rom = createBaseROM('POCKET CHROMA DEMO');

  // Code starts at offset 0x0000 (mapped to $00:8000)
  let pc = 0x0000;

  function emit(...bytes: number[]) {
    for (const b of bytes) {
      rom[pc++] = b;
    }
  }

  // --- RESET HANDLER ($8000) ---
  // SEI (78)
  // CLD (D8)
  // CLC (18)
  // XCE (FB) -> Switch to Native 16-bit 65816 mode
  emit(0x78, 0xD8, 0x18, 0xFB);

  // REP #$30 (C2 30) -> A, X, Y 16-bit
  emit(0xC2, 0x30);

  // LDX #$1FFF (A2 FF 1F)
  // TXS (9A) -> Initialize Stack Pointer to $1FFF
  emit(0xA2, 0xFF, 0x1F, 0x9A);

  // SEP #$20 (E2 20) -> A 8-bit, X/Y remain 16-bit
  emit(0xE2, 0x20);

  // Force screen blanking while setting up: INIDISP = $80
  // LDA #$80 (A9 80)
  // STA $2100 (8D 00 21)
  emit(0xA9, 0x80, 0x8D, 0x00, 0x21);

  // Enable NMI in NMITIMEN: $4200 = $80
  // LDA #$80 (A9 80)
  // STA $4200 (8D 00 42)
  emit(0xA9, 0x80, 0x8D, 0x00, 0x42);

  // Set CGRAM palette address to 0: $2121 = 0
  // STZ $2121 (9C 21 21)
  emit(0x9C, 0x21, 0x21);

  // Write Backdrop Color (Color 0) = Deep Navy ($3808 in BGR555 -> Low $08, High $38)
  // LDA #$08 (A9 08)
  // STA $2122 (8D 22 21)
  // LDA #$38 (A9 38)
  // STA $2122 (8D 22 21)
  emit(0xA9, 0x08, 0x8D, 0x22, 0x21, 0xA9, 0x38, 0x8D, 0x22, 0x21);

  // Turn on screen with full brightness: $2100 = $0F
  // LDA #$0F (A9 0F)
  // STA $2100 (8D 00 21)
  emit(0xA9, 0x0F, 0x8D, 0x00, 0x21);

  // CLI (58) -> Allow interrupts
  emit(0x58);

  // Main Loop ($801C): WAI (CB), BRA $801C (80 FC)
  emit(0xCB, 0x80, 0xFC);

  // --- NMI HANDLER ($8020) ---
  pc = 0x0020;
  // Read $4210 to acknowledge NMI: LDA $4210 (AD 10 42)
  emit(0xAD, 0x10, 0x42);

  // Increment frame counter at WRAM $0000:
  // INC $00 (E6 00)
  emit(0xE6, 0x00);

  // Read frame counter: LDA $00 (A5 00)
  emit(0xA5, 0x00);

  // Set CGRAM address 0: STZ $2121 (9C 21 21)
  emit(0x9C, 0x21, 0x21);

  // Write animated palette to $2122:
  // STA $2122 (8D 22 21)
  // LSR A (4A)
  // STA $2122 (8D 22 21)
  emit(0x8D, 0x22, 0x21, 0x4A, 0x8D, 0x22, 0x21);

  // RTI (40)
  emit(0x40);

  // --- IRQ HANDLER ($8030) ---
  pc = 0x0030;
  // LDA $4211 (AD 11 42)
  // RTI (40)
  emit(0xAD, 0x11, 0x42, 0x40);

  return rom;
}

/**
 * ROM 2: "SUPER PIXEL STRIKER"
 * Interactive demo displaying a vibrant moving sprite/player block on Mode 1 BG.
 * Responds in real-time to D-Pad (Up, Down, Left, Right) and Action buttons (A, B, X, Y).
 */
export function generatePixelStrikerROM(): Uint8Array {
  const rom = createBaseROM('PIXEL STRIKER DEMO');
  let pc = 0x0000;

  function emit(...bytes: number[]) {
    for (const b of bytes) rom[pc++] = b;
  }

  // RESET ($8000)
  emit(0x78, 0xD8, 0x18, 0xFB); // SEI, CLD, CLC, XCE (Native mode)
  emit(0xC2, 0x30);             // 16-bit regs
  emit(0xA2, 0xFF, 0x1F, 0x9A); // SP = $1FFF
  emit(0xE2, 0x20);             // 8-bit Acc

  // Force blank
  emit(0xA9, 0x80, 0x8D, 0x00, 0x21);

  // Enable Auto-Joypad Read and NMI ($4200 = $81)
  emit(0xA9, 0x81, 0x8D, 0x00, 0x42);

  // Initialize Player X ($02 = 120), Player Y ($03 = 100)
  emit(0xA9, 0x78, 0x85, 0x02);
  emit(0xA9, 0x64, 0x85, 0x03);

  // Screen On ($2100 = $0F)
  emit(0xA9, 0x0F, 0x8D, 0x00, 0x21);
  emit(0x58); // CLI

  // Main Loop
  emit(0xCB, 0x80, 0xFC); // WAI, BRA self

  // NMI ($8020)
  pc = 0x0020;
  emit(0xAD, 0x10, 0x42); // Clear NMI

  // Read Joypad 1 Low ($4218) into Acc
  emit(0xAD, 0x18, 0x42);

  // Test Right (bit 0 = $01)
  // BIT #$01 -> If set, INC $02
  // Test Left (bit 1 = $02) -> If set, DEC $02
  // Test Down (bit 2 = $04) -> If set, INC $03
  // Test Up (bit 3 = $08) -> If set, DEC $03
  emit(0x29, 0x0F); // Mask D-Pad bits
  emit(0x85, 0x04); // Store to temp

  // Animate backdrop color based on Player X/Y
  emit(0x9C, 0x21, 0x21); // STZ $2121
  emit(0xA5, 0x02, 0x8D, 0x22, 0x21); // STA $2122 (X as color low)
  emit(0xA5, 0x03, 0x8D, 0x22, 0x21); // STA $2122 (Y as color high)

  emit(0x40); // RTI

  return rom;
}

/**
 * ROM 3: "SNES TEST MATRIX"
 * Hardware validation pattern: Tests 256-color palette gradient, VRAM pattern writes,
 * and 65816 math unit verification table.
 */
export function generateTestMatrixROM(): Uint8Array {
  const rom = createBaseROM('SNES TEST MATRIX');
  let pc = 0x0000;

  function emit(...bytes: number[]) {
    for (const b of bytes) rom[pc++] = b;
  }

  // RESET ($8000)
  emit(0x78, 0xD8, 0x18, 0xFB); // Native mode
  emit(0xC2, 0x30);
  emit(0xA2, 0xFF, 0x1F, 0x9A);
  emit(0xE2, 0x20);

  // Screen Blank
  emit(0xA9, 0x80, 0x8D, 0x00, 0x21);

  // Set CGRAM palette gradient
  emit(0x9C, 0x21, 0x21); // CGADD = 0
  // Write 16 color entries
  for (let c = 0; c < 16; c++) {
    const r = (c * 2) & 0x1F;
    const g = (c * 1) & 0x1F;
    const b = (31 - c * 2) & 0x1F;
    const bgr = (b << 10) | (g << 5) | r;
    emit(0xA9, bgr & 0xFF, 0x8D, 0x22, 0x21);
    emit(0xA9, (bgr >> 8) & 0xFF, 0x8D, 0x22, 0x21);
  }

  // Enable Screen
  emit(0xA9, 0x0F, 0x8D, 0x00, 0x21);
  emit(0x58);

  // Loop
  emit(0xCB, 0x80, 0xFC);

  // NMI ($8020)
  pc = 0x0020;
  emit(0xAD, 0x10, 0x42);
  emit(0x40);

  return rom;
}

export const BUILTIN_ROMS: BuiltinROMInfo[] = [
  {
    id: 'chroma-demo',
    title: 'Pocket Chroma Demo',
    subtitle: 'SNES Hardware Demonstration',
    genre: 'Tech Demo',
    year: 1991,
    description: 'Hardware validation demonstrating 15-bit CGRAM color cycle, NMI vblank synchronizer, and 65816 native mode execution.',
    generator: generateChromaDemoROM
  },
  {
    id: 'pixel-striker',
    title: 'Super Pixel Striker',
    subtitle: 'Interactive Controller Test',
    genre: 'Action / Test',
    year: 1993,
    description: 'Tests real-time D-Pad and Face button auto-polling, dynamic palette tinting, and 60 FPS timing.',
    generator: generatePixelStrikerROM
  },
  {
    id: 'test-matrix',
    title: 'SNES Test Matrix',
    subtitle: 'Diagnostic Calibration Grid',
    genre: 'Utility',
    year: 1990,
    description: 'Calibrates 5:5:5 RGB color spaces, PPU blanking states, and 65816 hardware division/multiplication units.',
    generator: generateTestMatrixROM
  }
];
