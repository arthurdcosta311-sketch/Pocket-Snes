//
//  EmulatorSession.swift
//  Pocket Snes
//
//  Owns the running console: a background thread that advances the core once
//  per video frame, publishes the picture, and turns pad presses into the
//  core's controller state. The interface only ever talks to this type.
//

import Foundation
import SwiftUI
import CoreGraphics

enum EmulatorStatus: Equatable {
    case idle
    case unavailable
    case running
    case paused
    case failed(String)
}

final class EmulatorSession: ObservableObject {

    @Published private(set) var image: CGImage?
    @Published private(set) var status: EmulatorStatus = .idle
    @Published private(set) var fps: Int = 0

    let audio = AudioOutput()

    /// One run of the console. Stopping invalidates the token, so a thread that
    /// is still finishing a frame cannot publish over a newer session.
    private final class RunToken {
        private let lock = NSLock()
        private var active = true

        func stop() {
            lock.lock()
            active = false
            lock.unlock()
        }

        var isActive: Bool {
            lock.lock()
            defer { lock.unlock() }
            return active
        }
    }

    private let coreLock = NSLock()
    private let inputLock = NSLock()
    private let stateLock = NSLock()

    private var core: SNESCore?
    private var token: RunToken?
    private var isPaused = false
    private var inputState = SNESInput()

    deinit {
        token?.stop()
        audio.stop()
    }

    // MARK: - Lifecycle

    /// - Parameters:
    ///   - rom: the cartridge image to boot.
    ///   - prepare: a chance to touch the freshly built core before the frame
    ///     thread starts.
    func start(rom: [UInt8], prepare: ((SNESCore) -> Void)? = nil) {
        stop()

        let newCore = SNESCore(romData: rom)
        let newToken = RunToken()
        prepare?(newCore)

        coreLock.lock()
        core = newCore
        coreLock.unlock()

        stateLock.lock()
        token = newToken
        isPaused = false
        stateLock.unlock()

        inputLock.lock()
        inputState = SNESInput()
        inputLock.unlock()

        image = nil
        fps = 0
        status = .running

        audio.apu = newCore.bus.apu
        audio.start()

        let worker = Thread { [weak self] in
            self?.run(core: newCore, token: newToken)
        }
        worker.name = "PocketSnes.Emulator"
        worker.qualityOfService = .userInteractive
        worker.start()
    }

    /// The title has no ROM attached, so there is nothing to boot.
    func markUnavailable() {
        stop()
        status = .unavailable
    }

    func stop() {
        stateLock.lock()
        let live = token
        token = nil
        stateLock.unlock()

        live?.stop()
        audio.stop()

        coreLock.lock()
        core = nil
        coreLock.unlock()

        if status != .unavailable {
            status = .idle
        }
    }

    func pause() {
        guard status == .running else { return }
        stateLock.lock()
        isPaused = true
        stateLock.unlock()
        audio.stop()
        status = .paused
    }

    func resume() {
        guard status == .paused else { return }
        stateLock.lock()
        isPaused = false
        stateLock.unlock()
        audio.start()
        status = .running
    }

    // MARK: - Frame loop

    private var pausedNow: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isPaused
    }

    private func isCurrent(_ candidate: RunToken) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return token === candidate
    }

    private func run(core: SNESCore, token: RunToken) {
        let frameDuration = 1.0 / 60.0
        var framesInWindow = 0
        var windowStart = CFAbsoluteTimeGetCurrent()

        while token.isActive {
            if pausedNow {
                Thread.sleep(forTimeInterval: 0.03)
                continue
            }

            let started = CFAbsoluteTimeGetCurrent()

            inputLock.lock()
            let input = inputState
            inputLock.unlock()

            coreLock.lock()
            core.input = input
            core.runFrame()
            let pixels = core.frame
            coreLock.unlock()

            if let frame = FrameRenderer.image(from: pixels) {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isCurrent(token) else { return }
                    self.image = frame
                }
            }

            framesInWindow += 1
            let now = CFAbsoluteTimeGetCurrent()
            if now - windowStart >= 1 {
                let measured = Int((Double(framesInWindow) / (now - windowStart)).rounded())
                windowStart = now
                framesInWindow = 0
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isCurrent(token) else { return }
                    self.fps = measured
                }
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - started
            if elapsed < frameDuration {
                Thread.sleep(forTimeInterval: frameDuration - elapsed)
            }
        }
    }

    // MARK: - Input

    func setButton(_ pad: PadInput, pressed: Bool) {
        inputLock.lock()
        switch pad {
        case .up: inputState.up = pressed
        case .down: inputState.down = pressed
        case .left: inputState.left = pressed
        case .right: inputState.right = pressed
        case .a: inputState.a = pressed
        case .b: inputState.b = pressed
        case .x: inputState.x = pressed
        case .y: inputState.y = pressed
        case .l: inputState.l = pressed
        case .r: inputState.r = pressed
        case .start: inputState.start = pressed
        case .select: inputState.select = pressed
        }
        inputLock.unlock()
    }

    func releaseAllButtons() {
        inputLock.lock()
        inputState = SNESInput()
        inputLock.unlock()
    }

    // MARK: - Save states

    func captureState() -> Data? {
        coreLock.lock()
        defer { coreLock.unlock() }
        return core?.captureState()
    }

    func restoreState(_ data: Data) -> Bool {
        coreLock.lock()
        defer { coreLock.unlock() }
        return core?.restoreState(data) ?? false
    }

    // MARK: - Settings

    func applyAudioSettings(volume: Double, muted: Bool) {
        audio.volume = Float(volume)
        audio.muted = muted
    }
}
