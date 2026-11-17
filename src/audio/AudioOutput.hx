package audio;

/** Bounded Web Audio playback queue. The APU itself has no platform dependency. */
class AudioOutput {
	#if js
	var context:js.html.audio.AudioContext;
	var gain:js.html.audio.GainNode;
	var volume:Float = 0.7;
	var muted = false;
	var sources:Array<js.html.audio.AudioBufferSourceNode> = [];
	var samples:Array<Float> = [];
	var nextTime:Float = 0;
	final sampleRate:Int;

	public function new(sampleRate:Int) {
		this.sampleRate = sampleRate;
		// Create/resume audio synchronously in a user gesture (browser autoplay policy).
		js.Browser.document.addEventListener('pointerdown', unlock);
		js.Browser.document.addEventListener('keydown', unlock);
		js.Browser.document.addEventListener('change', unlock);
		js.Browser.document.addEventListener('visibilitychange', function(_) reset());
	}

	function unlock(_:js.html.Event) {
		if (context == null) {
			context = new js.html.audio.AudioContext();
			gain = context.createGain();
			gain.connect(context.destination);
			applyGain();
			reset();
		}
		context.resume().catchError(function(error) {
			js.Browser.console.warn('Audio could not resume', error);
		});
	}

	public function setVolume(value:Float) {
		volume = Math.isFinite(value) ? Math.max(0, Math.min(1, value)) : 0.7;
		applyGain();
	}

	public function setMuted(value:Bool) { muted = value; applyGain(); }

	function applyGain() {
		if (gain != null) gain.gain.setTargetAtTime(muted ? 0 : volume, context.currentTime, 0.01);
	}

	public function push(sample:Float) {
		if (context == null || context.state != js.html.audio.AudioContextState.RUNNING || js.Browser.document.hidden) return;
		// Bound the queue when a host stops draining it.
		if (samples.length < sampleRate / 5) samples.push(sample);
	}

	public function reset() {
		samples = [];
		for (source in sources) { source.onended = null; source.stop(); source.disconnect(); }
		sources = [];
		nextTime = context == null ? 0 : context.currentTime + 0.04;
	}

	public function flush() {
		if (context == null || context.state != js.html.audio.AudioContextState.RUNNING || samples.length == 0) return;
		var now = context.currentTime;
		// Drop stale queued sound after a suspension or a long emulation catch-up.
		if (nextTime < now || nextTime > now + 0.15) resetSchedule(now);
		var buffer = context.createBuffer(1, samples.length, sampleRate);
		var pcm = buffer.getChannelData(0);
		for (i in 0...samples.length) pcm[i] = samples[i];
		samples = [];
		var source = context.createBufferSource();
		source.buffer = buffer;
		source.connect(gain);
		source.onended = function(_) { sources.remove(source); source.disconnect(); };
		sources.push(source);
		source.start(nextTime);
		nextTime += buffer.duration;
	}

	function resetSchedule(now:Float) {
		for (source in sources) { source.onended = null; source.stop(); source.disconnect(); }
		sources = [];
		nextTime = now + 0.04;
	}
	#else
	public function new(sampleRate:Int) {}
	public function setVolume(value:Float) {}
	public function setMuted(value:Bool) {}
	public function push(sample:Float) {}
	public function reset() {}
	public function flush() {}
	#end
}
