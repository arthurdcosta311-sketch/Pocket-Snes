# Pocket Snes

A Super Nintendo emulator for iPhone and iPad, written in SwiftUI around a
65816 interpreter, a scanline PPU and a small audio stage. No ROMs ship with
it: import your own `.smc` / `.sfc` dumps from Files and they appear in the
library.

## What works

- LoROM and HiROM cartridges, with 512-byte copier headers stripped, SRAM and
  save states kept on disk.
- A frame loop in the background driving the core at 60 fps, with the full
  controller wired to it on screen and over Bluetooth.
- Video settings (fit, filter, scanlines) and audio volume/mute reaching real
  consumers, plus an engine self-test in Settings.
- Files-picker types for `.smc` and `.sfc`, so every dump shape can be
  imported.

## Known limits

- The sound chip is a tone generator, not an S-SMP/S-DSP. Games that upload
  their own sound driver are acknowledged so they boot, but they stay silent.
- PPU modes 2–7 fall back to a mode-1 render, so Mode 7 games look wrong.
- CPU cycles per scanline are approximated and an IRQ H-match fires at line
  start instead of at the programmed dot.
- ExHiROM and interleaved dumps are not detected.

## Building

Open `Pocket Snes.xcodeproj` in Xcode and run. Pushes to `main` build an
unsigned IPA through the GitHub Actions workflow and upload it as an artifact;
tag a release to attach it to a GitHub Release.
##help 
I need help with it people with experience on emulators feel free to reach out to me
