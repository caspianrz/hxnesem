package model;

/** NTSC 2A03 APU. clock() advances one CPU cycle, including during DMA. */
class APU {
	public static inline var CPU_RATE:Float = 1789773;
	public static final LENGTH = [10,254,20,2,40,4,80,6,160,8,60,10,14,12,26,14,12,16,24,18,48,20,96,22,192,24,72,26,16,28,32,30];
	static final NOISE_PERIOD = [4,8,16,32,64,96,128,160,202,254,380,508,762,1016,2034,4068];
	static final DMC_PERIOD = [428,380,340,320,286,254,226,214,190,160,142,128,106,84,72,54];
	public var pulse1(default, null):Pulse;
	public var pulse2(default, null):Pulse;
	public var triangle(default, null):Triangle;
	public var noise(default, null):Noise;
	public var dmc(default, null):DMC;
	public var irqPending(get, never):Bool;
	public var frameIRQ(default, null) = false;
	public var sampleRate(default, null):Int;
	// Optional host callback; no audio queue is allocated when there is no listener.
	public var onSample:Float->Void;
	var frameCycle = 0;
	var cycles = 0;
	var fiveStep = false;
	var inhibitIRQ = false;
	var frameResetDelay = 0;
	var samplePhase:Float = 0;
	var sampleSum:Float = 0;
	var sampleCount = 0;
	var previousInput:Float = 0;
	var highPass:Float = 0;
	var lowPass:Float = 0;
	var hpCoefficient:Float;
	var lpCoefficient:Float;

	public function new(readMemory:Int->Int, stallCPU:Int->Void, sampleRate:Int = 44100) {
		if (sampleRate < 8000 || sampleRate > 192000) throw 'Invalid APU sample rate';
		this.sampleRate = sampleRate;
		hpCoefficient = Math.exp(-2 * Math.PI * 90 / sampleRate);
		lpCoefficient = 1 - Math.exp(-2 * Math.PI * 14000 / sampleRate);
		dmc = new DMC(readMemory, stallCPU);
		reset();
	}

	public function reset() {
		pulse1 = new Pulse(true);
		pulse2 = new Pulse(false);
		triangle = new Triangle();
		noise = new Noise();
		dmc.reset();
		frameCycle = cycles = frameResetDelay = sampleCount = 0;
		fiveStep = inhibitIRQ = frameIRQ = false;
		samplePhase = sampleSum = previousInput = highPass = lowPass = 0;
	}

	function get_irqPending():Bool return frameIRQ || dmc.irq;

	public function readStatus(readonly:Bool = false):Int {
		var value = (pulse1.length > 0 ? 1 : 0) | (pulse2.length > 0 ? 2 : 0)
			| (triangle.length > 0 ? 4 : 0) | (noise.length > 0 ? 8 : 0)
			| (dmc.remaining > 0 ? 16 : 0) | (frameIRQ ? 64 : 0) | (dmc.irq ? 128 : 0);
		if (!readonly) frameIRQ = false;
		return value;
	}

	public function write(addr:Int, data:Int) {
		data &= 255;
		if (addr >= 0x4000 && addr <= 0x4007) {
			(addr < 0x4004 ? pulse1 : pulse2).write(addr & 3, data);
			return;
		}
		switch addr {
			case 0x4008: triangle.control = (data & 128) != 0; triangle.linearReload = data & 127;
			case 0x400a: triangle.period = (triangle.period & 0x700) | data;
			case 0x400b:
				triangle.period = (triangle.period & 255) | ((data & 7) << 8);
				if (triangle.enabled) triangle.length = LENGTH[data >> 3];
				triangle.reload = true;
			case 0x400c: noise.envelope.write(data);
			case 0x400e: noise.shortMode = (data & 128) != 0; noise.period = NOISE_PERIOD[data & 15];
			case 0x400f:
				if (noise.enabled) noise.length = LENGTH[data >> 3];
				noise.envelope.start = true;
			case 0x4010:
				dmc.irqEnabled = (data & 128) != 0;
				if (!dmc.irqEnabled) dmc.irq = false;
				dmc.loop = (data & 64) != 0; dmc.period = DMC_PERIOD[data & 15];
			case 0x4011: dmc.output = data & 127;
			case 0x4012: dmc.sampleAddress = 0xc000 + data * 64;
			case 0x4013: dmc.sampleLength = data * 16 + 1;
			case 0x4015:
				pulse1.enabled = (data & 1) != 0; if (!pulse1.enabled) pulse1.length = 0;
				pulse2.enabled = (data & 2) != 0; if (!pulse2.enabled) pulse2.length = 0;
				triangle.enabled = (data & 4) != 0; if (!triangle.enabled) triangle.length = 0;
				noise.enabled = (data & 8) != 0; if (!noise.enabled) noise.length = 0;
				dmc.irq = false;
				if ((data & 16) == 0) dmc.remaining = 0;
				else if (dmc.remaining == 0) dmc.restart();
			case 0x4017:
				fiveStep = (data & 128) != 0;
				inhibitIRQ = (data & 64) != 0;
				if (inhibitIRQ) frameIRQ = false;
				frameResetDelay = (cycles & 1) == 0 ? 3 : 4;
			default:
		}
	}

