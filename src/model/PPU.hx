package model;

import haxe.io.Bytes;
import model.Cartridge.Mirror;

/** NTSC PPU with dot timing and direct tile sampling (no fetch pipeline). */
class PPU {
	public var screen:Bytes = Bytes.alloc(256 * 240 * 4);
	public var frameDone = false;
	public var nmiPending = false;
	public var oam:Bytes = Bytes.alloc(256);
	var tableName = Bytes.alloc(4096);
	var tablePattern = Bytes.alloc(8192);
	var tablePalette = Bytes.alloc(32);
	var cartridge:Cartridge;
	var cycle = 0;
	var scanline = -1;
	var oddFrame = false;
	var control = 0;
	var mask = 0;
	var status = 0;
	var oamAddress = 0;
	var openBus = 0;
	var readBuffer = 0;
	var v = 0;
	var t = 0;
	var fineX = 0;
	var secondWrite = false;
	var nmiLine = false;
	var sprites:Array<Int> = [];

	private var palette:Array<Int> = [
		0x545454, 0x001e74, 0x081090, 0x300088, 0x440064, 0x5c0030, 0x540400, 0x3c1800, 0x202a00, 0x083a00, 0x004000, 0x003c00, 0x00323c, 0x000000, 0x000000,
		0x000000, 0x989698, 0x084cc4, 0x3032ec, 0x5c1ee4, 0x8814b0, 0xa01464, 0x982220, 0x783c00, 0x545a00, 0x287200, 0x087c00, 0x007628, 0x006678, 0x000000,
		0x000000, 0x000000, 0xeceeec, 0x4c9aec, 0x787cec, 0xb062ec, 0xe454ec, 0xec58b4, 0xec6a64, 0xd48820, 0xa0aa00, 0x74c400, 0x4cd020, 0x38cc6c, 0x38b4cc,
		0x3c3c3c, 0x000000, 0x000000, 0xeceeec, 0xa8ccec, 0xbcbcec, 0xd4b2ec, 0xecaeec, 0xecaed4, 0xecb4b0, 0xe4c490, 0xccd278, 0xb4de78, 0xa8e290, 0x98e2b4,
		0xa0d6e4, 0xa0a2a0, 0x000000, 0x000000
	];

	public function new(cart:Cartridge) {
		cartridge = cart;
		reset();
	}

	public function insertCartridge(cart:Cartridge) cartridge = cart;

	public function reset() {
		cycle = 0;
		scanline = -1;
		oddFrame = false;
		control = mask = status = oamAddress = openBus = readBuffer = v = t = fineX = 0;
		secondWrite = nmiLine = nmiPending = frameDone = false;
		sprites = [];
		for (i in 0...256 * 240) screen.set(i * 4 + 3, 255);
	}

	function updateNmi() {
		var line = (status & 0x80) != 0 && (control & 0x80) != 0;
		if (line && !nmiLine) nmiPending = true;
		nmiLine = line;
	}

	public function cpuRead(addr:Int, rdonly:Bool = false):Int {
		var data = openBus;
		switch (addr & 7) {
			case 2:
				data = (status & 0xe0) | (openBus & 0x1f);
				if (!rdonly) {
					status &= 0x7f;
					secondWrite = false;
					updateNmi();
				}
			case 4: data = oam.get(oamAddress);
			case 7:
				var address = v & 0x3fff;
				data = address >= 0x3f00 ? (ppuRead(address) | (openBus & 0xc0)) : readBuffer;
				if (!rdonly) {
					readBuffer = ppuRead(address >= 0x3f00 ? address - 0x1000 : address);
					v = (v + ((control & 4) != 0 ? 32 : 1)) & 0x7fff;
				}
			default:
		}
		if (!rdonly) openBus = data;
		return data;
	}

	public function cpuWrite(addr:Int, data:Int) {
		data &= 0xff;
		openBus = data;
		switch (addr & 7) {
			case 0:
				control = data;
				t = (t & ~0x0c00) | ((data & 3) << 10);
				updateNmi();
			case 1: mask = data;
			case 3: oamAddress = data;
			case 4:
				oam.set(oamAddress, data);
				oamAddress = (oamAddress + 1) & 255;
			case 5:
				if (!secondWrite) {
					fineX = data & 7;
					t = (t & ~0x1f) | (data >> 3);
				} else t = (t & ~0x73e0) | ((data & 7) << 12) | ((data & 0xf8) << 2);
				secondWrite = !secondWrite;
			case 6:
				if (!secondWrite) t = (t & 0xff) | ((data & 0x3f) << 8);
				else {
					t = (t & 0x7f00) | data;
					v = t;
				}
				secondWrite = !secondWrite;
			case 7:
				ppuWrite(v, data);
				v = (v + ((control & 4) != 0 ? 32 : 1)) & 0x7fff;
			default:
		}
	}

	function nameAddress(addr:Int):Int {
		var offset = (addr - 0x2000) & 0xfff;
		var table = offset >> 10;
		var mirror = cartridge == null ? Horizontal : cartridge.mirror;
		table = switch mirror {
			case Vertical: table & 1;
			case Horizontal: table >> 1;
			case OneScreen_Lo: 0;
			case OneScreen_Hi: 1;
			case FourScreen: table;
		};
		return (table << 10) | (offset & 0x3ff);
	}

	function paletteAddress(addr:Int):Int {
		var index = addr & 31;
		return (index & 0x13) == 0x10 ? index - 16 : index;
	}

