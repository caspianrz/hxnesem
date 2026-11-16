![Branding](./extra/branding.png)
-----
A NES emulator using Haxe and Heaps for graphics.

The current graphics path supports mapper 0 (NROM): 16/32 KiB PRG ROM,
8 KiB CHR ROM or CHR RAM, nametable/palette mirroring, background and sprite
rendering, scrolling, sprite priority/zero hits, vblank NMI, and OAM DMA.
The CPU bus also exposes PRG RAM and serial controllers.

Build the browser version with Haxe and the `heaps` haxelib installed:

```sh
haxe build.web.hxml
python3 -m http.server 8000 --directory web
```

Open http://localhost:8000 and choose a mapper-0 `.nes` file using the ROM
picker. No game ROMs are bundled. Controls: Z = A, X = B, Shift = Select,
Enter = Start, arrow keys = directions.

For HashLink, install `hlsdl` as well, build using `haxe build.hl.hxml`, then
run `hl out/emulator.hl path/to/game.nes`.

Run the core regression checks without Heaps or a game ROM:

```sh
haxe -cp src -cp tests -main CoreTest --interp
```

The checks use synthetic cartridges and cover ROM loading/mapping, register
buffering, palette/nametable mirroring, scrolling, background/sprite pixels,
frame timing, CPU/NMI integration, DMA, and controller serialization. The web
build and JavaScript core tests have also been checked; commercial-game
compatibility and an interactive browser session have not been verified.

This remains a work in progress. The PPU samples tiles directly instead of
emulating the hardware fetch/shift-register pipeline. Sprite evaluation is
simplified; hardware overflow quirks, exact register-access races, color
emphasis, and rendering-time PPUDATA behavior are not implemented. DMA timing
uses the existing CPU's instruction-level execution. Audio/APU, battery-save
persistence, NES 2.0, and mappers other than NROM are not implemented.
