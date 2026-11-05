import React, { useState } from 'react';
import { ButtonMask } from '../types';

interface SnesPocketSkinProps {
  onButtonChange: (mask: ButtonMask, pressed: boolean) => void;
  pocketTheme?: 'us-purple' | 'famicom-color' | 'dark-onyx';
}

export const SnesPocketSkin: React.FC<SnesPocketSkinProps> = ({
  onButtonChange,
  pocketTheme = 'us-purple'
}) => {
  const [activeButtons, setActiveButtons] = useState<number>(0);

  const handlePress = (button: ButtonMask) => {
    setActiveButtons(prev => prev | button);
    onButtonChange(button, true);
  };

  const handleRelease = (button: ButtonMask) => {
    setActiveButtons(prev => prev & ~button);
    onButtonChange(button, false);
  };

  const isPressed = (button: ButtonMask) => (activeButtons & button) !== 0;

  // Colors based on theme
  const getButtonStyles = (btn: 'Y' | 'X' | 'B' | 'A') => {
    if (pocketTheme === 'famicom-color') {
      const colors = {
        Y: { bg: 'from-green-500 to-green-700', border: 'border-green-400/50', text: 'text-white' },
        X: { bg: 'from-blue-500 to-blue-700', border: 'border-blue-400/50', text: 'text-white' },
        B: { bg: 'from-amber-400 to-amber-600', border: 'border-amber-300/50', text: 'text-white' },
        A: { bg: 'from-red-500 to-red-700', border: 'border-red-400/50', text: 'text-white' }
      };
      return colors[btn];
    }

    if (pocketTheme === 'dark-onyx') {
      return {
        bg: 'from-zinc-700 to-zinc-900',
        border: 'border-zinc-500/30',
        text: 'text-zinc-300'
      };
    }

    // Default: US SNES Purple & Lavender
    // X and Y are lighter lavender/concave, A and B are dark purple/convex
    if (btn === 'X' || btn === 'Y') {
      return {
        bg: 'from-[#9B8FC7] to-[#7E70B0]',
        border: 'border-[#B4A7E0]/60',
        text: 'text-[#2D234A]'
      };
    }
    return {
      bg: 'from-[#554082] to-[#3B2961]',
      border: 'border-[#6F55A8]/60',
      text: 'text-[#D8CEFA]'
    };
  };

  return (
    <div className="w-full max-w-xl mx-auto select-none touch-none">
      {/* Shoulder Triggers (L and R) */}
      <div className="flex justify-between items-center px-4 mb-2">
        <button
          type="button"
          onPointerDown={() => handlePress(ButtonMask.L)}
          onPointerUp={() => handleRelease(ButtonMask.L)}
          onPointerLeave={() => handleRelease(ButtonMask.L)}
          className={`h-11 px-7 rounded-t-xl text-xs font-black tracking-wider uppercase transition-all shadow-md active:translate-y-0.5 border-t border-x border-white/20 ${
            isPressed(ButtonMask.L)
              ? 'bg-zinc-600 text-purple-300 shadow-inner'
              : 'bg-gradient-to-b from-zinc-700 to-zinc-800 text-zinc-300'
          }`}
        >
          L TRIGGER
        </button>

        <div className="flex items-center gap-1.5 opacity-60">
          <span className="w-2 h-2 rounded-full bg-red-500 shadow-xs" />
          <span className="text-[10px] font-mono uppercase tracking-widest text-zinc-400">
            Pocket Snes Deck
          </span>
        </div>

        <button
          type="button"
          onPointerDown={() => handlePress(ButtonMask.R)}
          onPointerUp={() => handleRelease(ButtonMask.R)}
          onPointerLeave={() => handleRelease(ButtonMask.R)}
          className={`h-11 px-7 rounded-t-xl text-xs font-black tracking-wider uppercase transition-all shadow-md active:translate-y-0.5 border-t border-x border-white/20 ${
            isPressed(ButtonMask.R)
              ? 'bg-zinc-600 text-purple-300 shadow-inner'
              : 'bg-gradient-to-b from-zinc-700 to-zinc-800 text-zinc-300'
          }`}
        >
          R TRIGGER
        </button>
      </div>

      {/* Main Handheld Chassis Panel */}
      <div className="bg-gradient-to-b from-zinc-800 via-zinc-850 to-zinc-900 border border-zinc-700/80 rounded-3xl p-5 shadow-2xl relative overflow-hidden">
        {/* Subtle decorative grooves */}
        <div className="absolute top-2 left-6 right-6 flex justify-between opacity-30 pointer-events-none">
          <div className="flex gap-1">
            <div className="w-12 h-1 bg-zinc-500 rounded-full" />
            <div className="w-6 h-1 bg-zinc-500 rounded-full" />
          </div>
          <div className="flex gap-1">
            <div className="w-6 h-1 bg-zinc-500 rounded-full" />
            <div className="w-12 h-1 bg-zinc-500 rounded-full" />
          </div>
        </div>

        <div className="flex items-center justify-between mt-2">
          {/* D-PAD CLUSTER */}
          <div className="relative w-36 h-36 flex items-center justify-center">
            {/* Recessed Circular Bezel */}
            <div className="absolute inset-0 rounded-full bg-zinc-900/90 shadow-inner border border-zinc-700/50" />

            {/* D-Pad Cross Body */}
            <div className="relative w-32 h-32 flex items-center justify-center">
              {/* Up Button */}
              <button
                type="button"
                onPointerDown={() => handlePress(ButtonMask.Up)}
                onPointerUp={() => handleRelease(ButtonMask.Up)}
                onPointerLeave={() => handleRelease(ButtonMask.Up)}
                className={`absolute top-0 w-11 h-12 rounded-t-md flex items-center justify-center transition-all ${
                  isPressed(ButtonMask.Up)
                    ? 'bg-zinc-600 shadow-inner translate-y-0.5'
                    : 'bg-gradient-to-b from-zinc-750 to-zinc-800 shadow-md border-t border-zinc-600/40'
                }`}
                aria-label="Up"
              >
                <div className="w-0 h-0 border-x-4 border-x-transparent border-b-6 border-b-zinc-400/80" />
              </button>

              {/* Down Button */}
              <button
                type="button"
                onPointerDown={() => handlePress(ButtonMask.Down)}
                onPointerUp={() => handleRelease(ButtonMask.Down)}
                onPointerLeave={() => handleRelease(ButtonMask.Down)}
                className={`absolute bottom-0 w-11 h-12 rounded-b-md flex items-center justify-center transition-all ${
                  isPressed(ButtonMask.Down)
                    ? 'bg-zinc-600 shadow-inner -translate-y-0.5'
                    : 'bg-gradient-to-t from-zinc-750 to-zinc-800 shadow-md border-b border-zinc-900'
                }`}
                aria-label="Down"
              >
                <div className="w-0 h-0 border-x-4 border-x-transparent border-t-6 border-t-zinc-400/80" />
              </button>

              {/* Left Button */}
              <button
                type="button"
                onPointerDown={() => handlePress(ButtonMask.Left)}
                onPointerUp={() => handleRelease(ButtonMask.Left)}
                onPointerLeave={() => handleRelease(ButtonMask.Left)}
                className={`absolute left-0 h-11 w-12 rounded-l-md flex items-center justify-center transition-all ${
                  isPressed(ButtonMask.Left)
                    ? 'bg-zinc-600 shadow-inner translate-x-0.5'
                    : 'bg-gradient-to-r from-zinc-750 to-zinc-800 shadow-md border-l border-zinc-600/40'
                }`}
                aria-label="Left"
              >
                <div className="w-0 h-0 border-y-4 border-y-transparent border-r-6 border-r-zinc-400/80" />
              </button>

              {/* Right Button */}
              <button
                type="button"
                onPointerDown={() => handlePress(ButtonMask.Right)}
                onPointerUp={() => handleRelease(ButtonMask.Right)}
                onPointerLeave={() => handleRelease(ButtonMask.Right)}
                className={`absolute right-0 h-11 w-12 rounded-r-md flex items-center justify-center transition-all ${
                  isPressed(ButtonMask.Right)
                    ? 'bg-zinc-600 shadow-inner -translate-x-0.5'
                    : 'bg-gradient-to-l from-zinc-750 to-zinc-800 shadow-md border-r border-zinc-900'
                }`}
                aria-label="Right"
              >
                <div className="w-0 h-0 border-y-4 border-y-transparent border-l-6 border-l-zinc-400/80" />
              </button>

              {/* Center Pivot Dimple */}
              <div className="w-7 h-7 rounded-full bg-zinc-800 border border-zinc-700/60 shadow-inner pointer-events-none flex items-center justify-center">
                <div className="w-3 h-3 rounded-full bg-zinc-900/80" />
              </div>
            </div>
          </div>

          {/* CENTER: SELECT & START PILLS */}
          <div className="flex flex-col items-center justify-center gap-3">
            <div className="flex gap-4">
              {/* Select */}
              <div className="flex flex-col items-center">
                <button
                  type="button"
                  onPointerDown={() => handlePress(ButtonMask.Select)}
                  onPointerUp={() => handleRelease(ButtonMask.Select)}
                  onPointerLeave={() => handleRelease(ButtonMask.Select)}
                  className={`w-12 h-4.5 rounded-full transform -rotate-25 shadow-md transition-all ${
                    isPressed(ButtonMask.Select)
                      ? 'bg-zinc-500 scale-95 shadow-inner'
                      : 'bg-gradient-to-b from-zinc-600 to-zinc-750 border-t border-white/20'
                  }`}
                  aria-label="Select"
                />
                <span className="text-[9px] font-black tracking-widest text-zinc-400 uppercase mt-2 font-mono">
                  SELECT
                </span>
              </div>

              {/* Start */}
              <div className="flex flex-col items-center">
                <button
                  type="button"
                  onPointerDown={() => handlePress(ButtonMask.Start)}
                  onPointerUp={() => handleRelease(ButtonMask.Start)}
                  onPointerLeave={() => handleRelease(ButtonMask.Start)}
                  className={`w-12 h-4.5 rounded-full transform -rotate-25 shadow-md transition-all ${
                    isPressed(ButtonMask.Start)
                      ? 'bg-zinc-500 scale-95 shadow-inner'
                      : 'bg-gradient-to-b from-zinc-600 to-zinc-750 border-t border-white/20'
                  }`}
                  aria-label="Start"
                />
                <span className="text-[9px] font-black tracking-widest text-zinc-400 uppercase mt-2 font-mono">
                  START
                </span>
              </div>
            </div>
          </div>

          {/* ACTION BUTTONS (X, Y, A, B) */}
          {/* Angled at -12 degrees matching official SNES hardware and our fixed Swift skin */}
          <div className="relative w-36 h-36 flex items-center justify-center transform -rotate-12">
            {/* Darker recessed diamond background well */}
            <div className="absolute inset-1 rounded-3xl bg-zinc-900/60 shadow-inner border border-zinc-700/40" />

            {/* X Button (Top) - Concave */}
            <div className="absolute top-1 flex flex-col items-center">
              <button
                type="button"
                onPointerDown={() => handlePress(ButtonMask.X)}
                onPointerUp={() => handleRelease(ButtonMask.X)}
                onPointerLeave={() => handleRelease(ButtonMask.X)}
                className={`w-11 h-11 rounded-full flex items-center justify-center shadow-lg transition-transform border ${
                  getButtonStyles('X').border
                } ${
                  isPressed(ButtonMask.X)
                    ? 'scale-90 shadow-inner brightness-90'
                    : 'bg-gradient-to-b ' + getButtonStyles('X').bg
                }`}
                aria-label="X Button"
              >
                {/* Concave inner dish styling */}
                <div className="w-8 h-8 rounded-full bg-black/15 shadow-inner flex items-center justify-center">
                  <span className={`text-sm font-black font-mono ${getButtonStyles('X').text}`}>
                    X
                  </span>
                </div>
              </button>
            </div>

            {/* Y Button (Left) - Concave */}
            <div className="absolute left-1 flex items-center">
              <button
                type="button"
                onPointerDown={() => handlePress(ButtonMask.Y)}
                onPointerUp={() => handleRelease(ButtonMask.Y)}
                onPointerLeave={() => handleRelease(ButtonMask.Y)}
                className={`w-11 h-11 rounded-full flex items-center justify-center shadow-lg transition-transform border ${
                  getButtonStyles('Y').border
                } ${
                  isPressed(ButtonMask.Y)
                    ? 'scale-90 shadow-inner brightness-90'
                    : 'bg-gradient-to-b ' + getButtonStyles('Y').bg
                }`}
                aria-label="Y Button"
              >
                {/* Concave inner dish styling */}
                <div className="w-8 h-8 rounded-full bg-black/15 shadow-inner flex items-center justify-center">
                  <span className={`text-sm font-black font-mono ${getButtonStyles('Y').text}`}>
                    Y
                  </span>
                </div>
              </button>
            </div>

            {/* A Button (Right) - Convex */}
            <div className="absolute right-1 flex items-center">
              <button
                type="button"
                onPointerDown={() => handlePress(ButtonMask.A)}
                onPointerUp={() => handleRelease(ButtonMask.A)}
                onPointerLeave={() => handleRelease(ButtonMask.A)}
                className={`w-11 h-11 rounded-full flex items-center justify-center shadow-lg transition-transform border ${
                  getButtonStyles('A').border
                } ${
                  isPressed(ButtonMask.A)
                    ? 'scale-90 shadow-inner brightness-90'
                    : 'bg-gradient-to-b ' + getButtonStyles('A').bg
                }`}
                aria-label="A Button"
              >
                {/* Convex domed styling */}
                <span className={`text-sm font-black font-mono drop-shadow-sm ${getButtonStyles('A').text}`}>
                  A
                </span>
              </button>
            </div>

            {/* B Button (Bottom) - Convex */}
            <div className="absolute bottom-1 flex flex-col items-center">
              <button
                type="button"
                onPointerDown={() => handlePress(ButtonMask.B)}
                onPointerUp={() => handleRelease(ButtonMask.B)}
                onPointerLeave={() => handleRelease(ButtonMask.B)}
                className={`w-11 h-11 rounded-full flex items-center justify-center shadow-lg transition-transform border ${
                  getButtonStyles('B').border
                } ${
                  isPressed(ButtonMask.B)
                    ? 'scale-90 shadow-inner brightness-90'
                    : 'bg-gradient-to-b ' + getButtonStyles('B').bg
                }`}
                aria-label="B Button"
              >
                {/* Convex domed styling */}
                <span className={`text-sm font-black font-mono drop-shadow-sm ${getButtonStyles('B').text}`}>
                  B
                </span>
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
