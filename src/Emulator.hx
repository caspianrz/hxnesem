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
	static var audio:audio.AudioOutput;

	public static function loadRom(bytes:haxe.io.Bytes) {
		var cartridge = new Cartridge(bytes);
		if (audio != null) audio.reset();
		bus.insertCartridge(cartridge);
		loaded = true;
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
		var input:js.html.InputElement = cast js.Browser.document.getElementById('rom');
		if (input != null) input.onchange = function(_) {
			if (input.files.length == 0) return;
			var reader = new js.html.FileReader();
			reader.onload = function(_) {
				try {
					loadRom(haxe.io.Bytes.ofData(cast reader.result));
				} catch (e:Dynamic) js.Browser.alert(Std.string(e));
			};
			reader.readAsArrayBuffer(input.files.item(0));
		};
		#elseif sys
		var args = Sys.args();
		if (args.length > 0) loadRom(sys.io.File.getBytes(args[0]));
		#end
	}

	override function update(dt:Float) {
		var keys = [hxd.Key.Z, hxd.Key.X, hxd.Key.SHIFT, hxd.Key.ENTER,
			hxd.Key.UP, hxd.Key.DOWN, hxd.Key.LEFT, hxd.Key.RIGHT];
		bus.controllers[0] = 0;
		for (i in 0...keys.length) if (hxd.Key.isDown(keys[i])) bus.controllers[0] |= 1 << i;
		if (!loaded) return;
		resTime += dt;
		// Keep catch-up bounded after a suspended browser tab.
		if (resTime > 0.1) resTime = 0.1;
		var frameDuration = 1 / 60.0988;
		var changed = false;
		while (resTime >= frameDuration) {
			bus.ppu.frameDone = false;
			do bus.clock() while (!bus.ppu.frameDone);
			resTime -= frameDuration;
			changed = true;
		}
		if (changed) bmp.tile.getTexture().uploadPixels(sp);
		if (audio != null) audio.flush();
	}

	static function main() {
		bus = new Bus();
		new Emulator();
	}
}
