export class APU {
  cpuPorts: number[] = [0, 0, 0, 0];
  handshake: number[] = [0xaa, 0xbb, 0x0f, 0xbb];

  private audioCtx: AudioContext | null = null;
  private osc: OscillatorNode | null = null;
  private gainNode: GainNode | null = null;

  volume: number = 0.8;
  muted: boolean = false;

  private pendingNote: number = 0;
  private pendingVolume: number = 0;
  private pendingWaveform: number = 0;

  constructor() {
    // AudioContext will be initialized on user interaction
  }

  private initAudio() {
    if (this.audioCtx) return;
    try {
      const AudioCtxClass = window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
      if (AudioCtxClass) {
        this.audioCtx = new AudioCtxClass();
        this.gainNode = this.audioCtx.createGain();
        this.gainNode.gain.value = this.muted ? 0 : this.volume * 0.15;
        this.gainNode.connect(this.audioCtx.destination);
      }
    } catch {
      // Audio context may not be allowed until user gesture
    }
  }

  setVolume(vol: number) {
    this.volume = Math.max(0, Math.min(1, vol));
    if (this.gainNode && this.audioCtx) {
      this.gainNode.gain.setValueAtTime(
        this.muted ? 0 : this.volume * 0.15,
        this.audioCtx.currentTime
      );
    }
  }

  setMuted(m: boolean) {
    this.muted = m;
    if (this.gainNode && this.audioCtx) {
      this.gainNode.gain.setValueAtTime(
        this.muted ? 0 : this.volume * 0.15,
        this.audioCtx.currentTime
      );
    }
  }

  write(port: number, value: number) {
    if (port < 0 || port > 3) return;
    this.cpuPorts[port] = value;

    switch (port) {
      case 0:
        this.handshake[0] = value;
        if (value === 0xa5) {
          this.playNote(this.pendingNote, this.pendingVolume, this.pendingWaveform);
        } else if (value === 0x5a) {
          this.stopNote();
        }
        break;
      case 1:
        this.pendingNote = value;
        this.handshake[1] = value;
        break;
      case 2:
        this.pendingVolume = value;
        this.handshake[2] = value;
        break;
      case 3:
        this.pendingWaveform = value;
        this.handshake[3] = value;
        break;
    }
  }

  read(port: number): number {
    if (port >= 0 && port < 4) {
      return this.handshake[port];
    }
    return 0xbb;
  }

  private playNote(note: number, vol: number, wave: number) {
    this.initAudio();
    if (!this.audioCtx || !this.gainNode) return;

    if (this.audioCtx.state === 'suspended') {
      this.audioCtx.resume();
    }

    // Convert MIDI-like note or pitch byte to frequency (A4 = 440Hz, note 69)
    const freq = 440 * Math.pow(2, ((note % 88) - 49) / 12);

    if (this.osc) {
      try {
        this.osc.stop();
        this.osc.disconnect();
      } catch {
        // Ignored
      }
    }

    try {
      this.osc = this.audioCtx.createOscillator();
      const waveTypes: OscillatorType[] = ['square', 'sawtooth', 'triangle', 'square'];
      this.osc.type = waveTypes[wave % 4];
      this.osc.frequency.setValueAtTime(freq, this.audioCtx.currentTime);

      const level = (vol / 255) * (this.muted ? 0 : this.volume * 0.15);
      this.gainNode.gain.setValueAtTime(level, this.audioCtx.currentTime);

      this.osc.connect(this.gainNode);
      this.osc.start();
    } catch {
      // Audio node failure
    }
  }

  private stopNote() {
    if (this.osc) {
      try {
        this.osc.stop();
        this.osc.disconnect();
      } catch {
        // Ignored
      }
      this.osc = null;
    }
  }

  reset() {
    this.cpuPorts = [0, 0, 0, 0];
    this.handshake = [0xaa, 0xbb, 0x0f, 0xbb];
    this.stopNote();
  }

  step(_cycles: number) {
    // APU / DSP sample generation step
  }

  getAudioBuffer(): Float32Array {
    return new Float32Array(0);
  }
}
