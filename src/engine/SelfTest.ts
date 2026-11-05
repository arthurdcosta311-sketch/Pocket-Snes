import { SNESCore } from './SNESCore';

export interface TestResult {
  name: string;
  passed: boolean;
  details: string;
}

export function runEngineSelfTest(): { results: TestResult[]; allPassed: boolean } {
  const results: TestResult[] = [];
  const core = new SNESCore();

  // Test 1: Stack-relative opcodes (0xA3 LDA d,S and 0x83 STA d,S)
  try {
    const cpu = core.cpu;
    cpu.reset();
    cpu.emulationMode = false;
    cpu.mf = false; // 16-bit accumulator
    cpu.xf = false; // 16-bit index

    // Push 0x1234 to stack
    cpu.push16(0x1234);
    // sp is now decremented by 2. d,S with d=1 points to low byte, d=2 points to high byte
    const oldSp = cpu.sp;

    // Load from stack relative: opcode 0xA3, operand 1
    cpu.a = 0;
    // Set program memory at reset vector to: A3 01 (LDA 1,S) followed by STP (DB)
    core.bus.write(0x00, 0x8000, 0xA3);
    core.bus.write(0x00, 0x8001, 0x01);
    core.bus.write(0x00, 0x8002, 0xDB);
    cpu.pc = 0x8000;
    cpu.pb = 0x00;

    cpu.step(); // Execute LDA 1,S

    const passed = cpu.a === 0x1234 && cpu.sp === oldSp;
    results.push({
      name: 'Stack-Relative Opcodes (LDA d,S)',
      passed,
      details: passed
        ? 'Successfully read 16-bit value from stack offset without modifying SP'
        : `Expected A=0x1234, got A=0x${cpu.a.toString(16).toUpperCase()}`
    });
  } catch (err) {
    results.push({
      name: 'Stack-Relative Opcodes (LDA d,S)',
      passed: false,
      details: String(err)
    });
  }

  // Test 2: WRAM Port ($2180-$2183) Auto-Increment
  try {
    const bus = core.bus;
    // Set address to $002000
    bus.write(0x00, 0x2181, 0x00);
    bus.write(0x00, 0x2182, 0x20);
    bus.write(0x00, 0x2183, 0x00);

    // Write through $2180
    bus.write(0x00, 0x2180, 0xAA);
    bus.write(0x00, 0x2180, 0x55);

    // Read directly from WRAM array
    const val1 = bus.wram[0x2000];
    const val2 = bus.wram[0x2001];

    // Reset address and read back through $2180
    bus.write(0x00, 0x2181, 0x00);
    bus.write(0x00, 0x2182, 0x20);
    bus.write(0x00, 0x2183, 0x00);
    const read1 = bus.read(0x00, 0x2180);
    const read2 = bus.read(0x00, 0x2180);

    const passed = val1 === 0xAA && val2 === 0x55 && read1 === 0xAA && read2 === 0x55;
    results.push({
      name: 'WRAM Port ($2180-$2183) Read/Write & Increment',
      passed,
      details: passed
        ? 'WMDATA auto-increments 24-bit pointer and maps correctly into 128KB WRAM'
        : `Got values: val1=0x${val1.toString(16)}, val2=0x${val2.toString(16)}, read1=0x${read1.toString(16)}, read2=0x${read2.toString(16)}`
    });
  } catch (err) {
    results.push({
      name: 'WRAM Port ($2180-$2183)',
      passed: false,
      details: String(err)
    });
  }

  // Test 3: VRAM Address Byte Ordering ($2116 VMADDL / $2117 VMADDH)
  try {
    const ppu = core.ppu;
    ppu.reset();

    // Write low byte $34 to $2116, high byte $12 to $2117
    ppu.write(0x2116, 0x34);
    ppu.write(0x2117, 0x12);

    const passed = ppu.vmadd === 0x1234;
    results.push({
      name: 'VRAM Register Byte Ordering ($2116 VMADDL / $2117 VMADDH)',
      passed,
      details: passed
        ? 'VMADD set to 0x1234 (low byte correctly assigned to bits 0-7, high byte to bits 8-15)'
        : `Expected 0x1234, got 0x${ppu.vmadd.toString(16).toUpperCase()}`
    });
  } catch (err) {
    results.push({
      name: 'VRAM Register Byte Ordering',
      passed: false,
      details: String(err)
    });
  }

  // Test 4: Interrupt M/X Flag Preservation
  try {
    const cpu = core.cpu;
    cpu.reset();
    cpu.emulationMode = false;
    cpu.mf = true; // 8-bit accumulator
    cpu.xf = true; // 8-bit index
    cpu.db = 0x7E;

    // Trigger NMI
    cpu.nmiPending = true;
    cpu.step();

    // Verify DB wasn't wiped to 0 and pushed P had M=1
    const pOnStack = core.bus.read(0x00, cpu.sp + 1);
    const mPreserved = (pOnStack & 0x20) !== 0;
    const dbPreserved = cpu.db === 0x7E;

    const passed = mPreserved && dbPreserved;
    results.push({
      name: 'Interrupt Handler State Preservation (Native 65816 NMI)',
      passed,
      details: passed
        ? 'Interrupt preserves Accumulator/Index 8-bit flags in pushed status register and preserves Data Bank (DB)'
        : `M flag preserved: ${mPreserved}, DB preserved: ${dbPreserved}`
    });
  } catch (err) {
    results.push({
      name: 'Interrupt Handler State Preservation',
      passed: false,
      details: String(err)
    });
  }

  // Test 5: Hardware Multiplication and Division ($4202-$4206)
  try {
    const bus = core.bus;
    // 25 * 10 = 250
    bus.write(0x00, 0x4202, 25);
    bus.write(0x00, 0x4203, 10);
    const mpyLow = bus.read(0x00, 0x4216);
    const mpyHigh = bus.read(0x00, 0x4217);
    const mpyResult = (mpyHigh << 8) | mpyLow;

    // 1000 / 25 = 40, remainder 0
    bus.write(0x00, 0x4204, 1000 & 0xFF);
    bus.write(0x00, 0x4205, (1000 >> 8) & 0xFF);
    bus.write(0x00, 0x4206, 25);
    const divQuot = bus.read(0x00, 0x4214) | (bus.read(0x00, 0x4215) << 8);

    const passed = mpyResult === 250 && divQuot === 40;
    results.push({
      name: 'Hardware Math Units ($4202-$4206 Multiplier / Divider)',
      passed,
      details: passed
        ? 'Multiplication 25 x 10 = 250, Division 1000 / 25 = 40'
        : `Mpy: ${mpyResult}, Div: ${divQuot}`
    });
  } catch (err) {
    results.push({
      name: 'Hardware Math Units',
      passed: false,
      details: String(err)
    });
  }

  const allPassed = results.every(r => r.passed);
  return { results, allPassed };
}