	function quarterFrame() {
		pulse1.envelope.clock(); pulse2.envelope.clock(); noise.envelope.clock();
		triangle.quarterFrame();
	}

	function halfFrame() {
		pulse1.halfFrame(); pulse2.halfFrame();
		if (triangle.length > 0 && !triangle.control) triangle.length--;
		if (noise.length > 0 && !noise.envelope.loop) noise.length--;
	}

	public function clock() {
		cycles = (cycles + 1) & 1;
		frameCycle++;
		if (frameCycle == 7457 || frameCycle == 22371) quarterFrame();
		if (frameCycle == 14913 || (!fiveStep && frameCycle == 29829) || (fiveStep && frameCycle == 37281)) {
			quarterFrame(); halfFrame();
		}
		if (!fiveStep && frameCycle >= 29828 && frameCycle <= 29830 && !inhibitIRQ) frameIRQ = true;
		if ((!fiveStep && frameCycle == 29830) || (fiveStep && frameCycle == 37282)) frameCycle = 0;
		if (frameResetDelay > 0 && --frameResetDelay == 0) {
			frameCycle = 0;
			if (fiveStep) { quarterFrame(); halfFrame(); }
		}
		if (cycles == 0) { pulse1.clock(); pulse2.clock(); }
		triangle.clock(); noise.clock(); dmc.clock();
		{
			// Always advance audio state, even on the headless server or during replay.
			// Average CPU-rate output before resampling; the host receives bounded PCM.
			sampleSum += output(); sampleCount++;
			samplePhase += sampleRate;
			if (samplePhase >= CPU_RATE) {
				samplePhase -= CPU_RATE;
				var input = sampleSum / sampleCount;
				highPass = hpCoefficient * (highPass + input - previousInput);
				previousInput = input;
				lowPass += lpCoefficient * (highPass - lowPass);
				if (onSample != null) onSample(Math.max(-1, Math.min(1, lowPass * 1.5)));
				sampleSum = 0; sampleCount = 0;
			}
		}
	}

	/** Nonlinear pulse and triangle/noise/DMC mixer, before the output filters. */
	public function output():Float {
		var pulse = pulse1.output() + pulse2.output();
		var tnd = triangle.output() / 8227.0 + noise.output() / 12241.0 + dmc.output / 22638.0;
		return (pulse == 0 ? 0 : 95.88 / (8128.0 / pulse + 100)) + (tnd == 0 ? 0 : 159.79 / (1 / tnd + 100));
	}
}

class Envelope {
	public var loop = false;
	public var constant = false;
	public var volume = 0;
	public var start = false;
	public var decay(default, null) = 0;
	var divider = 0;
	public function new() {}
	public function write(data:Int) { loop = (data & 32) != 0; constant = (data & 16) != 0; volume = data & 15; }
	public function clock() {
		if (start) { start = false; decay = 15; divider = volume; }
		else if (divider > 0) divider--;
		else { divider = volume; if (decay > 0) decay--; else if (loop) decay = 15; }
	}
	public function output():Int return constant ? volume : decay;
}

