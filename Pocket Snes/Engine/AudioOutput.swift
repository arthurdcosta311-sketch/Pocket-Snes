//
//  AudioOutput.swift
//  Pocket Snes
//
//  The sound stage: an AVAudioEngine source node pulling samples from the APU
//  at the console's own rate, with the app's volume and mute applied on the
//  mixer. The S-SMP/S-DSP still have to be written, so the APU hands over
//  silence for now and this stage plays it without a glitch.
//

import Foundation
import AVFoundation

final class AudioOutput {

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var running = false

    private let sampleRate: Double = 32000

    /// The APU whose samples are played. Weak so a torn-down core cannot keep
    /// the audio stage alive.
    weak var apu: APU?

    var volume: Float = 0.8 {
        didSet { applyVolume() }
    }

    var muted: Bool = false {
        didSet { applyVolume() }
    }

    func start() {
        guard !running else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            if sourceNode == nil {
                installSourceNode()
            }
            engine.prepare()
            try engine.start()
            running = true
            applyVolume()
        } catch {
            running = false
        }
    }

    func stop() {
        guard running else { return }
        engine.stop()
        running = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func applyVolume() {
        engine.mainMixerNode.outputVolume = muted ? 0 : max(0, min(1, volume))
    }

    private func installSourceNode() {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            return
        }

        let node = AVAudioSourceNode(format: format) { [weak self] _, _, _, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let first = buffers.first, let raw = first.mData else { return noErr }

            let count = Int(first.mDataByteSize) / MemoryLayout<Float>.size
            guard count > 0 else { return noErr }

            // The synth is mono: render once, then copy across the channels so
            // the picture's sound stays centred and in phase.
            let samples = raw.bindMemory(to: Float.self, capacity: count)
            self?.apu?.render(into: samples, count: count)

            for index in 1..<buffers.count {
                guard let other = buffers[index].mData else { continue }
                other.copyMemory(from: raw, byteCount: Int(buffers[index].mDataByteSize))
            }

            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        sourceNode = node
    }
}
