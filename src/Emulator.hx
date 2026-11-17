package;

import h2d.Bitmap;
import hxd.PixelFormat;
import hxd.Pixels;
import h2d.Tile;
import model.Bus;
import model.Cartridge;

class Emulator extends hxd.App {
	public static var bus:Bus;
	public static var sp:Pixels;
	public static var bmp:Bitmap;
	public static var resTime:Float = 0;
	static var loaded = false;
	static var paused = false;
	static var online = false;
	static var romBytes:haxe.io.Bytes;
	static var controllerMasks:Array<Int> = [0, 0];
	static var audio:audio.AudioOutput;

	public static function loadRom(bytes:haxe.io.Bytes) {
		if (online) throw 'Disconnect netplay before loading a ROM';
		var cartridge = new Cartridge(bytes);
		romBytes = bytes;
		if (audio != null) audio.reset();
		bus.insertCartridge(cartridge);
		loaded = true;
		paused = false;
		controllerMasks = [0, 0];
		resTime = 0;
	}

	override function init() {
		#if js
		audio = new audio.AudioOutput(bus.apu.sampleRate);
		bus.apu.onSample = audio.push;
		#end
		s2d.scaleMode = ScaleMode.LetterBox(256, 240);
		sp = new Pixels(256, 240, bus.ppu.screen, PixelFormat.RGBA, 0);
		// Tile.fromPixels pads to a square; keep the texture the same size as the framebuffer.
		var texture = h3d.mat.Texture.fromPixels(sp);
		bmp = new Bitmap(Tile.fromTexture(texture), s2d);
		bmp.tile.getTexture().filter = Nearest;
		#if js
		var api = {
			loadRom: function(data:js.lib.ArrayBuffer) loadRom(haxe.io.Bytes.ofData(data)),
			setController: function(mask:Int, port:Int = 0) { if (port >= 0 && port < 2) { controllerMasks[port] = mask & 255; if (!online) bus.controllers[port] = mask & 255; } },
			setVolume: function(value:Float) audio.setVolume(value),
			setMuted: function(value:Bool) audio.setMuted(value),
			setPaused: function(value:Bool) { if (online) throw 'Pause is unavailable during netplay'; setPaused(value); },
			reset: function() {
				if (online) throw 'Disconnect netplay before resetting';
				if (!loaded) return;
				audio.reset(); bus.reset(); resTime = 0; controllerMasks = [0, 0];
			},
			step: stepInstruction,
			netplayVersion: netplay.State.VERSION,
			romHash: function() return loaded ? haxe.crypto.Sha256.make(romBytes).toHex() : '',
			localInput: function(port:Int = 0) return port >= 0 && port < 2 ? controllerMasks[port] : 0,
			netplayStart: function() {
				if (!loaded) throw 'Load the server ROM before connecting';
				bus.insertCartridge(new Cartridge(romBytes));
				online = true; paused = false; resTime = 0; controllerMasks = [0, 0]; audio.reset();
			},
			netplayStop: function() {
				online = false; setPaused(false);
			},
			netplaySave: function() return netplay.State.save(bus),
			netplayLoad: function(state:String) {
				if (!online) throw 'Netplay is not active';
				netplay.State.load(bus, state); audio.reset();
			},
			netplayFrame: function(inputs:Array<Int>, audible:Bool) {
				if (!online) throw 'Netplay is not active';
				var listener = bus.apu.onSample;
				if (!audible) bus.apu.onSample = null;
				try { netplay.State.frame(bus, inputs); }
				catch (error:Dynamic) { bus.apu.onSample = listener; throw error; }
				bus.apu.onSample = listener;
			},
			getState: function() return {
				loaded: loaded, paused: paused, netplay: online, mapper: loaded ? bus.mapperID() : -1,
				pc: bus.cpu.regs.pc, a: bus.cpu.regs.a, x: bus.cpu.regs.x, y: bus.cpu.regs.y,
				sp: bus.cpu.regs.s, status: bus.cpu.regs.p, cycles: bus.cpu.timer,
				instructions: loaded ? debug.Disassembler.list(bus, bus.cpu.regs.pc) : []
			}
		};
		Reflect.setField(js.Browser.window, 'nes', api);
		js.Browser.window.dispatchEvent(new js.html.Event('nes-ready'));
		#elseif sys
		var args = Sys.args();
		if (args.length > 0) loadRom(sys.io.File.getBytes(args[0]));
		#end
	}

	override function update(dt:Float) {
		#if js
		if (online) {
			bmp.tile.getTexture().uploadPixels(sp);
			audio.flush();
			return;
		}
		bus.controllers[0] = controllerMasks[0];
		bus.controllers[1] = controllerMasks[1];
		#else
		var keys = [hxd.Key.Z, hxd.Key.X, hxd.Key.SHIFT, hxd.Key.ENTER,
			hxd.Key.UP, hxd.Key.DOWN, hxd.Key.LEFT, hxd.Key.RIGHT];
		bus.controllers[0] = 0;
		for (i in 0...keys.length) if (hxd.Key.isDown(keys[i])) bus.controllers[0] |= 1 << i;
		#end
		if (!loaded || paused) return;
		resTime += dt;
		// Keep catch-up bounded after a suspended browser tab.
		if (resTime > 0.1) resTime = 0.1;
		var frameDuration = 1 / 60.0988;
		var changed = false;
		while (resTime >= frameDuration) {
			bus.ppu.frameDone = false;
			try {
				do bus.clock() while (!bus.ppu.frameDone);
			} catch (error:Dynamic) {
				setPaused(true);
				#if js
				js.Browser.window.dispatchEvent(new js.html.CustomEvent('nes-error', {detail: Std.string(error)}));
				#else
				throw error;
				#end
				break;
			}
			resTime -= frameDuration;
			changed = true;
		}
		if (changed) bmp.tile.getTexture().uploadPixels(sp);
		if (audio != null) audio.flush();
	}

	static function setPaused(value:Bool) {
		paused = value;
		resTime = 0;
		controllerMasks = [0, 0];
		bus.controllers = [0, 0];
		if (audio != null) audio.reset();
	}

	static function stepInstruction() {
		if (online) throw 'Disconnect netplay before stepping';
		if (!loaded) return;
		setPaused(true);
		debug.CPUDebugger.step(bus);
		if (audio != null) audio.reset();
		bmp.tile.getTexture().uploadPixels(sp);
	}

	static function main() {
		bus = new Bus();
		new Emulator();
	}
}
