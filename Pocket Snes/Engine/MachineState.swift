//
//  MachineState.swift
//  Pocket Snes
//
//  Whole-machine save state: CPU, PPU, bus and cartridge SRAM in one blob the
//  player can write to disk and load back later.
//

import Foundation

struct MachineState: Codable {
    var cpu: CPU65816.Snapshot
    var ppu: PPU.Snapshot
    var bus: Bus.Snapshot
    var sram: [UInt8]
}

extension SNESCore {

    /// Encodes the current machine state, or nil when encoding fails.
    func captureState() -> Data? {
        let state = MachineState(
            cpu: cpu.snapshot(),
            ppu: bus.ppu.snapshot(),
            bus: bus.snapshot(),
            sram: cart.sram
        )
        return try? JSONEncoder().encode(state)
    }

    /// Puts the machine back where a previous capture left it.
    @discardableResult
    func restoreState(_ data: Data) -> Bool {
        guard let state = try? JSONDecoder().decode(MachineState.self, from: data) else {
            return false
        }
        cpu.restore(state.cpu)
        bus.ppu.restore(state.ppu)
        bus.restore(state.bus)
        cart.sram = state.sram
        return true
    }
}
