package model;

import haxe.io.Bytes;

class Bus {
	public var cpu:Processor;
	public var ppu:PPU;
	public var apu:APU;
	var dmcStall = 0;
	public var ram:Bytes = Bytes.alloc(0x800);
	// A, B, Select, Start, Up, Down, Left, Right (bits 0..7).
	public var controllers:Array<Int> = [0, 0];
	var controllerShift:Array<Int> = [0, 0];
	var controllerStrobe = false;
	var cartridge:Cartridge;
	var systemClockCounter = 0;
	var cpuOddCycle = false;
	var dmaActive = false;
	var dmaDummy = 0;
	var dmaPage = 0;
	var dmaOffset = 0;
	var dmaData = 0;
	var dmaRead = true;

	public function new() {
		cpu = new Processor(this);
		ppu = new PPU(null);
		apu = new APU(read, function(cycles) dmcStall += cycles);
	}

	public function write(address:Int, data:Int):Void {
		address &= 0xffff;
		data &= 0xff;
		if (cartridge != null && cartridge.cpuWrite(address, data)) return;
		if (address <= 0x1fff) ram.set(address & 0x7ff, data);
		else if (address <= 0x3fff) ppu.cpuWrite(address & 7, data);
		else if (address == 0x4014) {
			dmaPage = data << 8;
			dmaOffset = 0;
			dmaRead = true;
			dmaActive = true;
			dmaDummy = cpuOddCycle ? 2 : 1;
		} else if (address <= 0x4013 || address == 0x4015 || address == 0x4017) {
			apu.write(address, data);
		} else if (address == 0x4016) {
			controllerStrobe = (data & 1) != 0;
			controllerShift = controllers.copy();
		}
	}

	public function read(address:Int):Int {
		address &= 0xffff;
		if (cartridge != null) {
			var data = cartridge.cpuRead(address);
			if (data >= 0) return data;
		}
		if (address <= 0x1fff) return ram.get(address & 0x7ff);
		if (address <= 0x3fff) return ppu.cpuRead(address & 7);
		if (address == 0x4015) return apu.readStatus();
		if (address == 0x4016 || address == 0x4017) {
			var port = address & 1;
			if (controllerStrobe) return controllers[port] & 1;
			var data = controllerShift[port] & 1;
			controllerShift[port] = (controllerShift[port] >> 1) | 0x80;
			return data;
		}
		return 0;
	}

	public function insertCartridge(cart:Cartridge) {
		cartridge = cart;
		ppu.insertCartridge(cart);
		reset();
	}

	public function reset() {
		systemClockCounter = 0;
		cpuOddCycle = dmaActive = false;
		controllerStrobe = false;
		controllerShift = [0, 0];
		dmcStall = 0;
		apu.reset();
		ppu.reset();
		cpu.reset();
	}

	public function clock():Void {
		ppu.clock();
		if (systemClockCounter == 0) {
			apu.clock();
			if (dmcStall > 0) dmcStall--;
			else if (dmaActive) {
				if (dmaDummy > 0) dmaDummy--;
				else if (dmaRead) {
					dmaData = read(dmaPage | dmaOffset);
					dmaRead = false;
				} else {
					ppu.cpuWrite(4, dmaData);
					dmaRead = true;
					dmaOffset++;
					if (dmaOffset == 256) dmaActive = false;
				}
			} else {
				if (ppu.nmiPending && cpu.instructionComplete()) {
					ppu.nmiPending = false;
					cpu.nmi();
				}
				else if ((apu.irqPending || (cartridge != null && cartridge.mapper.irqPending)) && cpu.instructionComplete()) cpu.irq();
				cpu.clock();
			}
			cpuOddCycle = !cpuOddCycle;
		}
		systemClockCounter = (systemClockCounter + 1) % 3;
	}
}
