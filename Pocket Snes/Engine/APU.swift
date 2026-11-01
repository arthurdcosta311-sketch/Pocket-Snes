//
//  APU.swift
//  Pocket Snes
//
//  The sound side of the console. A real S-SMP (SPC700) and S-DSP pair is a
//  project of its own, so this APU is a tone generator driven by the four CPU
//  ports instead: a cartridge loads a pitch, a level and a waveform into
//  $2141-$2143 and commits them on $2140. `AudioOutput` pulls the result
//  through `render(into:count:)`, so the volume and mute settings are audible.
//
//  ROMs written for the real DSP (anything that expects the SPC700 to run a
//  sound driver) still come out silent, which is the honest limit of this core.
//

import Foundation

final class APU {

    /// Last values written by the CPU to ports $2140-$2143.
    private(set) var cpuPorts: [UInt8] = [0, 0, 0, 0]

    /// Latches that the commit byte on port 0 hands to the synth.
    private var pendingNote: UInt8 = 0
    private var pendingVolume: UInt8 = 0
    private var pendingWaveform: UInt8 = 0

    private let synth = PocketSynth()

    /// The console's sample rate; the audio stage opens its format to match.
    static let sampleRate: Double = 32000

    // Oscillator state, touched only by the audio render thread.
    private var phase: Double = 0
    private var envelope: Double = 0
    private var lastGeneration: UInt32 = 0

    // MARK: - CPU ports

    func write(port: Int, value: UInt8) {
        guard cpuPorts.indices.contains(port) else { return }
        cpuPorts[port] = value

        switch port {
        case 0:
            if value == 0xA5 {
                synth.note(on: pendingNote, volume: pendingVolume, waveform: pendingWaveform)
            } else if value == 0x5A {
                synth.silence()
            }
        case 1:
            pendingNote = value
        case 2:
            pendingVolume = value
        case 3:
            pendingWaveform = value
        default:
            break
        }
    }

    func read(port: Int) -> UInt8 {
        // Idle S-SMP handshake values, as seen by the CPU when the SPC700
        // is not running.
        switch port {
        case 0: return 0xAA
        case 1: return 0xBB
        case 2: return 0x0F
        default: return 0xBB
        }
    }

    // MARK: - Output

    /// Fills one buffer of samples for the output stage. Called on the audio
    /// thread.
    func render(into samples: UnsafeMutablePointer<Float>, count: Int) {
        guard count > 0 else { return }

        let voice = synth.current()

        if voice.generation != lastGeneration {
            lastGeneration = voice.generation
            phase = 0
            envelope = 0
        }

        let attackStep = 1.0 / (0.004 * APU.sampleRate)
        let decay: Double = 0.999_995
        let release: Double = 0.9995
        let increment = voice.frequency / APU.sampleRate
        let level = Double(voice.level)

        for index in 0..<count {
            if level > 0 {
                envelope = min(1, envelope + attackStep)
                envelope *= decay
            } else {
                envelope *= release
                if envelope < 0.0005 { envelope = 0 }
            }

            var sample: Double
            switch voice.waveform {
            case 1:                       // saw
                sample = phase * 2 - 1
            case 2:                       // triangle
                sample = phase < 0.5 ? (phase * 4 - 1) : (3 - phase * 4)
            case 3:                       // 25% pulse
                sample = phase < 0.25 ? 1 : -1
            default:                      // square
                sample = phase < 0.5 ? 1 : -1
            }

            sample *= envelope * level * 0.35
            samples[index] = Float(max(-1, min(1, sample)))

            phase += increment
            if phase >= 1 { phase -= 1 }
        }
    }
}
