import debug.Disassembler;
import haxe.io.Bytes;
import model.Bus;
import model.Cartridge;

class DebuggerTest {
	static var checks = 0;
	static function equal(actual:Dynamic, expected:Dynamic, label:String) {
		checks++;
		if (actual != expected) throw '$label: expected $expected, got $actual';
	}
	static function main() {
		var bus = new Bus();
		var program = [0xa9, 0x42, 0x8d, 0x00, 0x20, 0xd0, 0xf9, 0x6c, 0xff, 0x12, 0x0a, 0x02];
		for (i in 0...program.length) bus.write(i, program[i]);
		var lines = Disassembler.list(bus, 0, 6);
		equal(lines[0].code, 'LDA #$42', 'immediate'); equal(lines[0].bytes, 'A9 42', 'raw bytes');
		equal(lines[1].code, 'STA $2000', 'absolute'); equal(lines[1].address, 2, 'variable instruction lengths');
		equal(lines[2].code, 'BNE $0000', 'signed relative target'); equal(lines[3].code, 'JMP ($12FF)', 'indirect');
		equal(lines[4].code, 'ASL A', 'accumulator'); equal(lines[5].code, '.byte $02', 'unsupported opcode');
		for (test in [
			{op: 0xa5, code: 'LDA $12'}, {op: 0xb5, code: 'LDA $12,X'}, {op: 0xb6, code: 'LDX $12,Y'},
			{op: 0xa1, code: 'LDA ($12,X)'}, {op: 0xb1, code: 'LDA ($12),Y'},
			{op: 0xbd, code: 'LDA $3412,X'}, {op: 0xb9, code: 'LDA $3412,Y'}, {op: 0xea, code: 'NOP'}
		]) {
			bus.write(0x100, test.op); bus.write(0x101, 0x12); bus.write(0x102, 0x34);
			equal(Disassembler.decode(bus, 0x100).code, test.code, 'addressing $test');
		}
		var count = 0;
		for (opcode in 0...256) {
			bus.write(0x100, opcode);
			if (!StringTools.startsWith(Disassembler.decode(bus, 0x100).code, '.byte')) count++;
		}
		equal(count, 151, 'all official opcodes represented');
		bus.controllers = [0x85, 0x43]; bus.write(0x4016, 1); bus.write(0x4016, 0);
		Disassembler.list(bus, 0x4015, 5);
		for (port in 0...2) for (bit in 0...8)
			equal(bus.read(0x4016 + port), (bus.controllers[port] >> bit) & 1, 'debug reads preserve controller shift $port $bit');
		for (_ in 0...29828) bus.apu.clock();
		Disassembler.decode(bus, 0x4015);
		equal(bus.apu.irqPending, true, 'debug reads preserve APU frame interrupt');
		equal(bus.read(0x4015) & 64, 64, 'normal status read still acknowledges IRQ');
		equal(bus.apu.irqPending, false, 'normal status read clears IRQ');
		bus.ppu.cpuWrite(0, 128);
		for (_ in 0...89342) bus.ppu.clock();
		Disassembler.decode(bus, 0x2002);
		equal(bus.ppu.cpuRead(2, true) & 128, 128, 'debug reads preserve PPU vblank');
		bus.ppu.cpuWrite(6, 0x20); // Read-only status must not reset the address write latch.
		Disassembler.decode(bus, 0x2002); bus.ppu.cpuWrite(6, 0); bus.ppu.cpuWrite(7, 55);
		equal(bus.ppu.ppuRead(0x2000), 55, 'debug reads preserve PPU address latch');
		var bytes = Bytes.alloc(16 + 16384); bytes.blit(0, Bytes.ofString('NES\x1a'), 0, 4); bytes.set(4, 1);
		bytes.set(16 + 0x3fff, 0xa9); bus.insertCartridge(new Cartridge(bytes)); bus.write(0, 0x37);
		var wrap = Disassembler.decode(bus, 0xffff);
		equal(wrap.code, 'LDA #$37', "operand reads wrap across $FFFF");
		equal(Disassembler.list(bus, 0xffff, 2)[1].address, 1, 'instruction address wraps');
		bytes.set(16, 0xa9); bytes.set(17, 42); bytes.set(18, 0xe8); bytes.set(19, 0x4c); bytes.set(20, 0); bytes.set(21, 0x80);
		bytes.set(16 + 0x3ffc, 0); bytes.set(16 + 0x3ffd, 0x80);
		bus.insertCartridge(new Cartridge(bytes));
		debug.CPUDebugger.step(bus);
		equal(bus.cpu.regs.a, 42, 'single step executes LDA after reset cycles');
		equal(bus.cpu.regs.pc, 0x8002, 'single step stops before INX');
		debug.CPUDebugger.step(bus); equal(bus.cpu.regs.x, 1, 'single step executes exactly one next instruction');
		bus.write(0x4014, 0); debug.CPUDebugger.step(bus);
		equal(bus.cpu.regs.pc, 0x8000, 'single step waits for DMA and executes JMP');
		equal(bus.cpu.instructionComplete(), true, 'single step ends at instruction boundary');
		trace('$checks debugger checks passed');
	}
}
