import haxe.io.Bytes;
import model.Bus;
import model.Cartridge;
import model.PPU;

class CoreTest {
	static var checks = 0;
	static function equal(actual:Dynamic, expected:Dynamic, label:String) {
		checks++;
		if (actual != expected) throw '$label: expected $expected, got $actual';
	}
	static function rom(chr:Int = 0, flags:Int = 0, banks:Int = 1):Bytes {
		var data = Bytes.alloc(16 + ((flags & 4) != 0 ? 512 : 0) + banks * 16384 + chr * 8192);
		data.blit(0, Bytes.ofString('NES\x1a'), 0, 4);
		data.set(4, banks);
		data.set(5, chr);
		data.set(6, flags);
		var start = 16 + ((flags & 4) != 0 ? 512 : 0);
		// JMP $8000, with reset/NMI vectors pointing at it.
		data.set(start, 0x4c);
		data.set(start + 1, 0);
		data.set(start + 2, 0x80);
		for (offset in [0x3ffa, 0x3ffc, 0x3ffe]) {
			data.set(start + (banks - 1) * 16384 + offset, 0);
			data.set(start + (banks - 1) * 16384 + offset + 1, 0x80);
		}
		return data;
	}
	static function address(p:PPU, addr:Int) {
		p.cpuRead(2);
		p.cpuWrite(6, addr >> 8);
		p.cpuWrite(6, addr & 255);
	}
	static function frame(p:PPU):Int {
		p.frameDone = false;
		var clocks = 0;
		do { p.clock(); clocks++; } while (!p.frameDone && clocks < 90000);
		return clocks;
	}
	static function rejects(data:Bytes, label:String) {
		var rejected = false;
		try { new Cartridge(data); } catch (_:Dynamic) { rejected = true; }
		equal(rejected, true, label);
	}
	static function main() {
		var bytes = rom(1);
		bytes.set(16 + 16384, 0x81);
		var cart = new Cartridge(bytes);
		equal(cart.cpuRead(0x8000), 0x4c, 'PRG begins at byte 16');
		equal(cart.cpuRead(0xc000), 0x4c, '16K PRG mirror');
		cart.cpuWrite(0x8000, 0);
		equal(cart.cpuRead(0x8000), 0x4c, 'PRG ROM immutable');
		equal(cart.ppuRead(0), 0x81, 'CHR ROM readable');
		equal(cart.ppuWrite(0, 0), false, 'CHR ROM write rejected');
		equal(cart.ppuRead(0), 0x81, 'CHR ROM unchanged');
		cart.cpuWrite(0x6000, 0xab);
		equal(cart.cpuRead(0x6000), 0xab, 'PRG RAM');
		var ramCart = new Cartridge(rom());
		ramCart.ppuWrite(0x1fff, 0xcd);
		equal(ramCart.ppuRead(0x1fff), 0xcd, '8K CHR RAM allocated');
		var twoBank = rom(0, 0, 2);
		twoBank.set(16 + 16384, 0xfe);
		equal(new Cartridge(twoBank).cpuRead(0xc000), 0xfe, '32K PRG mapping');
		equal(new Cartridge(rom(0, 4)).cpuRead(0x8000), 0x4c, 'trainer skipped');
		rejects(Bytes.alloc(16), 'bad header');
		rejects(bytes.sub(0, 20), 'truncated ROM');
		var unsupported = rom(); unsupported.set(6, 0x50);
		rejects(unsupported, 'unsupported mapper');

		// Distinct bytes in each 8K PRG and 1K CHR bank reveal mapping errors.
		function banked(id:Int):Cartridge {
			var data = rom(4, id << 4, 4);
			for (i in 0...8) data.fill(16 + i * 8192, 8192, i);
			for (i in 0...32) data.fill(16 + 65536 + i * 1024, 1024, i);
			return new Cartridge(data);
		}
		function serial(c:Cartridge, addr:Int, value:Int) {
			for (i in 0...5) c.cpuWrite(addr, (value >> i) & 1);
		}
		var ux = banked(2);
		equal(ux.cpuRead(0xc000), 6, 'UxROM fixed final bank');
		ux.cpuWrite(0x8000, 2);
		equal(ux.cpuRead(0x8000), 4, 'UxROM selected bank');
		var cnData = rom(4, 0x30, 2);
		for (i in 0...4) cnData.fill(16 + 32768 + i * 8192, 8192, i);
		var cn = new Cartridge(cnData); cn.cpuWrite(0x9000, 3);
		equal(cn.ppuRead(0), 3, 'CNROM CHR switch');
		var mmc1 = banked(1);
		serial(mmc1, 0xe000, 2);
		equal(mmc1.cpuRead(0x8000), 4, 'MMC1 serial PRG switch');
		equal(mmc1.cpuRead(0xc000), 6, 'MMC1 fixed last bank');
		serial(mmc1, 0x8000, 0x1e); serial(mmc1, 0xa000, 3); serial(mmc1, 0xc000, 5);
		equal(mmc1.ppuRead(0), 12, 'MMC1 lower 4K CHR bank');
		equal(mmc1.ppuRead(0x1000), 20, 'MMC1 upper 4K CHR bank');
		equal(mmc1.mirror, model.Cartridge.Mirror.Vertical, 'MMC1 mirroring');
		serial(mmc1, 0xe000, 16); mmc1.cpuWrite(0x6000, 99);
		equal(mmc1.cpuRead(0x6000), 0, 'MMC1 RAM disabled');
		mmc1.cpuWrite(0x8000, 0x80);
		var mmc3 = banked(4);
		mmc3.cpuWrite(0x8000, 6); mmc3.cpuWrite(0x8001, 3);
		equal(mmc3.cpuRead(0x8000), 3, 'MMC3 PRG register');
		mmc3.cpuWrite(0x8000, 0x46);
		equal(mmc3.cpuRead(0x8000), 6, 'MMC3 inverted fixed PRG');
		equal(mmc3.cpuRead(0xc000), 3, 'MMC3 inverted switchable PRG');
		mmc3.cpuWrite(0x8000, 0); mmc3.cpuWrite(0x8001, 7);
		equal(mmc3.ppuRead(0), 6, 'MMC3 aligned 2K CHR');
		equal(mmc3.ppuRead(0x400), 7, 'MMC3 second 1K CHR');
		mmc3.cpuWrite(0x8000, 0x80);
		equal(mmc3.ppuRead(0x1000), 6, 'MMC3 CHR inversion');
		mmc3.cpuWrite(0xa001, 0xc0); mmc3.cpuWrite(0x6000, 99);
		equal(mmc3.cpuRead(0x6000), 0, 'MMC3 RAM write protection');
		mmc3.cpuWrite(0xc000, 1); mmc3.cpuWrite(0xc001, 0); mmc3.cpuWrite(0xe001, 0);
		mmc3.mapper.scanline(); equal(mmc3.mapper.irqPending, false, 'MMC3 IRQ reload');
		mmc3.mapper.scanline(); equal(mmc3.mapper.irqPending, true, 'MMC3 IRQ assertion');
		mmc3.cpuWrite(0xe000, 0); equal(mmc3.mapper.irqPending, false, 'MMC3 IRQ acknowledge');
		var irqPPU = new PPU(mmc3); irqPPU.cpuWrite(1, 8);
		mmc3.cpuWrite(0xe001, 0);
		for (_ in 0...602) irqPPU.clock();
		equal(mmc3.mapper.irqPending, true, 'PPU clocks MMC3 scanline IRQ');

		var irqROM = rom();
		irqROM.set(16 + 0x3ffe, 0x34); irqROM.set(16 + 0x3fff, 0x92);
		var irqBus = new Bus(); irqBus.insertCartridge(new Cartridge(irqROM));
		irqBus.cpu.int = 0; irqBus.cpu.irq();
		equal(irqBus.cpu.regs.pc, 0x9234, 'IRQ uses IRQ vector');
		equal(irqBus.read(0x100 + ((irqBus.cpu.regs.s + 1) & 255)) & 4, 0, 'IRQ saves previous interrupt flag');

		var p = new PPU(ramCart);
		p.ppuWrite(0x2000, 0x12);
		equal(p.ppuRead(0x2400), 0x12, 'horizontal nametable mirror');
		equal(p.ppuRead(0x3000), 0x12, '$3000 mirror');
		p = new PPU(new Cartridge(rom(0, 1)));
		p.ppuWrite(0x2000, 0x34);
		equal(p.ppuRead(0x2800), 0x34, 'vertical nametable mirror');
		equal(p.ppuRead(0x2400), 0, 'vertical second nametable independent');
		p.ppuWrite(0x3f10, 0x21);
		equal(p.ppuRead(0x3f00), 0x21, 'universal palette mirror');
		equal(p.ppuRead(0x7f30), 0x21, '14-bit address and palette wrapping');
		p.ppuWrite(0x2000, 0x45);
		address(p, 0x2000);
		equal(p.cpuRead(7), 0, 'PPUDATA first read buffered');
		equal(p.cpuRead(7), 0x45, 'PPUDATA second read');
		address(p, 0x3f00);
		equal(p.cpuRead(7) & 63, 0x21, 'palette read unbuffered');
		p.cpuWrite(0, 4);
		address(p, 0x2100);
		p.cpuWrite(7, 0x23); p.cpuWrite(7, 0x24);
		equal(p.ppuRead(0x2120), 0x24, 'PPUDATA increment 32');
		p.cpuWrite(3, 255); p.cpuWrite(4, 0xab); p.cpuWrite(4, 0xcd);
		equal(p.oam.get(255), 0xab, 'OAM write');
		equal(p.oam.get(0), 0xcd, 'OAM address wrap');

		p = new PPU(new Cartridge(rom()));
		equal(frame(p), 89342, 'NTSC frame dots');
		p.cpuWrite(0, 0x80);
		equal(p.nmiPending, true, 'enabling NMI during vblank');
		equal(p.cpuRead(2, true) & 128, 128, 'readonly status');
		equal(p.cpuRead(2) & 128, 128, 'vblank status');
		equal(p.cpuRead(2) & 128, 0, 'status read clears vblank');
		p.reset(); p.cpuWrite(1, 8);
		equal(frame(p), 89342, 'even rendered frame');
		equal(frame(p), 89341, 'odd rendered frame dot skip');

		// Tile 0: solid low bitplane. Palette 1 is blue; backdrop is gray.
		p.reset();
		for (i in 0...256) p.oam.set(i, 255);
		for (i in 0...8) p.ppuWrite(i, 255);
		p.ppuWrite(0x3f00, 0); p.ppuWrite(0x3f01, 1);
		p.cpuWrite(1, 0x0a);
		frame(p);
		equal(p.screen.get(0), 0, 'background red');
		equal(p.screen.get(1), 0x1e, 'background green');
		equal(p.screen.get(2), 0x74, 'background blue');
		equal(p.screen.get(3), 255, 'opaque framebuffer');
		p.cpuWrite(1, 8); frame(p);
		equal(p.screen.get(0), 0x54, 'background left clipping');
		// Sprite zero overlaps the solid background on scanline 1.
		p.oam.set(0, 0); p.oam.set(1, 0); p.oam.set(2, 0); p.oam.set(3, 16);
		p.ppuWrite(0x3f11, 0x30); p.cpuWrite(1, 0x1e); frame(p);
		equal(p.screen.get((256 + 16) * 4), 0xec, 'sprite foreground');
		equal(p.cpuRead(2) & 64, 64, 'sprite zero hit');
		p.oam.set(2, 0x20); frame(p);
		equal(p.screen.get((256 + 16) * 4), 0, 'sprite behind background');

		// Coarse/fine scrolling and attribute quadrants use separate nametables.
		p = new PPU(new Cartridge(rom(0, 1)));
		for (i in 0...8) { p.ppuWrite(i, 255); p.ppuWrite(16 + i + 8, 255); }
		p.ppuWrite(0x2400, 1);
		p.ppuWrite(0x3f01, 1); p.ppuWrite(0x3f02, 0x30);
		p.cpuWrite(5, 255); p.cpuWrite(5, 0); p.cpuWrite(1, 0x0a);
		frame(p);
		equal(p.screen.get(0), 0, 'fine X last pixel in first nametable');
		equal(p.screen.get(4), 0xec, 'fine X crosses nametable boundary');
		p.cpuWrite(5, 0); p.cpuWrite(5, 0); p.ppuWrite(0x23c0, 4);
		p.ppuWrite(0x3f05, 0x30); frame(p);
		equal(p.screen.get(16 * 4), 0xec, 'attribute top right quadrant');
		equal(p.screen.get(0), 0, 'attribute top left quadrant');

		// Execute a tiny ROM that enables vblank NMIs and increments RAM in its handler.
		var program = rom();
		var code = [0xa9, 0x80, 0x8d, 0x00, 0x20, 0x4c, 0x05, 0x80];
		for (i in 0...code.length) program.set(16 + i, code[i]);
		program.set(16 + 0x100, 0xe6); program.set(16 + 0x101, 0x00); // INC $00
		program.set(16 + 0x102, 0x40); // RTI
		program.set(16 + 0x3ffa, 0); program.set(16 + 0x3ffb, 0x81);
		var running = new Bus(); running.insertCartridge(new Cartridge(program));
		for (_ in 0...89342) running.clock();
		equal(running.ram.get(0), 1, 'CPU executes ROM and services PPU NMI');

		// Boot like a game: wait for vblank, clear RAM, call setup, then render.
		var bootRom = rom(1);
		var boot = [0x78, 0xd8, 0xa2, 0xff, 0x9a];
		for (_ in 0...2) for (byte in [0x2c, 0x02, 0x20, 0x10, 0xfb]) boot.push(byte);
		for (byte in [0xa9, 0, 0xa2, 0, 0x9d, 0, 0, 0xe8, 0xd0, 0xfa,
			0x20, 0, 0x81, 0xa9, 42, 0x85, 0]) boot.push(byte);
		var idle = 0x8000 + boot.length;
		for (byte in [0x4c, idle & 255, idle >> 8]) boot.push(byte);
		var setup = [0xa9, 0x3f, 0x8d, 6, 0x20, 0xa9, 0, 0x8d, 6, 0x20,
			0x8d, 7, 0x20, 0xa9, 1, 0x8d, 7, 0x20,
			0xa9, 0, 0x8d, 0, 0x20, 0x8d, 5, 0x20, 0x8d, 5, 0x20,
			0xa9, 0x0a, 0x8d, 1, 0x20, 0x60];
		for (i in 0...boot.length) bootRom.set(16 + i, boot[i]);
		for (i in 0...setup.length) bootRom.set(16 + 0x100 + i, setup[i]);
		for (i in 0...8) bootRom.set(16 + 16384 + i, 255);
		var bootBus = new Bus(); bootBus.insertCartridge(new Cartridge(bootRom));
		for (_ in 0...4 * 89342) bootBus.clock();
		equal(bootBus.ram.get(0), 42, 'game boot completes RAM loop and subroutine');
		equal(bootBus.cpu.regs.s, 255, 'game boot stack restored');
		equal(bootBus.ppu.screen.get(0), 0, 'CPU-initialized background red');
		equal(bootBus.ppu.screen.get(1), 0x1e, 'CPU-initialized background green');
		equal(bootBus.ppu.screen.get(2), 0x74, 'CPU-initialized background blue');

		var bus = new Bus(); bus.insertCartridge(new Cartridge(rom()));
		equal(bus.cpu.regs.pc, 0x8000, 'reset vector through cartridge');
		bus.write(0x2008, 4); bus.write(0x2006, 0x20); bus.write(0x2006, 0);
		bus.write(0x2007, 11); bus.write(0x2007, 12);
		equal(bus.ppu.ppuRead(0x2020), 12, 'mirrored CPU PPU registers');
		for (i in 0...256) bus.write(0x200 + i, i);
		bus.write(0x2003, 128);
		var timer = bus.cpu.timer;
		bus.write(0x4014, 2);
		for (_ in 0...513 * 3) bus.clock();
		equal(bus.cpu.timer, timer, 'DMA stalls CPU for 513 cycles');
		equal(bus.ppu.oam.get(128), 0, 'DMA starts at OAMADDR');
		equal(bus.ppu.oam.get(127), 255, 'DMA wraps OAMADDR');
		bus.clock(); equal(bus.cpu.timer, timer + 1, 'CPU resumes after DMA');
		bus.controllers[0] = 0x85;
		bus.write(0x4016, 1); bus.write(0x4016, 0);
		for (i in 0...8) equal(bus.read(0x4016), (0x85 >> i) & 1, 'controller bit $i');
		equal(bus.read(0x4016), 1, 'controller post-read ones');
		trace('$checks checks passed');
	}
}
