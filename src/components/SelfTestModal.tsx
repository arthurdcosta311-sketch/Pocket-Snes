import React, { useState } from 'react';
import { runEngineSelfTest, TestResult } from '../engine/SelfTest';
import { CheckCircle2, XCircle, Play, X, ShieldCheck } from 'lucide-react';

interface SelfTestModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export const SelfTestModal: React.FC<SelfTestModalProps> = ({ isOpen, onClose }) => {
  const [results, setResults] = useState<TestResult[] | null>(null);
  const [isRunning, setIsRunning] = useState<boolean>(false);

  if (!isOpen) return null;

  const handleRunTests = () => {
    setIsRunning(true);
    setTimeout(() => {
      const outcome = runEngineSelfTest();
      setResults(outcome.results);
      setIsRunning(false);
    }, 200);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-sm animate-fade-in">
      <div className="relative w-full max-w-xl bg-zinc-900 border border-zinc-700 rounded-2xl shadow-2xl overflow-hidden flex flex-col max-h-[85vh]">
        {/* Header */}
        <div className="flex items-center justify-between p-4 border-b border-zinc-800 bg-zinc-850">
          <div className="flex items-center gap-2.5">
            <div className="w-8 h-8 rounded-lg bg-purple-600/20 border border-purple-500/40 flex items-center justify-center text-purple-400">
              <ShieldCheck size={18} />
            </div>
            <div>
              <h2 className="text-sm font-bold text-white uppercase tracking-wider">
                SNES Engine Diagnostics & Self-Test
              </h2>
              <p className="text-[11px] text-zinc-400">
                Validates 65816 CPU opcodes, WRAM ports, VRAM byte order & math units
              </p>
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="p-1.5 rounded-lg hover:bg-zinc-800 text-zinc-400 hover:text-white transition-colors"
          >
            <X size={18} />
          </button>
        </div>

        {/* Content */}
        <div className="p-4 overflow-y-auto flex-1 space-y-3">
          <div className="p-3 rounded-xl bg-zinc-950/60 border border-zinc-800/80 text-xs text-zinc-300">
            <p className="font-semibold text-zinc-200 mb-1">
              Engine Fix Verification Suite
            </p>
            <p className="text-zinc-400 text-[11px] leading-relaxed">
              This self-test verifies the key fixes applied to resolve the real-ROM boot failure:
              16 stack-relative opcodes, WRAM $2180 data port pointer auto-increment, $2116/$2117 VMADD byte ordering, and native interrupt M/X flag preservation.
            </p>
          </div>

          {!results && !isRunning && (
            <div className="py-8 text-center text-zinc-400">
              <p className="text-xs mb-3">Press below to execute real-time engine diagnostics.</p>
              <button
                type="button"
                onClick={handleRunTests}
                className="inline-flex items-center gap-2 px-4 py-2 rounded-xl bg-purple-600 hover:bg-purple-500 text-white font-semibold text-xs transition-colors shadow-lg shadow-purple-600/30"
              >
                <Play size={14} />
                Run Diagnostics
              </button>
            </div>
          )}

          {isRunning && (
            <div className="py-12 text-center text-zinc-400">
              <div className="w-6 h-6 border-2 border-purple-500 border-t-transparent rounded-full animate-spin mx-auto mb-2" />
              <p className="text-xs font-mono">Running 65816 and PPU test vectors...</p>
            </div>
          )}

          {results && (
            <div className="space-y-2.5">
              {results.map((res, i) => (
                <div
                  key={i}
                  className={`p-3 rounded-xl border flex items-start gap-3 ${
                    res.passed
                      ? 'bg-emerald-950/20 border-emerald-800/40 text-emerald-200'
                      : 'bg-rose-950/20 border-rose-800/40 text-rose-200'
                  }`}
                >
                  <div className="mt-0.5">
                    {res.passed ? (
                      <CheckCircle2 size={16} className="text-emerald-400" />
                    ) : (
                      <XCircle size={16} className="text-rose-400" />
                    )}
                  </div>
                  <div className="flex-1">
                    <div className="flex items-center justify-between">
                      <span className="text-xs font-bold">{res.name}</span>
                      <span
                        className={`text-[10px] font-mono px-2 py-0.5 rounded font-bold uppercase ${
                          res.passed
                            ? 'bg-emerald-900/40 text-emerald-300'
                            : 'bg-rose-900/40 text-rose-300'
                        }`}
                      >
                        {res.passed ? 'PASSED' : 'FAILED'}
                      </span>
                    </div>
                    <p className="text-[11px] text-zinc-400 mt-1 leading-snug">
                      {res.details}
                    </p>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="p-3 border-t border-zinc-800 bg-zinc-850 flex items-center justify-between">
          <span className="text-[10px] font-mono text-zinc-500">
            Pocket Snes v1.0.2 • Self-Test Suite
          </span>
          <div className="flex gap-2">
            {results && (
              <button
                type="button"
                onClick={handleRunTests}
                className="px-3 py-1.5 rounded-lg bg-zinc-800 hover:bg-zinc-700 text-xs font-semibold text-zinc-200 transition-colors"
              >
                Re-run
              </button>
            )}
            <button
              type="button"
              onClick={onClose}
              className="px-3 py-1.5 rounded-lg bg-purple-600 hover:bg-purple-500 text-xs font-semibold text-white transition-colors"
            >
              Close
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};
