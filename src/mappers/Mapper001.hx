package mappers;

import model.Cartridge.Mirror;

/** Standard MMC1 (up to 256 KiB PRG, 8 KiB PRG RAM). */
class Mapper001 extends Mapper000 {
	var shift = 0x10;
	var control = 0x0c;
	var chr0 = 0;
	var chr1 = 0;
	var prg = 0;

	public function new(prgCount:Int, chrCount:Int) {
		super(prgCount, chrCount);
		mirror = OneScreen_Lo;
	}

	override public function cpuMapRead(addr:Int, mapped:Dynamic):Bool {
		if (addr < 0x8000) return false;
		var mode = (control >> 2) & 3;
		var bank = mode < 2 ? (prg & 0x0e) + ((addr >> 14) & 1)
			: mode == 2 ? (addr < 0xc000 ? 0 : prg & 15)
			: (addr < 0xc000 ? prg & 15 : prgCount - 1);
		mapped.a = (bank % prgCount) * 0x4000 + (addr & 0x3fff);
		return true;
	}

	override public function cpuMapWrite(addr:Int, mapped:Dynamic, data:Int = 0):Bool {
		if (addr < 0x8000) return false;
		if ((data & 0x80) != 0) { shift = 0x10; control |= 0x0c; return true; }
		var complete = (shift & 1) != 0;
		shift = (shift >> 1) | ((data & 1) << 4);
		if (complete) {
			switch ((addr >> 13) & 3) {
				case 0:
					control = shift;
					mirror = switch (control & 3) { case 0: OneScreen_Lo; case 1: OneScreen_Hi; case 2: Vertical; default: Horizontal; };
				case 1: chr0 = shift;
				case 2: chr1 = shift;
				case 3: prg = shift; ramEnabled = (prg & 16) == 0;
			}
			shift = 0x10;
		}
		return true;
	}

	override public function ppuMapRead(addr:Int, mapped:Dynamic):Bool {
		if (addr < 0 || addr >= 0x2000) return false;
		var bank = (control & 16) == 0 ? (chr0 & 30) + (addr >> 12) : (addr < 0x1000 ? chr0 : chr1);
		mapped.a = (bank % (chrCount == 0 ? 2 : chrCount * 2)) * 0x1000 + (addr & 0xfff);
		return true;
	}

	override public function ppuMapWrite(addr:Int, mapped:Dynamic):Bool {
		return chrCount == 0 && ppuMapRead(addr, mapped);
	}
}
