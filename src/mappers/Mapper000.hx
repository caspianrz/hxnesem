package mappers;

import interfaces.IMapper;

class Mapper000 implements IMapper {
	public var irqPending = false;
	public var ramEnabled = true;
	public var ramWritable = true;
	public var mirror:Null<model.Cartridge.Mirror> = null;
	public function scanline() {}

	final prgCount:Int;
	final chrCount:Int;

	public function new(prgCount:Int, chrCount:Int) {
		this.prgCount = prgCount;
		this.chrCount = chrCount;
	}

	public function cpuMapRead(addr:Int, mappedAddr:Dynamic) {
		if (addr >= 0x8000 && addr <= 0xffff) {
			Reflect.setProperty(mappedAddr, "a", addr & (this.prgCount > 1 ? 0x7FFF : 0x3FFF));
			return true;
		}
		return false;
	}

	public function cpuMapWrite(addr:Int, mappedAddr:Dynamic, data:Int = 0) {
		return false; // NROM has no writable PRG banks or mapper registers.
	}

	public function ppuMapRead(addr:Int, mappedAddr:Dynamic) {
		if (addr >= 0 && addr <= 0x1fff) {
			Reflect.setProperty(mappedAddr, "a", addr);
			return true;
		}
		return false;
	}

	public function ppuMapWrite(addr:Int, mappedAddr:Dynamic) {
		if (addr >= 0 && addr <= 0x1fff) {
			if (chrCount == 0) {
				Reflect.setProperty(mappedAddr, "a", addr);
				return true;
			}
		}
		return false;
	}
}
