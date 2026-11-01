//
//  PocketSynth.swift
//  Pocket Snes
//
//  The sound unit behind APU.swift. A full S-SMP/S-DSP pair is a long way off,
//  so the console's four APU ports drive a small tone generator instead: the
//  cartridge writes a note, a level and a waveform, and the audio output plays
//  it. Commercial ROMs, which expect the real DSP, stay silent.
//

import Foundation

final class PocketSynth {

    struct Voice {
        var frequency: Double = 0
        var level: Float = 0
        var waveform: Int = 0
        var generation: UInt32 = 0
    }

    private let lock = NSLock()
    private var voice = Voice()

    /// Starts a note from a MIDI note number, a 0-127 level and a waveform.
    func note(on midiNote: UInt8, volume: UInt8, waveform: UInt8) {
        lock.lock()
        defer { lock.unlock() }

        voice.frequency = 440.0 * pow(2.0, (Double(min(midiNote, 127)) - 69.0) / 12.0)
        voice.level = Float(min(volume, 127)) / 127.0
        voice.waveform = Int(waveform & 0x03)
        voice.generation &+= 1
    }

    func silence() {
        lock.lock()
        defer { lock.unlock() }

        voice.level = 0
    }

    /// Read by the audio render callback.
    func current() -> Voice {
        lock.lock()
        defer { lock.unlock() }
        return voice
    }
}
