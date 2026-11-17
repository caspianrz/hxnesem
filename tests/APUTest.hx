import model.APU;
import model.Bus;
import model.Cartridge;
import haxe.io.Bytes;

class APUTest {
	static var checks = 0;
	static function equal(actual:Dynamic, expected:Dynamic, label:String) {
		checks++;
		if (actual != expected) throw '$label: expected $expected, got $actual';
	}
	static function near(actual:Float, expected:Float, tolerance:Float, label:String) {
		checks++;
		if (Math.abs(actual - expected) > tolerance) throw '$label: expected $expected, got $actual';
	}
	static function tick(apu:APU, count:Int) for (_ in 0...count) apu.clock();
	static function fresh():APU return new APU(function(_) return 0, function(_) {});
	static function main() {
		var a = fresh();
		equal(a.readStatus(), 0, 'reset status'); near(a.output(), 0, 0, 'reset DAC silence');
		a.write(0x4003, 0); equal(a.readStatus() & 1, 0, 'disabled pulse cannot load length');
		a.write(0x4015, 15);
		a.write(0x4000, 0xdf); a.write(0x4002, 8); a.write(0x4003, 0);
		a.write(0x4007, 0); a.write(0x400b, 0); a.write(0x400f, 0);
		equal(a.readStatus() & 15, 15, 'status reports all four length counters');
		a.write(0x4015, 0); equal(a.readStatus() & 15, 0, 'disable clears all lengths immediately');
		a.write(0x4015, 15); equal(a.readStatus() & 15, 0, 'enable does not reload length');

		// Pulse timer clocks at half CPU rate, one sequence step every period+1 ticks.
		a.write(0x4003, 0); tick(a, 2); equal(a.pulse1.output(), 0, '75 percent duty low step');
		tick(a, 18); equal(a.pulse1.output(), 0, '75 percent duty second low step');
		tick(a, 18); equal(a.pulse1.output(), 15, 'pulse timer reaches high duty step');
		a.write(0x4002, 7); equal(a.pulse1.output(), 0, 'ultrasonic pulse muted');
		a.write(0x4002, 8);

		var env = new model.APU.Envelope(); env.write(1); env.start = true; env.clock();
		equal(env.output(), 15, 'envelope restart'); env.clock(); equal(env.output(), 15, 'envelope divider');
		env.clock(); equal(env.output(), 14, 'envelope decay');
		for (_ in 0...28) env.clock(); equal(env.output(), 0, 'envelope reaches zero');
		env.write(0x20); env.clock(); env.clock(); equal(env.output(), 15, 'envelope loops');
		env.write(0x1a); equal(env.output(), 10, 'constant volume bypasses decay');

		a = fresh(); a.write(0x4015, 3);
		for (base in [0x4000, 0x4004]) {
			a.write(base, 0x1f); a.write(base + 2, 100); a.write(base + 3, 0); a.write(base + 1, 0x89);
		}
		tick(a, 14913);
		equal(a.pulse1.period, 49, 'pulse 1 negate uses ones complement');
		equal(a.pulse2.period, 50, 'pulse 2 negate uses twos complement');
		equal(a.pulse1.length, 9, 'half frame decrements length');
		a.write(0x4000, 0x3f); tick(a, 14917); equal(a.pulse1.length, 9, 'length halt');

		a = fresh(); tick(a, 29827); equal(a.irqPending, false, 'no early frame IRQ');
		tick(a, 1); equal(a.irqPending, true, 'four step frame IRQ');
		equal(a.readStatus() & 64, 64, 'status exposes frame IRQ');
		equal(a.irqPending, false, 'status acknowledges frame IRQ');
		tick(a, 1); equal(a.irqPending, true, 'frame IRQ asserted across terminal cycles');
		a.write(0x4017, 0x40); equal(a.irqPending, false, 'frame IRQ inhibit clears pending');
		tick(a, 60000); equal(a.irqPending, false, 'inhibited frame IRQ stays clear');
		a = fresh(); a.write(0x4015, 1); a.write(0x4003, 0); a.write(0x4017, 0x80);
		tick(a, 2); equal(a.pulse1.length, 10, 'frame reset is delayed');
		tick(a, 1); equal(a.pulse1.length, 9, 'five step reset clocks half frame');
		tick(a, 80000); equal(a.irqPending, false, 'five step mode never generates IRQ');

		a = fresh(); a.write(0x4015, 4); a.write(0x4008, 2); a.write(0x400a, 10); a.write(0x400b, 0);
		tick(a, 7457); equal(a.triangle.linear, 2, 'triangle linear reload');
		tick(a, 7456); equal(a.triangle.linear, 1, 'triangle linear decrement');
		tick(a, 7458); equal(a.triangle.linear, 0, 'triangle linear expires');
		var held = a.triangle.output(); tick(a, 100); equal(a.triangle.output(), held, 'triangle DAC holds when stopped');
		a.write(0x4008, 0x83); a.write(0x400b, 0); tick(a, 7500);
		equal(a.triangle.linear, 3, 'triangle control retains reload');
		var values = new Map<Int, Bool>();
		for (_ in 0...352) { a.clock(); values.set(a.triangle.output(), true); }
		var valueCount = 0; for (_ in values.keys()) valueCount++;
		equal(valueCount, 16, 'triangle traverses 16 DAC levels');

		a = fresh(); a.write(0x4015, 8); a.write(0x400c, 0x1f); a.write(0x400f, 0);
		tick(a, 1); equal(a.noise.shift, 0x4000, 'noise LFSR feedback');
		equal(a.noise.output(), 15, 'noise DAC when bit zero clear');
		tick(a, 4); equal(a.noise.shift, 0x2000, 'noise timer period');
		var longNoise = fresh(); var shortNoise = fresh(); shortNoise.write(0x400e, 0x80);
		tick(longNoise, 60); tick(shortNoise, 60);
		equal(longNoise.noise.shift != shortNoise.noise.shift, true, 'short noise uses alternate tap');

		var reads:Array<Int> = []; var stalls = 0;
		a = new APU(function(addr) { reads.push(addr); return 255; }, function(count) stalls += count);
		a.write(0x4010, 0x8f); a.write(0x4011, 64); a.write(0x4012, 0); a.write(0x4013, 0); a.write(0x4015, 16);
		equal(a.readStatus() & 16, 16, 'DMC active before fetch');
		tick(a, 1); equal(reads[0], 0xc000, 'DMC mapped sample address'); equal(stalls, 4, 'DMC fetch stalls CPU');
		equal(a.readStatus() & 0x90, 0x80, 'DMC end IRQ and inactive status');
		equal(a.irqPending, true, 'status read does not clear DMC IRQ');
		tick(a, 1000); equal(a.dmc.output, 80, 'DMC consumes eight delta bits');
		a.write(0x4015, 0); equal(a.irqPending, false, 'status write acknowledges DMC IRQ');
		equal(a.dmc.output, 80, 'DMC DAC holds when disabled');
		a.write(0x4011, 255); equal(a.dmc.output, 127, 'DMC direct DAC is seven bits');
		a.write(0x4010, 0); equal(a.irqPending, false, 'DMC IRQ disable');
		near(a.output(), 159.79 / (1 / (127 / 22638.0) + 100), 0.0000001, 'nonlinear DMC mixer');

		reads = []; stalls = 0; a.reset();
		a.write(0x4010, 0x4f); a.write(0x4012, 255); a.write(0x4013, 4); a.write(0x4015, 16);
		tick(a, 54 * 8 * 67);
		equal(reads[0], 0xffc0, 'DMC high sample start'); equal(reads[63], 0xffff, 'DMC reads end of address space');
		equal(reads[64], 0x8000, 'DMC address wraps to cartridge space');
		equal(reads[65], 0xffc0, 'DMC looping restarts sample address'); equal(a.dmc.irq, false, 'looping suppresses IRQ');

		a = fresh(); var count = 0; var peak = 0.0;
		a.onSample = function(value) { count++; if (!Math.isFinite(value) || value < -1 || value > 1) throw 'Invalid PCM'; peak = Math.max(peak, Math.abs(value)); };
		tick(a, 1789773); equal(count, 44100, 'one second produces exact sample count'); near(peak, 0, 0, 'silent PCM');
		a.write(0x4015, 1); a.write(0x4000, 0xbf); a.write(0x4002, 253); a.write(0x4003, 0);
		tick(a, 30000); equal(peak > 0.01, true, 'pulse produces audible PCM');
		a.reset(); count = 0; peak = 0; tick(a, 17898);
		equal(count, 441, 'reset clears resampler phase'); near(peak, 0, 0, 'reset clears filter history');

		// A concert-A pulse must retain its pitch after CPU-rate mixing/resampling.
		a = fresh(); var crossings = 0; var previous = 0.0;
		a.onSample = function(value) { if (previous < 0 && value >= 0) crossings++; previous = value; };
		a.write(0x4015, 1); a.write(0x4000, 0xbf); a.write(0x4002, 253); a.write(0x4003, 0);
		tick(a, 1789773);
		equal(crossings >= 439 && crossings <= 442, true, '440 Hz pulse retains pitch in PCM');

		// Bus integration: register routing, IRQ vector, controller 2, and DMA clocks.
		var bytes = Bytes.alloc(16 + 16384); bytes.blit(0, Bytes.ofString('NES\x1a'), 0, 4); bytes.set(4, 1);
		bytes.set(16 + 0x3ffc, 0); bytes.set(16 + 0x3ffd, 0x80);
		bytes.set(16 + 0x3ffe, 0); bytes.set(16 + 0x3fff, 0x90);
		bytes.set(16, 0x4c); bytes.set(17, 0); bytes.set(18, 0x80); bytes.set(16 + 0x1000, 0x78);
		bytes.set(16 + 0x1001, 0x4c); bytes.set(16 + 0x1002, 1); bytes.set(16 + 0x1003, 0x90);
		var bus = new Bus(); bus.insertCartridge(new Cartridge(bytes));
		bus.write(0x4015, 1); bus.write(0x4003, 0); equal(bus.read(0x4015) & 1, 1, 'bus routes APU registers');
		bus.controllers[1] = 1; bus.write(0x4016, 1); bus.write(0x4016, 0);
		bus.write(0x4017, 0x40); equal(bus.read(0x4017), 1, '$4017 read remains controller 2');
		bus.reset(); bus.cpu.int = 0; for (_ in 0...29860 * 3) bus.clock();
		equal(bus.cpu.regs.pc, 0x9001, 'frame IRQ reaches CPU IRQ handler');
		bus.reset(); count = 0; bus.apu.onSample = function(_) count++;
		bus.write(0x4014, 0); for (_ in 0...513 * 3) bus.clock();
		equal(count, 12, 'APU clocks throughout OAM DMA');
		bus.reset(); bus.write(0x4010, 0x8f); bus.write(0x4015, 16);
		var before = bus.cpu.timer; for (_ in 0...4 * 3) bus.clock();
		equal(bus.cpu.timer, before, 'DMC stalls CPU through bus');
		equal(bus.read(0x4015) & 128, 128, 'DMC IRQ visible on bus');
		trace('$checks APU checks passed');
	}
}
