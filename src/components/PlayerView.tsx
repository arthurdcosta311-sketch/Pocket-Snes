import React, { useEffect, useRef, useState, useCallback } from 'react';
import { SNESCore } from '../engine/SNESCore';
import { ButtonMask } from '../types';
import { SnesPocketSkin } from './SnesPocketSkin';
import {
  Play,
  Pause,
  RotateCcw,
  Volume2,
  VolumeX,
  FastForward,
  Maximize2,
  Save,
  Download,
  Sliders,
  ChevronLeft
} from 'lucide-react';

interface PlayerViewProps {
  core: SNESCore;
  romTitle: string;
  onBack: () => void;
  onOpenSettings: () => void;
  pocketTheme: 'us-purple' | 'famicom-color' | 'dark-onyx';
}

export const PlayerView: React.FC<PlayerViewProps> = ({
  core,
  romTitle,
  onBack,
  onOpenSettings,
  pocketTheme
}) => {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const containerRef = useRef<HTMLDivElement | null>(null);
  const [isPlaying, setIsPlaying] = useState<boolean>(true);
  const [speedMultiplier, setSpeedMultiplier] = useState<number>(1);
  const [isAudioEnabled, setIsAudioEnabled] = useState<boolean>(false);
  const [crtEnabled, setCrtEnabled] = useState<boolean>(true);
  const [fps, setFps] = useState<number>(60);
  const [saveStatus, setSaveStatus] = useState<string | null>(null);

  const audioCtxRef = useRef<AudioContext | null>(null);
  const animationFrameRef = useRef<number | null>(null);
  const buttonMaskRef = useRef<number>(0);

  // Initialize Canvas & Screen Loop
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    ctx.imageSmoothingEnabled = false;
    const imgData = ctx.createImageData(256, 224);

    let lastTime = performance.now();

    const loop = (currentTime: number) => {
      if (isPlaying) {
        // Run frame(s) based on speed multiplier
        const framesToRun = speedMultiplier;
        let fb: Uint32Array | null = null;
        for (let i = 0; i < framesToRun; i++) {
          fb = core.runFrame(buttonMaskRef.current);
        }

        if (fb) {
          const imgDataU32 = new Uint32Array(imgData.data.buffer);
          imgDataU32.set(fb);
          ctx.putImageData(imgData, 0, 0);
        }

        if (currentTime - lastTime >= 500) {
          setFps(core.fps);
          lastTime = currentTime;
        }

        // Web Audio Sample streaming if enabled
        if (isAudioEnabled && audioCtxRef.current && audioCtxRef.current.state === 'running') {
          const samples = core.getAudioSamples();
          if (samples.length > 0) {
            const buffer = audioCtxRef.current.createBuffer(1, samples.length, 32000);
            buffer.getChannelData(0).set(samples);
            const source = audioCtxRef.current.createBufferSource();
            source.buffer = buffer;
            source.connect(audioCtxRef.current.destination);
            source.start();
          }
        }
      }

      animationFrameRef.current = requestAnimationFrame(loop);
    };

    animationFrameRef.current = requestAnimationFrame(loop);

    return () => {
      if (animationFrameRef.current) {
        cancelAnimationFrame(animationFrameRef.current);
      }
    };
  }, [core, isPlaying, speedMultiplier, isAudioEnabled]);

  // Audio Context Toggle
  const toggleAudio = async () => {
    if (!audioCtxRef.current) {
      const AudioCtx = window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
      audioCtxRef.current = new AudioCtx({ sampleRate: 32000 });
    }

    if (audioCtxRef.current.state === 'suspended') {
      await audioCtxRef.current.resume();
    }

    setIsAudioEnabled(!isAudioEnabled);
  };

  // Keyboard controls listener
  useEffect(() => {
    const keyMap: Record<string, ButtonMask> = {
      ArrowUp: ButtonMask.Up,
      KeyW: ButtonMask.Up,
      ArrowDown: ButtonMask.Down,
      KeyS: ButtonMask.Down,
      ArrowLeft: ButtonMask.Left,
      KeyA: ButtonMask.Left,
      ArrowRight: ButtonMask.Right,
      KeyD: ButtonMask.Right,
      KeyK: ButtonMask.B,
      KeyL: ButtonMask.A,
      KeyJ: ButtonMask.Y,
      KeyI: ButtonMask.X,
      KeyU: ButtonMask.L,
      KeyO: ButtonMask.R,
      Enter: ButtonMask.Start,
      ShiftRight: ButtonMask.Select,
      ShiftLeft: ButtonMask.Select
    };

    const handleKeyDown = (e: KeyboardEvent) => {
      const mask = keyMap[e.code];
      if (mask) {
        e.preventDefault();
        buttonMaskRef.current |= mask;
      }
    };

    const handleKeyUp = (e: KeyboardEvent) => {
      const mask = keyMap[e.code];
      if (mask) {
        e.preventDefault();
        buttonMaskRef.current &= ~mask;
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    window.addEventListener('keyup', handleKeyUp);

    return () => {
      window.removeEventListener('keydown', handleKeyDown);
      window.removeEventListener('keyup', handleKeyUp);
    };
  }, []);

  const handleButtonChange = useCallback((mask: ButtonMask, pressed: boolean) => {
    if (pressed) {
      buttonMaskRef.current |= mask;
    } else {
      buttonMaskRef.current &= ~mask;
    }
  }, []);

  const handleQuickSave = () => {
    const json = core.saveState();
    localStorage.setItem(`pocket_snes_save_${romTitle}`, json);
    setSaveStatus('Saved State');
    setTimeout(() => setSaveStatus(null), 2000);
  };

  const handleQuickLoad = () => {
    const json = localStorage.getItem(`pocket_snes_save_${romTitle}`);
    if (json) {
      core.loadState(json);
      setSaveStatus('Loaded State');
    } else {
      setSaveStatus('No Save Found');
    }
    setTimeout(() => setSaveStatus(null), 2000);
  };

  const toggleFullscreen = () => {
    if (!document.fullscreenElement) {
      containerRef.current?.requestFullscreen?.();
    } else {
      document.exitFullscreen?.();
    }
  };

  return (
    <div
      ref={containerRef}
      className="flex flex-col min-h-screen bg-zinc-950 text-zinc-100 items-center justify-between p-3 select-none"
    >
      {/* Top Bar / Navigation */}
      <header className="w-full max-w-4xl flex items-center justify-between py-2 px-3 bg-zinc-900/90 border border-zinc-800 rounded-2xl backdrop-blur-md shadow-lg mb-2">
        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={onBack}
            className="flex items-center gap-1 px-2.5 py-1.5 rounded-lg bg-zinc-800 hover:bg-zinc-700 text-xs font-semibold transition-colors"
          >
            <ChevronLeft size={16} />
            Library
          </button>
          <div className="flex flex-col">
            <h1 className="text-sm font-bold truncate max-w-[180px] sm:max-w-xs uppercase tracking-tight">
              {romTitle}
            </h1>
            <div className="flex items-center gap-2 text-[10px] text-zinc-400 font-mono">
              <span className="flex items-center gap-1">
                <span className="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse" />
                {fps} FPS
              </span>
              <span>•</span>
              <span>FRAME {core.totalFrames}</span>
            </div>
          </div>
        </div>

        {/* Action Controls */}
        <div className="flex items-center gap-1.5 sm:gap-2">
          {saveStatus && (
            <span className="text-[10px] font-bold text-amber-400 bg-amber-950/70 border border-amber-600/40 px-2 py-0.5 rounded-md animate-fade-in">
              {saveStatus}
            </span>
          )}

          <button
            type="button"
            onClick={handleQuickSave}
            title="Quick Save"
            className="p-1.5 rounded-lg bg-zinc-800 hover:bg-zinc-700 text-zinc-300 transition-colors"
          >
            <Save size={15} />
          </button>

          <button
            type="button"
            onClick={handleQuickLoad}
            title="Quick Load"
            className="p-1.5 rounded-lg bg-zinc-800 hover:bg-zinc-700 text-zinc-300 transition-colors"
          >
            <Download size={15} />
          </button>

          <button
            type="button"
            onClick={() => setCrtEnabled(!crtEnabled)}
            title="Toggle CRT Scanlines"
            className={`px-2 py-1 rounded-lg text-[10px] font-mono font-bold uppercase transition-colors ${
              crtEnabled
                ? 'bg-purple-600 text-white'
                : 'bg-zinc-800 text-zinc-400 hover:bg-zinc-700'
            }`}
          >
            CRT
          </button>

          <button
            type="button"
            onClick={() => setSpeedMultiplier(prev => (prev === 1 ? 2 : prev === 2 ? 4 : 1))}
            title="Fast Forward Speed"
            className={`flex items-center gap-1 px-2 py-1 rounded-lg text-[10px] font-mono font-bold transition-colors ${
              speedMultiplier > 1
                ? 'bg-amber-600 text-white'
                : 'bg-zinc-800 text-zinc-400 hover:bg-zinc-700'
            }`}
          >
            <FastForward size={13} />
            {speedMultiplier}x
          </button>

          <button
            type="button"
            onClick={toggleAudio}
            title={isAudioEnabled ? 'Mute' : 'Enable Audio'}
            className="p-1.5 rounded-lg bg-zinc-800 hover:bg-zinc-700 text-zinc-300 transition-colors"
          >
            {isAudioEnabled ? <Volume2 size={15} /> : <VolumeX size={15} />}
          </button>

          <button
            type="button"
            onClick={() => setIsPlaying(!isPlaying)}
            title={isPlaying ? 'Pause' : 'Play'}
            className="p-1.5 rounded-lg bg-zinc-800 hover:bg-zinc-700 text-zinc-300 transition-colors"
          >
            {isPlaying ? <Pause size={15} /> : <Play size={15} />}
          </button>

          <button
            type="button"
            onClick={() => core.reset()}
            title="Reset Console"
            className="p-1.5 rounded-lg bg-zinc-800 hover:bg-zinc-700 text-zinc-300 transition-colors"
          >
            <RotateCcw size={15} />
          </button>

          <button
            type="button"
            onClick={onOpenSettings}
            title="Settings & Keymap"
            className="p-1.5 rounded-lg bg-zinc-800 hover:bg-zinc-700 text-zinc-300 transition-colors"
          >
            <Sliders size={15} />
          </button>

          <button
            type="button"
            onClick={toggleFullscreen}
            title="Fullscreen"
            className="p-1.5 rounded-lg bg-zinc-800 hover:bg-zinc-700 text-zinc-300 transition-colors"
          >
            <Maximize2 size={15} />
          </button>
        </div>
      </header>

      {/* Screen Container */}
      <div className="relative flex-1 flex items-center justify-center w-full max-w-2xl min-h-[224px] my-auto">
        <div className="relative rounded-2xl overflow-hidden p-2 bg-gradient-to-b from-zinc-800 to-zinc-900 border-2 border-zinc-700 shadow-[0_12px_40px_rgba(0,0,0,0.8)]">
          {/* CRT Screen Glass Curvature & Glare */}
          <div className="relative overflow-hidden rounded-lg bg-black">
            <canvas
              ref={canvasRef}
              width={256}
              height={224}
              className="w-full max-w-[512px] aspect-[8/7] block pixelated"
            />

            {/* CRT Scanlines Overlay */}
            {crtEnabled && (
              <div
                className="absolute inset-0 pointer-events-none mix-blend-overlay opacity-30"
                style={{
                  backgroundImage:
                    'linear-gradient(rgba(18, 16, 16, 0) 50%, rgba(0, 0, 0, 0.75) 50%)',
                  backgroundSize: '100% 4px'
                }}
              />
            )}

            {/* Subtle glass reflection highlight */}
            <div className="absolute inset-0 pointer-events-none bg-gradient-to-tr from-transparent via-white/5 to-transparent" />
          </div>
        </div>
      </div>

      {/* Handheld Controller Deck */}
      <div className="w-full py-2">
        <SnesPocketSkin
          onButtonChange={handleButtonChange}
          pocketTheme={pocketTheme}
        />
      </div>
    </div>
  );
};
