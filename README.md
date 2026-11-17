![Branding](./extra/branding.png)
-----
A NES emulator using Haxe and Heaps for graphics.

The current graphics path supports mappers 0–4 (NROM, MMC1, UxROM, CNROM, MMC3),
8 KiB CHR ROM or CHR RAM, nametable/palette mirroring, background and sprite
rendering, scrolling, sprite priority/zero hits, vblank NMI, and OAM DMA.
The CPU bus also exposes PRG RAM and serial controllers.

The NTSC APU implements both pulse channels, triangle, noise, and DMC samples,
including envelopes, sweeps, length/linear counters, the 4/5-step frame
sequencer, frame/DMC IRQs, and DMC cartridge reads with approximate CPU stalls.
Audio uses a nonlinear mixer, CPU-cycle averaging, and high/low-pass filters.
The browser build plays 44.1 kHz mono PCM through Web Audio; click or press a
key to enable sound. Queued sound is cleared when changing ROMs or hiding the
tab. HashLink currently runs the APU core without speaker output.

Build the browser version with Haxe and the `heaps` haxelib installed:

```sh
haxe build.web.hxml
python3 -m http.server 8000 --directory web
```

Open http://localhost:8000 and choose a mapper 0–4 `.nes` file using the ROM
picker, or drop a ROM onto the screen. No game ROMs are bundled.

The browser toolbar provides pause/resume, reset, volume, and mute. **Controls**
opens keyboard mapping for both players: choose an action and press a physical
key (Escape cancels). Assigning an occupied key swaps its previous action.
Mappings, volume, and mute save automatically in this browser's local storage;
ROM contents are never saved or uploaded. If storage is blocked, settings work
for the current session. Restore defaults resets both players' controls.

Player 1 defaults: Z = A, X = B, Left Shift = Select, Enter = Start, arrow keys
= directions. Player 2: G = A, H = B, R = Select, T = Start, W/S/A/D = directions.
Click the screen to play; focus leaving the window releases all held buttons.
Opening Controls pauses play and resumes it on close if it was running.

**CPU inspector** opens a docked panel with live registers, flags, cycle count,
and the next 20 disassembled instructions with addresses and raw bytes.
Pause/resume, reset, and single-instruction stepping work in the panel.
**Pop out** opens the same inspector in a separate browser window connected to
the main emulator. If pop-ups are blocked, the docked panel remains available.
Debugger reads preserve PPU/APU flags and controller shift registers. Unknown
opcodes display as `.byte` data. These browser controls do not change the
HashLink command-line interface.

For HashLink, install `hlsdl` as well, build using `haxe build.hl.hxml`, then
run `hl out/emulator.hl path/to/game.nes`.

Run the core regression checks without Heaps or a game ROM:

```sh
haxe -cp src -cp tests -main CoreTest --interp
haxe -cp src -cp tests -main ProcessorTest --interp
haxe -cp src -cp tests -main APUTest --interp
haxe -cp src -cp tests -main DebuggerTest --interp
node tests/SettingsTest.cjs
```

The checks use synthetic cartridges and cover ROM loading/mapping, register
buffering, palette/nametable mirroring, scrolling, background/sprite pixels,
frame timing, CPU/NMI integration, DMA, and controller serialization. CPU checks
cover branches, flags, stack returns, register wrapping, and instruction timing.
APU checks cover channel waveforms/counters, envelope and sweep behavior,
frame/DMC IRQ acknowledgement, DMC looping/address wrapping/stalls, DMA clocks,
PCM rate, and pitch. Test the browser audio scheduling contract with a mocked
Web Audio host (Node required):

```sh
haxe -cp src -cp tests -main AudioOutputTest -js /tmp/audio-output-test.js
node /tmp/audio-output-test.js
```

A synthetic boot ROM also waits for vblank and initializes a colored framebuffer. The web
build and JavaScript core tests have also been checked. Chromium UI checks with
a synthetic ROM cover both mapped controllers, persisted settings, ROM errors,
drag-and-drop, audio controls, debugger docking/pop-out/stepping, and responsive
canvas sizing. Commercial-game compatibility remains unverified.

This remains a work in progress. The PPU samples tiles directly instead of
emulating the hardware fetch/shift-register pipeline. Sprite evaluation is
simplified; hardware overflow quirks, exact register-access races, color
emphasis, and rendering-time PPUDATA behavior are not implemented. DMA timing
uses the existing CPU's instruction-level execution. Exact APU register-write races, DMC DMA/controller-read glitches,
PAL APU timing, expansion audio, and band-limited synthesis are not implemented.
Browser listening tests and commercial-game audio have not been verified. Battery-save
persistence, NES 2.0, and mappers beyond 0–4 are not implemented. MMC3 IRQs use a scanline approximation,
not filtered PPU A12 edges. MMC1 supports standard boards up to 256 KiB PRG
and 8 KiB PRG RAM; extended SxROM boards and consecutive-cycle write filtering
are not supported. Discrete mapper bus conflicts and MMC6 variants are not emulated.

APU register and mixer references: [NESdev APU](https://www.nesdev.org/wiki/APU),
[APU mixer](https://www.nesdev.org/wiki/APU_Mixer), and
[DMC](https://www.nesdev.org/wiki/APU_DMC).
