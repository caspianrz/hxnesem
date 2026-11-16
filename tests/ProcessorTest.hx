import model.Bus;
import model.Processor;

class ProcessorTest {
	static var checks = 0;
	static function equal(actual:Int, expected:Int, label:String) {
		checks++;
		if (actual != expected) throw '$label: expected $expected, got $actual';
	}
	static function step(cpu:Processor):Int {
		while (!cpu.instructionComplete()) cpu.clock();
		var cycles = 0;
		do { cpu.clock(); cycles++; } while (!cpu.instructionComplete());
		return cycles;
	}
	static function setup(code:Array<Int>):Bus {
		var bus = new Bus();
		bus.cpu.regs.pc = 0x200;
		for (i in 0...code.length) bus.write(0x200 + i, code[i]);
		return bus;
	}
	static function main() {
		var bus = setup([0xa9, 0, 0xf0, 2, 0xa9, 1, 0xa2, 0xff, 0xe8, 0xa0, 0xff, 0xc8]);
		var cpu = bus.cpu;
		cpu.zero = 0; equal(cpu.zero, 0, 'zero flag isolates bit 1');
		step(cpu); equal(cpu.zero, 1, 'LDA zero');
		equal(step(cpu), 3, 'BEQ taken cycles'); equal(cpu.regs.pc, 0x206, 'BEQ uses zero flag');
		step(cpu); step(cpu); equal(cpu.regs.x, 0, 'INX wraps'); equal(cpu.zero, 1, 'INX zero');
		step(cpu); step(cpu); equal(cpu.regs.y, 0, 'INY wraps'); equal(cpu.zero, 1, 'INY tests Y');

		bus = setup([0xa2, 0, 0xca, 0xe8, 0xd0, 0xfc]); cpu = bus.cpu;
		step(cpu); step(cpu); equal(cpu.regs.x, 255, 'DEX wraps');
		step(cpu); equal(step(cpu), 2, 'BNE not taken cycles');
		cpu.zero = 0; cpu.regs.pc = 0x204;
		equal(step(cpu), 3, 'BNE taken cycles'); equal(cpu.regs.pc, 0x202, 'signed backward branch');
		bus.write(0x2fe, 0xd0); bus.write(0x2ff, 0xfe); cpu.regs.pc = 0x2fe;
		equal(step(cpu), 4, 'branch page crossing'); equal(cpu.regs.pc, 0x2fe, 'cross-page backward branch');

		bus = setup([0x20, 0x10, 2, 0xea, 0xa9, 7]); cpu = bus.cpu;
		bus.write(0x210, 0x60);
		equal(step(cpu), 6, 'JSR cycles'); equal(cpu.regs.s, 0xfb, 'JSR pushes two bytes');
		step(cpu); equal(cpu.regs.pc, 0x203, 'RTS returns after call'); equal(cpu.regs.s, 0xfd, 'RTS restores stack');
		step(cpu); equal(cpu.regs.pc, 0x204, 'NOP is one byte');
		equal(step(cpu), 2, 'LDA immediate cycles'); equal(cpu.regs.a, 7, 'code after NOP');

		bus = setup([0xa9, 0x80, 0x29, 0, 0xa9, 0x80, 0x0a, 0xa9, 0x80, 0x2a, 0x6a]); cpu = bus.cpu;
		step(cpu); step(cpu); equal(cpu.zero, 1, 'AND zero flag');
		step(cpu); step(cpu); equal(cpu.regs.a, 0, 'ASL result'); equal(cpu.zero, 1, 'ASL zero'); equal(cpu.carry, 1, 'ASL carry');
		step(cpu); step(cpu); equal(cpu.regs.a, 1, 'ROL result'); equal(cpu.carry, 1, 'ROL carry normalized');
		step(cpu); equal(cpu.regs.a, 0x80, 'ROR carry input'); equal(cpu.negative, 1, 'ROR negative result'); equal(cpu.zero, 0, 'ROR zero result');
		bus = setup([0xa9, 0x80, 0xaa, 0xa9, 0, 0x38, 0xe9, 1]); cpu = bus.cpu;
		step(cpu); step(cpu); equal(cpu.negative, 1, 'TAX negative flag');
		step(cpu); step(cpu); step(cpu); equal(cpu.regs.a, 255, 'SBC underflow'); equal(cpu.carry, 0, 'SBC borrow'); equal(cpu.negative, 1, 'SBC negative');
		bus = setup([0xa9, 0xff, 0x2c, 0, 3]); cpu = bus.cpu;
		bus.write(0x300, 0x80); step(cpu); step(cpu); equal(cpu.ovflow, 0, 'BIT tests bit 6'); equal(cpu.negative, 1, 'BIT tests bit 7');
		bus = setup([0xbd, 0xff, 0x02]); cpu = bus.cpu; cpu.regs.x = 1;
		equal(step(cpu), 5, 'indexed load page crossing cycles');
		trace('$checks CPU checks passed');
	}
}
