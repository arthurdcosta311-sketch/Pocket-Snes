import React, { useState } from 'react';
import { X, Keyboard, Smartphone, GitBranch, Sliders } from 'lucide-react';

interface SettingsModalProps {
  isOpen: boolean;
  onClose: () => void;
  pocketTheme: 'us-purple' | 'famicom-color' | 'dark-onyx';
  onThemeChange: (theme: 'us-purple' | 'famicom-color' | 'dark-onyx') => void;
}

export const SettingsModal: React.FC<SettingsModalProps> = ({
  isOpen,
  onClose,
  pocketTheme,
  onThemeChange
}) => {
  const [tab, setTab] = useState<'skin' | 'keys' | 'github'>('skin');

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-sm animate-fade-in">
      <div className="relative w-full max-w-lg bg-zinc-900 border border-zinc-700 rounded-2xl shadow-2xl overflow-hidden flex flex-col max-h-[85vh]">
        {/* Header */}
        <div className="flex items-center justify-between p-4 border-b border-zinc-800 bg-zinc-850">
          <div className="flex items-center gap-2">
            <Sliders size={18} className="text-purple-400" />
            <h2 className="text-sm font-bold text-white uppercase tracking-wider">
              Settings & Preferences
            </h2>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="p-1.5 rounded-lg hover:bg-zinc-800 text-zinc-400 hover:text-white transition-colors"
          >
            <X size={18} />
          </button>
        </div>

        {/* Tab Navigation */}
        <div className="flex border-b border-zinc-800 bg-zinc-950 px-3 pt-2 gap-1">
          <button
            type="button"
            onClick={() => setTab('skin')}
            className={`flex items-center gap-1.5 px-3 py-2 text-xs font-semibold rounded-t-lg transition-colors border-t-2 ${
              tab === 'skin'
                ? 'bg-zinc-900 text-purple-400 border-purple-500'
                : 'text-zinc-400 border-transparent hover:text-zinc-200'
            }`}
          >
            <Smartphone size={14} />
            Pocket Skin
          </button>

          <button
            type="button"
            onClick={() => setTab('keys')}
            className={`flex items-center gap-1.5 px-3 py-2 text-xs font-semibold rounded-t-lg transition-colors border-t-2 ${
              tab === 'keys'
                ? 'bg-zinc-900 text-purple-400 border-purple-500'
                : 'text-zinc-400 border-transparent hover:text-zinc-200'
            }`}
          >
            <Keyboard size={14} />
            Key Bindings
          </button>

          <button
            type="button"
            onClick={() => setTab('github')}
            className={`flex items-center gap-1.5 px-3 py-2 text-xs font-semibold rounded-t-lg transition-colors border-t-2 ${
              tab === 'github'
                ? 'bg-zinc-900 text-purple-400 border-purple-500'
                : 'text-zinc-400 border-transparent hover:text-zinc-200'
            }`}
          >
            <GitBranch size={14} />
            GitHub IPA Build
          </button>
        </div>

        {/* Tab Body */}
        <div className="p-4 overflow-y-auto flex-1 text-xs text-zinc-300">
          {tab === 'skin' && (
            <div className="space-y-4">
              <div>
                <label className="block text-xs font-bold text-zinc-200 uppercase tracking-wide mb-2">
                  Pocket Controller Deck Style
                </label>
                <div className="grid grid-cols-1 gap-2.5">
                  {/* Option 1: US Purple */}
                  <label
                    onClick={() => onThemeChange('us-purple')}
                    className={`flex items-center justify-between p-3 rounded-xl border cursor-pointer transition-all ${
                      pocketTheme === 'us-purple'
                        ? 'bg-purple-950/40 border-purple-500/80 ring-1 ring-purple-500'
                        : 'bg-zinc-950/40 border-zinc-800 hover:border-zinc-700'
                    }`}
                  >
                    <div className="flex items-center gap-3">
                      <div className="flex gap-1 items-center">
                        <span className="w-4 h-4 rounded-full bg-[#9B8FC7] shadow-inner" />
                        <span className="w-4 h-4 rounded-full bg-[#554082] shadow-inner" />
                      </div>
                      <div>
                        <p className="font-bold text-zinc-100">North American SNES (Purple / Lavender)</p>
                        <p className="text-[11px] text-zinc-400">Concave X/Y dish and convex A/B dome</p>
                      </div>
                    </div>
                    <input
                      type="radio"
                      name="theme"
                      checked={pocketTheme === 'us-purple'}
                      onChange={() => onThemeChange('us-purple')}
                      className="accent-purple-500"
                    />
                  </label>

                  {/* Option 2: Super Famicom 4-Color */}
                  <label
                    onClick={() => onThemeChange('famicom-color')}
                    className={`flex items-center justify-between p-3 rounded-xl border cursor-pointer transition-all ${
                      pocketTheme === 'famicom-color'
                        ? 'bg-purple-950/40 border-purple-500/80 ring-1 ring-purple-500'
                        : 'bg-zinc-950/40 border-zinc-800 hover:border-zinc-700'
                    }`}
                  >
                    <div className="flex items-center gap-3">
                      <div className="flex gap-1 items-center">
                        <span className="w-3 h-3 rounded-full bg-blue-500" />
                        <span className="w-3 h-3 rounded-full bg-green-500" />
                        <span className="w-3 h-3 rounded-full bg-yellow-400" />
                        <span className="w-3 h-3 rounded-full bg-red-500" />
                      </div>
                      <div>
                        <p className="font-bold text-zinc-100">Super Famicom / PAL (Four Colors)</p>
                        <p className="text-[11px] text-zinc-400">Classic European & Japanese quad-color layout</p>
                      </div>
                    </div>
                    <input
                      type="radio"
                      name="theme"
                      checked={pocketTheme === 'famicom-color'}
                      onChange={() => onThemeChange('famicom-color')}
                      className="accent-purple-500"
                    />
                  </label>

                  {/* Option 3: Dark Onyx */}
                  <label
                    onClick={() => onThemeChange('dark-onyx')}
                    className={`flex items-center justify-between p-3 rounded-xl border cursor-pointer transition-all ${
                      pocketTheme === 'dark-onyx'
                        ? 'bg-purple-950/40 border-purple-500/80 ring-1 ring-purple-500'
                        : 'bg-zinc-950/40 border-zinc-800 hover:border-zinc-700'
                    }`}
                  >
                    <div className="flex items-center gap-3">
                      <div className="flex gap-1 items-center">
                        <span className="w-4 h-4 rounded-full bg-zinc-600" />
                        <span className="w-4 h-4 rounded-full bg-zinc-800" />
                      </div>
                      <div>
                        <p className="font-bold text-zinc-100">Dark Onyx Stealth</p>
                        <p className="text-[11px] text-zinc-400">Minimalist modern matte dark gray</p>
                      </div>
                    </div>
                    <input
                      type="radio"
                      name="theme"
                      checked={pocketTheme === 'dark-onyx'}
                      onChange={() => onThemeChange('dark-onyx')}
                      className="accent-purple-500"
                    />
                  </label>
                </div>
              </div>

              <div className="p-3 rounded-xl bg-zinc-950/50 border border-zinc-800/80 text-[11px] text-zinc-400 space-y-1">
                <p className="font-bold text-zinc-300">Touch Target Optimization</p>
                <p>
                  Each button operates on an isolated circular hit mask with -12° diamond geometry, guaranteeing zero touch interference between buttons.
                </p>
              </div>
            </div>
          )}

          {tab === 'keys' && (
            <div className="space-y-3">
              <p className="text-[11px] text-zinc-400">
                You can use a physical keyboard or game controller in addition to touch controls:
              </p>

              <div className="grid grid-cols-2 gap-2 text-[11px]">
                <div className="flex items-center justify-between p-2 rounded-lg bg-zinc-950/60 border border-zinc-800">
                  <span className="text-zinc-400">D-Pad Up / Down / Left / Right</span>
                  <span className="font-mono font-bold text-purple-300">Arrows / WASD</span>
                </div>

                <div className="flex items-center justify-between p-2 rounded-lg bg-zinc-950/60 border border-zinc-800">
                  <span className="text-zinc-400">B Button</span>
                  <span className="font-mono font-bold text-purple-300">K</span>
                </div>

                <div className="flex items-center justify-between p-2 rounded-lg bg-zinc-950/60 border border-zinc-800">
                  <span className="text-zinc-400">A Button</span>
                  <span className="font-mono font-bold text-purple-300">L</span>
                </div>

                <div className="flex items-center justify-between p-2 rounded-lg bg-zinc-950/60 border border-zinc-800">
                  <span className="text-zinc-400">Y Button</span>
                  <span className="font-mono font-bold text-purple-300">J</span>
                </div>

                <div className="flex items-center justify-between p-2 rounded-lg bg-zinc-950/60 border border-zinc-800">
                  <span className="text-zinc-400">X Button</span>
                  <span className="font-mono font-bold text-purple-300">I</span>
                </div>

                <div className="flex items-center justify-between p-2 rounded-lg bg-zinc-950/60 border border-zinc-800">
                  <span className="text-zinc-400">L Trigger</span>
                  <span className="font-mono font-bold text-purple-300">U</span>
                </div>

                <div className="flex items-center justify-between p-2 rounded-lg bg-zinc-950/60 border border-zinc-800">
                  <span className="text-zinc-400">R Trigger</span>
                  <span className="font-mono font-bold text-purple-300">O</span>
                </div>

                <div className="flex items-center justify-between p-2 rounded-lg bg-zinc-950/60 border border-zinc-800">
                  <span className="text-zinc-400">Select</span>
                  <span className="font-mono font-bold text-purple-300">Shift</span>
                </div>

                <div className="flex items-center justify-between p-2 rounded-lg bg-zinc-950/60 border border-zinc-800">
                  <span className="text-zinc-400">Start</span>
                  <span className="font-mono font-bold text-purple-300">Enter</span>
                </div>
              </div>
            </div>
          )}

          {tab === 'github' && (
            <div className="space-y-3">
              <div className="p-3 rounded-xl bg-purple-950/30 border border-purple-800/40 text-purple-200">
                <p className="font-bold text-xs mb-1">Automated iOS IPA Build Workflow</p>
                <p className="text-[11px] text-purple-300/80 leading-relaxed">
                  The repository includes an automated GitHub Actions workflow at <code className="bg-purple-900/50 px-1 py-0.5 rounded font-mono">.github/workflows/build-ipa.yml</code>. Whenever you push to the <code className="bg-purple-900/50 px-1 py-0.5 rounded font-mono">main</code> branch, GitHub automatically runs Xcode on macOS to compile and produce the unsigned <code className="bg-purple-900/50 px-1 py-0.5 rounded font-mono">Pocket-Snes.ipa</code> file.
                </p>
              </div>

              <div className="p-3 rounded-xl bg-zinc-950/60 border border-zinc-800 space-y-2">
                <p className="font-bold text-zinc-200 text-xs">How to Push and Download Your IPA:</p>
                <ol className="list-decimal list-inside space-y-1.5 text-[11px] text-zinc-400 leading-relaxed">
                  <li>
                    Clone or pull this updated repository to your local terminal:
                    <div className="mt-1 p-2 rounded bg-black/60 font-mono text-[10px] text-purple-300 overflow-x-auto">
                      git pull origin main
                    </div>
                  </li>
                  <li>
                    Push the engine and skin fixes back to your GitHub repository:
                    <div className="mt-1 p-2 rounded bg-black/60 font-mono text-[10px] text-purple-300 overflow-x-auto">
                      git commit -am &quot;Fix SNES CPU/PPU emulation and pocket skin touch hit-boxes&quot;<br />
                      git push origin main
                    </div>
                  </li>
                  <li>
                    Visit your GitHub repository tab <strong>&quot;Actions&quot;</strong> &rarr; <strong>&quot;Build iOS IPA&quot;</strong>.
                  </li>
                  <li>
                    Click on the completed workflow run to download <code className="text-zinc-200">Pocket-Snes-ipa.zip</code> containing the ready-to-sideload IPA!
                  </li>
                </ol>
              </div>
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="p-3 border-t border-zinc-800 bg-zinc-850 flex justify-end">
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-1.5 rounded-lg bg-purple-600 hover:bg-purple-500 text-xs font-semibold text-white transition-colors"
          >
            Done
          </button>
        </div>
      </div>
    </div>
  );
};
