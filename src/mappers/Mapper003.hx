package mappers;

class Mapper003 extends Mapper000 {
	var bank = 0;
	override public function cpuMapWrite(addr:Int, mapped:Dynamic, data:Int = 0):Bool {
		if (addr < 0x8000) return false;
		bank = data & 3;
		return true;
	}
	override public function ppuMapRead(addr:Int, mapped:Dynamic):Bool {
		if (!super.ppuMapRead(addr, mapped)) return false;
		mapped.a += (chrCount == 0 ? 0 : bank % chrCount) * 0x2000;
		return true;
	}
}
