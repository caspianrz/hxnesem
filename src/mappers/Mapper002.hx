package mappers;

class Mapper002 extends Mapper000 {
	var bank = 0;
	override public function cpuMapRead(addr:Int, mapped:Dynamic):Bool {
		if (addr < 0x8000) return false;
		mapped.a = (addr < 0xc000 ? bank % prgCount : prgCount - 1) * 0x4000 + (addr & 0x3fff);
		return true;
	}
	override public function cpuMapWrite(addr:Int, mapped:Dynamic, data:Int = 0):Bool {
		if (addr < 0x8000) return false;
		bank = data & 15;
		return true;
	}
}