	public function ppuRead(addr:Int, rdonly:Bool = false):Int {
		addr &= 0x3fff;
		if (addr < 0x2000) {
			var data = cartridge == null ? -1 : cartridge.ppuRead(addr);
			return data >= 0 ? data : tablePattern.get(addr);
		}
		if (addr < 0x3f00) return tableName.get(nameAddress(addr));
		return tablePalette.get(paletteAddress(addr)) & ((mask & 1) != 0 ? 0x30 : 0x3f);
	}

	public function ppuWrite(addr:Int, data:Int) {
		addr &= 0x3fff;
		data &= 255;
		if (addr < 0x2000) {
			if (cartridge != null) cartridge.ppuWrite(addr, data);
			else tablePattern.set(addr, data);
		} else if (addr < 0x3f00) tableName.set(nameAddress(addr), data);
		else tablePalette.set(paletteAddress(addr), data & 0x3f);
	}

	function nextX(address:Int):Int {
		return (address & 31) == 31 ? (address & ~31) ^ 0x400 : address + 1;
	}

	function incrementY() {
		if ((v & 0x7000) != 0x7000) v += 0x1000;
		else {
			v &= ~0x7000;
			var y = (v & 0x3e0) >> 5;
			if (y == 29) { y = 0; v ^= 0x800; }
			else if (y == 31) y = 0;
			else y++;
			v = (v & ~0x3e0) | (y << 5);
		}
	}

	function evaluateSprites() {
		sprites = [];
		var height = (control & 0x20) != 0 ? 16 : 8;
		for (i in 0...64) {
			var row = scanline - oam.get(i * 4) - 1;
			if (row >= 0 && row < height) {
				if (sprites.length == 8) {
					if ((mask & 0x18) != 0) status |= 0x20;
					break;
				}
				sprites.push(i);
			}
		}
	}

	function renderPixel(x:Int) {
		var bg = 0;
		var bgPalette = 0;
		if ((mask & 8) != 0 && (x >= 8 || (mask & 2) != 0)) {
			var px = (x & 7) + fineX;
			var address = px >= 8 ? nextX(v) : v;
			var tile = ppuRead(0x2000 | (address & 0xfff));
			var pattern = ((control & 0x10) << 8) + tile * 16 + ((address >> 12) & 7);
			var bit = 7 - (px & 7);
			bg = ((ppuRead(pattern) >> bit) & 1) | (((ppuRead(pattern + 8) >> bit) & 1) << 1);
			var attr = ppuRead(0x23c0 | (address & 0xc00) | ((address >> 4) & 0x38) | ((address >> 2) & 7));
			bgPalette = (attr >> (((address >> 4) & 4) | (address & 2))) & 3;
		}
		var colorAddress = bg == 0 ? 0x3f00 : 0x3f00 + bgPalette * 4 + bg;
		if ((mask & 0x10) != 0 && (x >= 8 || (mask & 4) != 0)) {
			for (i in sprites) {
				var base = i * 4;
				var sx = x - oam.get(base + 3);
				if (sx < 0 || sx > 7) continue;
				var attr = oam.get(base + 2);
				var height = (control & 0x20) != 0 ? 16 : 8;
				var row = scanline - oam.get(base) - 1;
				if ((attr & 0x80) != 0) row = height - 1 - row;
				var tile = oam.get(base + 1);
				var pattern = height == 16 ? ((tile & 1) << 12) + ((tile & 0xfe) + (row >> 3)) * 16 + (row & 7)
					: ((control & 8) << 9) + tile * 16 + row;
				var bit = (attr & 0x40) != 0 ? sx : 7 - sx;
				var pixel = ((ppuRead(pattern) >> bit) & 1) | (((ppuRead(pattern + 8) >> bit) & 1) << 1);
				if (pixel == 0) continue;
				if (i == 0 && bg != 0 && x < 255) status |= 0x40;
				if (bg == 0 || (attr & 0x20) == 0) colorAddress = 0x3f10 + (attr & 3) * 4 + pixel;
				break;
			}
		}
		if ((mask & 0x18) == 0 && (v & 0x3fff) >= 0x3f00) colorAddress = v & 0x3fff;
		var color = palette[ppuRead(colorAddress)];
		var offset = (scanline * 256 + x) * 4;
		screen.set(offset, color >> 16);
		screen.set(offset + 1, color >> 8);
		screen.set(offset + 2, color);
		screen.set(offset + 3, 255);
	}

	public function clock() {
		var rendering = (mask & 0x18) != 0;
		if (scanline == -1 && cycle == 1) {
			status &= 0x1f;
			updateNmi();
		}
		if (scanline == 241 && cycle == 1) {
			status |= 0x80;
			updateNmi();
		}
		if (scanline >= 0 && scanline < 240) {
			if (cycle == 0) evaluateSprites();
			if (cycle >= 1 && cycle <= 256) renderPixel(cycle - 1);
		}
		if (rendering && scanline >= -1 && scanline < 240) {
			if (cycle >= 8 && cycle <= 256 && cycle % 8 == 0) v = nextX(v);
			if (cycle == 256) incrementY();
			if (cycle == 257) v = (v & ~0x041f) | (t & 0x041f);
			if (scanline == -1 && cycle >= 280 && cycle <= 304) v = (v & ~0x7be0) | (t & 0x7be0);
		}
		// Odd NTSC frames omit the final pre-render dot when rendering is enabled.
		if (scanline == -1 && cycle == 339 && oddFrame && rendering) {
			cycle = 0;
			scanline = 0;
			return;
		}
		cycle++;
		if (cycle == 341) {
			cycle = 0;
			scanline++;
			if (scanline == 261) {
				scanline = -1;
				oddFrame = !oddFrame;
				frameDone = true;
			}
		}
	}
}
