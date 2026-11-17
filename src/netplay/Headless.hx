package netplay;

import model.Bus;
import model.Cartridge;
import haxe.io.Bytes;

/** Node server uses exactly the same CPU/PPU/APU/mappers and snapshot schema as the client. */
class Headless {
	static function main() {
		var factory = {
			version: State.VERSION,
			create: function(data:js.lib.ArrayBuffer) {
				var bus = new Bus();
				var cart = new Cartridge(Bytes.ofData(data));
				bus.insertCartridge(cart);
				return {
					romHash: cart.contentHash,
					step: function(inputs:Array<Int>) State.frame(bus, inputs),
					save: function() return State.save(bus),
					load: function(state:String) State.load(bus, state),
					peek: function(address:Int) return bus.read(address, true)
				};
			}
		};
		js.Syntax.code('module.exports = {0}', factory);
	}
}
