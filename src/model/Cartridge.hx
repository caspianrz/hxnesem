package model;

import mappers.Mapper000;
import interfaces.IMapper;
import haxe.io.Bytes;

enum Mirror {
	Horizontal;
	Vertical;
	OneScreen_Lo;
	OneScreen_Hi;
	FourScreen;
}

class Cartridge {
	public var pos(default, null):Int = 16;
	public var mapper(default, null):IMapper;
	public var mapperID(default, null):Int;
	public var mirror(default, null):Mirror;
	var prgMemory:Bytes;
	var chrMemory:Bytes;
	var prgRam:Bytes = Bytes.alloc(8192);

	public function new(bytes:Bytes) {
		if (bytes.length < 16 || bytes.getString(0, 4) != 'NES\x1a')
			throw 'Invalid iNES header';
		var flags6 = bytes.get(6);
		var flags7 = bytes.get(7);
		if ((flags7 & 0x0c) == 0x08) throw 'NES 2.0 ROMs are not supported';
		mapperID = (flags7 & 0xf0) | (flags6 >> 4);
		if (mapperID != 0) throw 'Unsupported mapper: $mapperID';
		var prgCount = bytes.get(4);
		var chrCount = bytes.get(5);
		if (prgCount < 1 || prgCount > 2 || chrCount > 1) throw 'Invalid NROM bank counts';
		mirror = (flags6 & 8) != 0 ? FourScreen : ((flags6 & 1) != 0 ? Vertical : Horizontal);
		if ((flags6 & 4) != 0) pos += 512;
		if (bytes.length < pos + prgCount * 16384 + chrCount * 8192) throw 'Truncated iNES ROM';
		if ((flags6 & 4) != 0) prgRam.blit(0x1000, bytes, 16, 512);
		prgMemory = bytes.sub(pos, prgCount * 16384);
		pos += prgMemory.length;
		chrMemory = chrCount == 0 ? Bytes.alloc(8192) : bytes.sub(pos, 8192);
		pos += chrCount * 8192;
		mapper = new Mapper000(prgCount, chrCount);
	}

	// Unmapped reads use -1; bytes are always in the range 0..255.
	public function cpuRead(addr:Int):Int {
		if (addr >= 0x6000 && addr <= 0x7fff) return prgRam.get(addr & 0x1fff);
		var mapped = {a: 0};
		return mapper.cpuMapRead(addr, mapped) ? prgMemory.get(mapped.a) : -1;
	}

	public function cpuWrite(addr:Int, data:Int):Bool {
		if (addr >= 0x6000 && addr <= 0x7fff) {
			prgRam.set(addr & 0x1fff, data & 0xff);
			return true;
		}
		// NROM PRG is ROM: writes are consumed without changing it.
		return addr >= 0x8000 && addr <= 0xffff;
	}

	public function ppuRead(addr:Int):Int {
		var mapped = {a: 0};
		return mapper.ppuMapRead(addr, mapped) ? chrMemory.get(mapped.a) : -1;
	}

	public function ppuWrite(addr:Int, data:Int):Bool {
		var mapped = {a: 0};
		if (!mapper.ppuMapWrite(addr, mapped)) return false;
		chrMemory.set(mapped.a, data & 0xff);
		return true;
	}
}
