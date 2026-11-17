package netplay;

import haxe.io.Bytes;
import model.Bus;

/** Frame-boundary snapshots. ROM, framebuffer, host callbacks and CPU dispatch stay local. */
@:access(model.Bus)
@:access(model.Cartridge)
class State {
	public static inline var VERSION = 'hxnesem-rollback-1';
	static final excluded = ['bus', 'opTable', 'onSample', 'readMemory', 'stallCPU', 'cartridge', 'screen', 'palette',
		'prgMemory', 'chrMemory', 'pos', 'headerMirror', 'mapperID', 'contentHash', 'chrIsRam'];

	static function object(value:Dynamic):Bool {
		return value != null && !Std.isOfType(value, Array) && !Std.isOfType(value, Bytes) && switch Type.typeof(value) {
			case TObject, TClass(_): !Std.isOfType(value, String);
			default: false;
		};
	}

	static function capture(value:Dynamic):Dynamic {
		if (Std.isOfType(value, Array)) return [for (item in (cast value:Array<Dynamic>)) capture(item)];
		if (!object(value)) return value;
		var result:Dynamic = {};
		var fields = Reflect.fields(value); fields.sort(Reflect.compare);
		for (field in fields) {
			var item = Reflect.field(value, field);
			if (excluded.indexOf(field) < 0 && !Reflect.isFunction(item)) Reflect.setField(result, field, capture(item));
		}
		return result;
	}

	static function apply(target:Dynamic, source:Dynamic) {
		for (field in Reflect.fields(target)) {
			var current = Reflect.field(target, field);
			if (excluded.indexOf(field) >= 0 || Reflect.isFunction(current)) continue;
			if (!Reflect.hasField(source, field)) throw 'Incomplete netplay state: $field';
			var saved = Reflect.field(source, field);
			if (object(current)) apply(current, saved);
			else Reflect.setField(target, field, saved);
		}
	}

	public static function save(bus:Bus):String {
		if (bus.cartridge == null) throw 'Load a ROM before saving state';
		return haxe.Serializer.run({version: VERSION, rom: bus.cartridge.contentHash, machine: capture(bus),
			cart: capture(bus.cartridge), chrRam: bus.cartridge.chrIsRam ? bus.cartridge.chrMemory : null});
	}

	public static function load(bus:Bus, encoded:String) {
		if (encoded == null || encoded.length > 1048576) throw 'Invalid netplay state size';
		var state:Dynamic = haxe.Unserializer.run(encoded);
		if (state.version != VERSION || bus.cartridge == null || state.rom != bus.cartridge.contentHash) throw 'State version or ROM mismatch';
		apply(bus, state.machine);
		apply(bus.cartridge, state.cart);
		if (bus.cartridge.chrIsRam) {
			var ram:Bytes = state.chrRam;
			if (ram == null || ram.length != 8192) throw 'Invalid CHR RAM state';
			bus.cartridge.chrMemory = ram;
		}
	}

	public static function frame(bus:Bus, inputs:Array<Int>) {
		bus.controllers[0] = inputs[0] & 255;
		bus.controllers[1] = inputs[1] & 255;
		bus.ppu.frameDone = false;
		var budget = 90000;
		do { bus.clock(); } while (!bus.ppu.frameDone && --budget > 0);
		if (budget == 0) throw 'Emulation frame timed out';
	}
}
