package debug;

import model.Bus;

class CPUDebugger {
	/** Advance the bus, including DMA/interrupts, to the next CPU instruction boundary. */
	public static function step(bus:Bus):Int {
		var budget = 300000;
		var before = bus.cpu.timer;
		while (!bus.cpu.instructionComplete() && budget-- > 0) bus.clock();
		var boundary = bus.cpu.timer;
		while (bus.cpu.timer == boundary && budget-- > 0) bus.clock();
		while (!bus.cpu.instructionComplete() && budget-- > 0) bus.clock();
		if (budget <= 0) throw 'CPU step timed out';
		return bus.cpu.timer - before;
	}
}