class Pulse {
	static final DUTY = [0x02, 0x06, 0x1e, 0xf9];
	public var enabled = false;
	public var length = 0;
	public var period = 0;
	public var envelope = new Envelope();
	var first:Bool;
	var timer = 0;
	var sequence = 0;
	var duty = 0;
	var sweep = 0;
	var sweepDivider = 0;
	var sweepReload = false;
	public function new(first:Bool) this.first = first;
	public function write(reg:Int, data:Int) {
		switch reg {
			case 0: envelope.write(data); duty = data >> 6;
			case 1: sweep = data; sweepReload = true;
			case 2: period = (period & 0x700) | data;
			case 3:
				period = (period & 255) | ((data & 7) << 8);
				if (enabled) length = APU.LENGTH[data >> 3];
				sequence = 0; envelope.start = true;
		}
	}
	function target():Int {
		var change = period >> (sweep & 7);
		return (sweep & 8) != 0 ? period - change - (first ? 1 : 0) : period + change;
	}
	public function halfFrame() {
		if (length > 0 && !envelope.loop) length--;
		if (sweepDivider == 0 && (sweep & 128) != 0 && (sweep & 7) != 0 && period >= 8 && target() <= 0x7ff) period = target();
		if (sweepDivider == 0 || sweepReload) { sweepDivider = (sweep >> 4) & 7; sweepReload = false; }
		else sweepDivider--;
	}
	public function clock() {
		if (timer == 0) { timer = period; sequence = (sequence + 1) & 7; }
		else timer--;
	}
	public function output():Int {
		return length == 0 || period < 8 || target() > 0x7ff || ((DUTY[duty] >> sequence) & 1) == 0 ? 0 : envelope.output();
	}
}

class Triangle {
	public var enabled = false;
	public var length = 0;
	public var period = 0;
	public var control = false;
	public var linearReload = 0;
	public var linear(default, null) = 0;
	public var reload = false;
	var timer = 0;
	var sequence = 15; // DAC starts at zero and holds its value when counters stop.
	public function new() {}
	public function quarterFrame() {
		if (reload) linear = linearReload; else if (linear > 0) linear--;
		if (!control) reload = false;
	}
	public function clock() {
		if (timer == 0) {
			timer = period;
			if (length > 0 && linear > 0) sequence = (sequence + 1) & 31;
		} else timer--;
	}
	public function output():Int return sequence < 16 ? 15 - sequence : sequence - 16;
}

class Noise {
	public var enabled = false;
	public var length = 0;
	public var period = 4;
	public var shortMode = false;
	public var envelope = new Envelope();
	public var shift(default, null) = 1;
	var timer = 0;
	public function new() {}
	public function clock() {
		if (timer == 0) {
			timer = period - 1;
			var feedback = (shift ^ (shift >> (shortMode ? 6 : 1))) & 1;
			shift = (shift >> 1) | (feedback << 14);
		} else timer--;
	}
	public function output():Int return length == 0 || (shift & 1) != 0 ? 0 : envelope.output();
}

class DMC {
	public var irq = false;
	public var irqEnabled = false;
	public var loop = false;
	public var period = 428;
	public var output = 0;
	public var sampleAddress = 0xc000;
	public var sampleLength = 1;
	public var remaining = 0;
	var address = 0xc000;
	var timer = 0;
	var buffer = -1;
	var shift = 0;
	var bits = 8;
	var silent = true;
	var readMemory:Int->Int;
	var stallCPU:Int->Void;
	public function new(readMemory:Int->Int, stallCPU:Int->Void) { this.readMemory = readMemory; this.stallCPU = stallCPU; }
	public function reset() {
		irq = irqEnabled = loop = false; period = 428; output = 0;
		sampleAddress = address = 0xc000; sampleLength = 1; remaining = timer = shift = 0;
		buffer = -1; bits = 8; silent = true;
	}
	public function restart() { address = sampleAddress; remaining = sampleLength; }
	public function clock() {
		if (buffer < 0 && remaining > 0) {
			buffer = readMemory(address) & 255;
			stallCPU(4);
			address = address == 0xffff ? 0x8000 : address + 1;
			remaining--;
			if (remaining == 0) { if (loop) restart(); else if (irqEnabled) irq = true; }
		}
		if (timer > 0) { timer--; return; }
		timer = period - 1;
		if (!silent) {
			if ((shift & 1) != 0) { if (output <= 125) output += 2; }
			else if (output >= 2) output -= 2;
		}
		shift >>= 1;
		if (--bits == 0) {
			bits = 8; silent = buffer < 0;
			if (!silent) { shift = buffer; buffer = -1; }
		}
	}
}
