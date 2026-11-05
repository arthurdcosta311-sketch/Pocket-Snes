import React, { useRef, useState } from 'react';
import { BuiltinROMInfo, BUILTIN_ROMS } from '../engine/SampleROMs';
import { Cartridge } from '../engine/Cartridge';
import { ArtworkCanvas } from './ArtworkCanvas';
import {
  Upload,
  Play,
  Info,
  ShieldCheck,
  Gamepad2,
  HardDrive,
  FileCode,
  Check,
  Sparkles
} from 'lucide-react';

interface UploadedROM {
  id: string;
  title: string;
  fileName: string;
  size: number;
  data: Uint8Array;
  cartridge: Cartridge;
  timestamp: number;
}

interface LibraryViewProps {
  onLaunchROM: (data: Uint8Array, title: string) => void;
  onOpenSelfTest: () => void;
  onOpenSettings: () => void;
}

export const LibraryView: React.FC<LibraryViewProps> = ({
  onLaunchROM,
  onOpenSelfTest,
  onOpenSettings
}) => {
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const [uploadedRoms, setUploadedRoms] = useState<UploadedROM[]>([]);
  const [isDragging, setIsDragging] = useState<boolean>(false);
  const [selectedCartridge, setSelectedCartridge] = useState<{
    cartridge: Cartridge;
    title: string;
    size: number;
  } | null>(null);
  const [uploadError, setUploadError] = useState<string | null>(null);

  const processFile = async (file: File) => {
    setUploadError(null);
    const validExtensions = ['.smc', '.sfc', '.bin', '.snes'];
    const hasValidExt = validExtensions.some(ext =>
      file.name.toLowerCase().endsWith(ext)
    );

    if (!hasValidExt) {
      setUploadError(
        `"${file.name}" has an unrecognized extension. Please provide an authentic SNES ROM (.smc, .sfc, or .bin).`
      );
      return;
    }

    try {
      const buffer = await file.arrayBuffer();
      const bytes = new Uint8Array(buffer);
      const cart = new Cartridge(bytes);

      const newRom: UploadedROM = {
        id: `rom_${Date.now()}_${Math.random().toString(36).substring(2, 6)}`,
        title: cart.title || file.name.replace(/\.[^/.]+$/, ''),
        fileName: file.name,
        size: bytes.length,
        data: bytes,
        cartridge: cart,
        timestamp: Date.now()
      };

      setUploadedRoms(prev => [newRom, ...prev]);
      // Auto launch uploaded ROM
      onLaunchROM(newRom.data, newRom.title);
    } catch (err) {
      setUploadError(`Failed to parse ROM: ${(err as Error).message}`);
    }
  };

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault();
    setIsDragging(false);
    if (e.dataTransfer.files && e.dataTransfer.files.length > 0) {
      processFile(e.dataTransfer.files[0]);
    }
  };

  const handleFileInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files.length > 0) {
      processFile(e.target.files[0]);
    }
  };

  const handleLaunchBuiltin = (rom: BuiltinROMInfo) => {
    const data = rom.generator();
    onLaunchROM(data, rom.title);
  };

  return (
    <div className="min-h-screen bg-zinc-950 text-zinc-100 flex flex-col p-4 sm:p-6 max-w-6xl mx-auto">
      {/* Top Header */}
      <header className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 pb-6 border-b border-zinc-800">
        <div className="flex items-center gap-3">
          <div className="w-11 h-11 rounded-2xl bg-gradient-to-tr from-purple-700 to-indigo-600 flex items-center justify-center shadow-lg shadow-purple-900/30 border border-purple-400/30">
            <Gamepad2 className="text-white" size={24} />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h1 className="text-xl font-black uppercase tracking-tight text-white">
                Pocket Snes
              </h1>
              <span className="text-[10px] font-mono font-bold bg-purple-950 text-purple-300 border border-purple-800/80 px-2 py-0.5 rounded-full">
                SNES 65816 CORE
              </span>
            </div>
            <p className="text-xs text-zinc-400">
              Portable Super Nintendo Entertainment System with real ROM boot & ergonomic pocket deck
            </p>
          </div>
        </div>

        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={onOpenSelfTest}
            className="flex items-center gap-1.5 px-3 py-2 rounded-xl bg-zinc-900 hover:bg-zinc-800 border border-zinc-800 text-xs font-semibold text-emerald-400 transition-colors shadow-sm"
          >
            <ShieldCheck size={16} />
            Diagnostics
          </button>

          <button
            type="button"
            onClick={onOpenSettings}
            className="flex items-center gap-1.5 px-3 py-2 rounded-xl bg-zinc-900 hover:bg-zinc-800 border border-zinc-800 text-xs font-semibold text-zinc-200 transition-colors shadow-sm"
          >
            Preferences
          </button>
        </div>
      </header>

      {/* Main Content Body */}
      <main className="py-6 space-y-8 flex-1">
        {/* ROM Upload / Drag-and-drop Card */}
        <section aria-label="Load SNES ROM Cartridge">
          <div
            onDragOver={e => {
              e.preventDefault();
              setIsDragging(true);
            }}
            onDragLeave={() => setIsDragging(false)}
            onDrop={handleDrop}
            onClick={() => fileInputRef.current?.click()}
            className={`relative rounded-2xl border-2 border-dashed p-6 sm:p-8 text-center cursor-pointer transition-all ${
              isDragging
                ? 'border-purple-500 bg-purple-950/20 scale-[1.01]'
                : 'border-zinc-800 hover:border-zinc-700 bg-zinc-900/50 hover:bg-zinc-900/80'
            }`}
          >
            <input
              ref={fileInputRef}
              type="file"
              accept=".smc,.sfc,.bin,.snes"
              onChange={handleFileInputChange}
              className="hidden"
            />
            <div className="max-w-md mx-auto flex flex-col items-center">
              <div className="w-14 h-14 rounded-full bg-purple-600/10 border border-purple-500/30 flex items-center justify-center text-purple-400 mb-3 shadow-inner">
                <Upload size={24} />
              </div>
              <h2 className="text-base font-bold text-white mb-1">
                Drop your real SNES ROM cartridge here
              </h2>
              <p className="text-xs text-zinc-400 mb-3">
                Supports standard Super Nintendo <span className="text-zinc-200 font-mono">.smc</span>,{' '}
                <span className="text-zinc-200 font-mono">.sfc</span>, and raw cartridge binary files.
                With our 16 stack-relative opcodes and WRAM $2180 port fixes, real ROMs boot smoothly!
              </p>
              <span className="inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-lg bg-purple-600 hover:bg-purple-500 text-white font-semibold text-xs shadow-md transition-colors">
                Browse Files
              </span>
            </div>
          </div>

          {uploadError && (
            <div className="mt-3 p-3 rounded-xl bg-rose-950/40 border border-rose-800/60 text-xs text-rose-300">
              {uploadError}
            </div>
          )}
        </section>

        {/* Uploaded Real ROMs (if any) */}
        {uploadedRoms.length > 0 && (
          <section>
            <div className="flex items-center justify-between mb-3">
              <h2 className="text-sm font-bold text-zinc-200 uppercase tracking-wider flex items-center gap-2">
                <HardDrive size={16} className="text-purple-400" />
                Loaded Cartridges ({uploadedRoms.length})
              </h2>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-4">
              {uploadedRoms.map(rom => (
                <div
                  key={rom.id}
                  className="bg-zinc-900 border border-zinc-800 rounded-2xl p-4 flex flex-col justify-between hover:border-zinc-700 transition-all shadow-md group"
                >
                  <div className="flex items-start gap-3 mb-3">
                    <ArtworkCanvas
                      title={rom.title}
                      genre={rom.cartridge.isHiROM ? 'HiROM Cartridge' : 'LoROM Cartridge'}
                      className="w-24 h-28 shrink-0"
                    />
                    <div className="flex-1 min-w-0">
                      <h3 className="font-bold text-sm text-white truncate uppercase tracking-tight">
                        {rom.title}
                      </h3>
                      <p className="text-[11px] font-mono text-zinc-400 truncate mt-0.5">
                        {rom.fileName}
                      </p>
                      <div className="mt-2 space-y-1 text-[10px] font-mono text-zinc-500">
                        <p>MODE: {rom.cartridge.isHiROM ? 'HiROM' : 'LoROM'}</p>
                        <p>SIZE: {(rom.size / 1024).toFixed(0)} KB</p>
                        <p>RESET: ${rom.cartridge.resetVector.toString(16).toUpperCase()}</p>
                      </div>
                    </div>
                  </div>

                  <div className="flex gap-2 pt-2 border-t border-zinc-800/80">
                    <button
                      type="button"
                      onClick={() => onLaunchROM(rom.data, rom.title)}
                      className="flex-1 flex items-center justify-center gap-1.5 py-1.5 rounded-xl bg-purple-600 hover:bg-purple-500 text-white font-bold text-xs transition-colors shadow-sm"
                    >
                      <Play size={13} />
                      Play
                    </button>
                    <button
                      type="button"
                      onClick={() =>
                        setSelectedCartridge({
                          cartridge: rom.cartridge,
                          title: rom.title,
                          size: rom.size
                        })
                      }
                      title="Inspect Cartridge Header"
                      className="p-1.5 rounded-xl bg-zinc-800 hover:bg-zinc-700 text-zinc-300 transition-colors"
                    >
                      <Info size={15} />
                    </button>
                  </div>
                </div>
              ))}
            </div>
          </section>
        )}

        {/* Built-in Hardware Validation & Demo ROMs */}
        <section>
          <div className="flex items-center justify-between mb-3">
            <div>
              <h2 className="text-sm font-bold text-zinc-200 uppercase tracking-wider flex items-center gap-2">
                <Sparkles size={16} className="text-amber-400" />
                Built-in 65816 Demo & Calibration Cartridges
              </h2>
              <p className="text-xs text-zinc-400">
                Preloaded standalone Super Nintendo ROMs ready to run immediately
              </p>
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            {BUILTIN_ROMS.map(rom => (
              <div
                key={rom.id}
                className="bg-zinc-900 border border-zinc-800 rounded-2xl p-4 flex flex-col justify-between hover:border-zinc-700 transition-all shadow-md group"
              >
                <div>
                  <ArtworkCanvas
                    title={rom.title}
                    genre={rom.genre}
                    year={rom.year}
                    className="w-full h-36 mb-3"
                  />
                  <h3 className="font-bold text-sm text-white group-hover:text-purple-300 transition-colors">
                    {rom.title}
                  </h3>
                  <p className="text-[11px] text-zinc-400 font-mono mt-0.5">
                    {rom.subtitle}
                  </p>
                  <p className="text-xs text-zinc-400 mt-2 leading-relaxed">
                    {rom.description}
                  </p>
                </div>

                <div className="mt-4 pt-3 border-t border-zinc-800/80">
                  <button
                    type="button"
                    onClick={() => handleLaunchBuiltin(rom)}
                    className="w-full flex items-center justify-center gap-1.5 py-2 rounded-xl bg-purple-600 hover:bg-purple-500 text-white font-bold text-xs transition-colors shadow-md shadow-purple-900/20"
                  >
                    <Play size={14} />
                    Launch Demo
                  </button>
                </div>
              </div>
            ))}
          </div>
        </section>

        {/* Engine Fix Details Card */}
        <section className="rounded-2xl bg-gradient-to-r from-zinc-900 via-zinc-900 to-purple-950/20 border border-zinc-800 p-5">
          <div className="flex items-start gap-3">
            <div className="w-9 h-9 rounded-xl bg-emerald-500/10 border border-emerald-500/30 flex items-center justify-center text-emerald-400 shrink-0">
              <Check size={18} />
            </div>
            <div className="text-xs space-y-1.5">
              <h2 className="font-bold text-zinc-100 text-sm">
                Engine & Touch Skin Fixes Active
              </h2>
              <p className="text-zinc-400 leading-relaxed">
                <strong className="text-zinc-300">Emulation Core:</strong> Restored all 16 missing 65816 stack-relative opcodes (<code className="text-purple-300 font-mono">$03-$F3</code>), fixed $2180-$2183 WRAM data port auto-increment pointers used by game decompression routines, rectified $2116/$2117 VMADD byte ordering for tilemaps, and fixed native interrupt M-flag preservation.
              </p>
              <p className="text-zinc-400 leading-relaxed">
                <strong className="text-zinc-300">Pocket Skin:</strong> Fixed overlapping touch hitboxes in Swift & Web decks by introducing isolated circular bounds with -12° diamond geometry and authentic concave/convex button styles.
              </p>
            </div>
          </div>
        </section>
      </main>

      {/* Cartridge Inspector Modal */}
      {selectedCartridge && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-sm animate-fade-in">
          <div className="w-full max-w-md bg-zinc-900 border border-zinc-700 rounded-2xl p-5 shadow-2xl">
            <div className="flex items-center justify-between pb-3 border-b border-zinc-800 mb-4">
              <div className="flex items-center gap-2">
                <FileCode size={18} className="text-purple-400" />
                <h3 className="font-bold text-white text-sm">
                  Cartridge Header Inspector
                </h3>
              </div>
              <button
                type="button"
                onClick={() => setSelectedCartridge(null)}
                className="text-zinc-400 hover:text-white"
              >
                &times;
              </button>
            </div>

            <div className="space-y-2 text-xs font-mono">
              <div className="flex justify-between p-2 rounded bg-zinc-950">
                <span className="text-zinc-400">Internal Title:</span>
                <span className="text-purple-300 font-bold">{selectedCartridge.title}</span>
              </div>
              <div className="flex justify-between p-2 rounded bg-zinc-950">
                <span className="text-zinc-400">Mapping Architecture:</span>
                <span className="text-purple-300">{selectedCartridge.cartridge.isHiROM ? 'HiROM' : 'LoROM'}</span>
              </div>
              <div className="flex justify-between p-2 rounded bg-zinc-950">
                <span className="text-zinc-400">ROM File Size:</span>
                <span className="text-purple-300">{(selectedCartridge.size / 1024).toFixed(0)} KB ({selectedCartridge.size} bytes)</span>
              </div>
              <div className="flex justify-between p-2 rounded bg-zinc-950">
                <span className="text-zinc-400">Reset Vector:</span>
                <span className="text-purple-300">${selectedCartridge.cartridge.resetVector.toString(16).toUpperCase()}</span>
              </div>
              <div className="flex justify-between p-2 rounded bg-zinc-950">
                <span className="text-zinc-400">NMI Vector:</span>
                <span className="text-purple-300">${selectedCartridge.cartridge.nmiVector.toString(16).toUpperCase()}</span>
              </div>
              <div className="flex justify-between p-2 rounded bg-zinc-950">
                <span className="text-zinc-400">Checksum Complement:</span>
                <span className="text-purple-300">${selectedCartridge.cartridge.checksumComplement.toString(16).toUpperCase()}</span>
              </div>
            </div>

            <div className="mt-5 flex justify-end">
              <button
                type="button"
                onClick={() => setSelectedCartridge(null)}
                className="px-4 py-1.5 rounded-lg bg-purple-600 hover:bg-purple-500 text-white font-semibold text-xs"
              >
                Close
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
