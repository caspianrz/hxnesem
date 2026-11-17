package interfaces;

interface IMapper {
	public function cpuMapRead(address:Int, mapperAddress:Dynamic):Bool;
	public function cpuMapWrite(address:Int, mapperAddress:Dynamic, data:Int = 0):Bool;
	public function ppuMapRead(address:Int, mapperAddress:Dynamic):Bool;
	public function ppuMapWrite(address:Int, mapperAddress:Dynamic):Bool;
}
