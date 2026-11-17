import audio.AudioOutput;

/** Host contract tests; run the compiled JS in Node with a small Web Audio mock. */
class AudioOutputTest {
	static var checks = 0;
	static function equal(actual:Dynamic, expected:Dynamic, label:String) {
		checks++;
		if (actual != expected) throw '$label: expected $expected, got $actual';
	}
	static function main() {
		js.Syntax.code("globalThis.window = { document: { hidden: false, listeners: {}, addEventListener: function(name, fn) { this.listeners[name] = fn; } } };
		globalThis.AudioContext = class {
			constructor() { this.currentTime = 0; this.state = 'suspended'; this.destination = {}; this.sources = []; globalThis.testContext = this; }
			resume() { this.state = 'running'; return Promise.resolve(); }
			createGain() { const node = { connect: function() {}, gain: { setTargetAtTime: function(value) { globalThis.testVolume = value; } } }; return node; }
			createBuffer(channels, count, rate) { return { duration: count / rate, pcm: new Float32Array(count), getChannelData: function() { return this.pcm; } }; }
			createBufferSource() {
				const source = { connect: function() {}, disconnect: function() { this.disconnected = true; }, start: function(time) { this.time = time; }, stop: function() { this.stopped = true; } };
				this.sources.push(source); return source;
			}
		};");
		var output = new AudioOutput(44100);
		var doc:Dynamic = js.Browser.document;
		output.push(0.5); output.flush();
		equal(js.Syntax.code("typeof globalThis.testContext"), 'undefined', 'audio context waits for gesture');
		doc.listeners.pointerdown(null);
		var context:Dynamic = js.Syntax.code('globalThis.testContext');
		equal(context.state, 'running', 'gesture resumes context');
		equal(js.Syntax.code('globalThis.testVolume'), 0.7, 'default gain');
		output.setVolume(0.4); equal(js.Syntax.code('globalThis.testVolume'), 0.4, 'volume gain');
		output.setMuted(true); equal(js.Syntax.code('globalThis.testVolume'), 0, 'mute immediate');
		output.setVolume(0.9); equal(js.Syntax.code('globalThis.testVolume'), 0, 'volume change respects mute');
		output.setMuted(false); equal(js.Syntax.code('globalThis.testVolume'), 0.9, 'unmute restores gain');
		output.setVolume(2); equal(js.Syntax.code('globalThis.testVolume'), 1, 'volume clamped');
		for (_ in 0...441) output.push(0.25);
		output.flush();
		var first:Dynamic = context.sources[0];
		equal(first.buffer.pcm.length, 441, 'sample buffer length');
		equal(first.buffer.pcm[0], 0.25, 'PCM reaches host buffer');
		equal(first.time, 0.04, 'playback starts with headroom');
		for (_ in 0...441) output.push(-0.25);
		output.flush();
		equal(context.sources[1].time, 0.05, 'consecutive buffers scheduled without gaps');
		first.onended(null); equal(first.disconnected, true, 'finished sources disconnect');
		output.reset(); equal(context.sources[1].stopped, true, 'ROM reset stops pending sound');
		context.state = 'suspended'; output.push(0.5); output.flush();
		equal(context.sources.length, 2, 'suspended output discarded');
		doc.listeners.keydown(null); equal(context.state, 'running', 'keyboard gesture resumes audio');
		doc.hidden = true; doc.listeners.visibilitychange(null); output.push(0.5); output.flush();
		equal(context.sources.length, 2, 'hidden output discarded');
		doc.hidden = false;
		for (_ in 0...20000) output.push(0.2);
		output.flush(); equal(context.sources[2].buffer.pcm.length, 8820, 'sample queue bounded to 200ms');
		context.currentTime = 10; output.push(0.1); output.flush();
		equal(context.sources[2].stopped, true, 'underrun drops stale queued sources');
		equal(context.sources[3].time, 10.04, 'underrun reanchors schedule');
		trace('$checks audio output checks passed');
	}
}
