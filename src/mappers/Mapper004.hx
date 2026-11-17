package mappers;

import model.Cartridge.Mirror;

/** MMC3 banking; IRQs are clocked by the PPU's scanline approximation. */
class Mapper004 extends Mapper000 {
	var select = 0;
	var banks = [0, 2, 4, 5, 6, 7, 0, 1];
	var latch = 0;
	var counter = 0;
	var reload = false;
	var enabled = false;

	override public function cpuMapRead(addr:Int, mapped:Dynamic):Bool {
		if (addr < 0x8000) return false;
		var slot = (addr - 0x8000) >> 13;
		var fixed = prgCount * 2 - 2;
		var bank = switch slot {
			case 0: (select & 0x40) == 0 ? banks[6] & 63 : fixed;
			case 1: banks[7] & 63;
			case 2: (select & 0x40) == 0 ? fixed : banks[6] & 63;
			default: fixed + 1;
		};
		mapped.a = (bank % (prgCount * 2)) * 0x2000 + (addr & 0x1fff);
		return true;
	}

	override public function cpuMapWrite(addr:Int, mapped:Dynamic, data:Int = 0):Bool {
		if (addr < 0x8000) return false;
		switch (addr & 0xe001) {
			case 0x8000: select = data;
			case 0x8001: banks[select & 7] = data;
			case 0xa000: mirror = (data & 1) == 0 ? Vertical : Horizontal;
			case 0xa001: ramEnabled = (data & 0x80) != 0; ramWritable = (data & 0x40) == 0;
			case 0xc000: latch = data;
			case 0xc001: reload = true;
			case 0xe000: enabled = false; irqPending = false;
			case 0xe001: enabled = true;
		}
		return true;
	}

	override public function ppuMapRead(addr:Int, mapped:Dynamic):Bool {
		if (addr < 0 || addr >= 0x2000) return false;
		var slot = (addr >> 10) ^ ((select & 0x80) != 0 ? 4 : 0);
		var bank = slot < 4 ? (banks[slot >> 1] & 0xfe) + (slot & 1) : banks[slot - 2];
		mapped.a = (bank % (chrCount == 0 ? 8 : chrCount * 8)) * 0x400 + (addr & 0x3ff);
		return true;
	}

	override public function ppuMapWrite(addr:Int, mapped:Dynamic):Bool {
		return chrCount == 0 && ppuMapRead(addr, mapped);
	}

	override public function scanline() {
		if (counter == 0 || reload) counter = latch;
		else counter--;
		reload = false;
		if (counter == 0 && enabled) irqPending = true;
	}
}
