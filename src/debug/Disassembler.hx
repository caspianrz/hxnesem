package debug;

import model.Bus;

typedef Instruction = {
	var address:Int;
	var bytes:String;
	var code:String;
	var size:Int;
}

/** Official 6502 opcodes. Unknown bytes are explicit data, not invented instructions. */
class Disassembler {
	static final rows = [
		'BRK:i ORA:x ? ? ? ORA:z ASL:z ? PHP:i ORA:n ASL:a ? ? ORA:w ASL:w ?',
		'BPL:r ORA:y ? ? ? ORA:u ASL:u ? CLC:i ORA:v ? ? ? ORA:t ASL:t ?',
		'JSR:w AND:x ? ? BIT:z AND:z ROL:z ? PLP:i AND:n ROL:a ? BIT:w AND:w ROL:w ?',
		'BMI:r AND:y ? ? ? AND:u ROL:u ? SEC:i AND:v ? ? ? AND:t ROL:t ?',
		'RTI:i EOR:x ? ? ? EOR:z LSR:z ? PHA:i EOR:n LSR:a ? JMP:w EOR:w LSR:w ?',
		'BVC:r EOR:y ? ? ? EOR:u LSR:u ? CLI:i EOR:v ? ? ? EOR:t LSR:t ?',
		'RTS:i ADC:x ? ? ? ADC:z ROR:z ? PLA:i ADC:n ROR:a ? JMP:d ADC:w ROR:w ?',
		'BVS:r ADC:y ? ? ? ADC:u ROR:u ? SEI:i ADC:v ? ? ? ADC:t ROR:t ?',
		'? STA:x ? ? STY:z STA:z STX:z ? DEY:i ? TXA:i ? STY:w STA:w STX:w ?',
		'BCC:r STA:y ? ? STY:u STA:u STX:b ? TYA:i STA:v TXS:i ? ? STA:t ? ?',
		'LDY:n LDA:x LDX:n ? LDY:z LDA:z LDX:z ? TAY:i LDA:n TAX:i ? LDY:w LDA:w LDX:w ?',
		'BCS:r LDA:y ? ? LDY:u LDA:u LDX:b ? CLV:i LDA:v TSX:i ? LDY:t LDA:t LDX:v ?',
		'CPY:n CMP:x ? ? CPY:z CMP:z DEC:z ? INY:i CMP:n DEX:i ? CPY:w CMP:w DEC:w ?',
		'BNE:r CMP:y ? ? ? CMP:u DEC:u ? CLD:i CMP:v ? ? ? CMP:t DEC:t ?',
		'CPX:n SBC:x ? ? CPX:z SBC:z INC:z ? INX:i SBC:n NOP:i ? CPX:w SBC:w INC:w ?',
		'BEQ:r SBC:y ? ? ? SBC:u INC:u ? SED:i SBC:v ? ? ? SBC:t INC:t ?'
	];
	static final opcodes = rows.join(' ').split(' ');
	static function hex(value:Int, width:Int):String return '$' + StringTools.hex(value, width);

	public static function decode(bus:Bus, address:Int):Instruction {
		address &= 0xffff;
		var opcode = bus.read(address, true);
		var spec = opcodes[opcode].split(':');
		if (spec[0] == '?') return {address: address, bytes: StringTools.hex(opcode, 2), code: '.byte ' + hex(opcode, 2), size: 1};
		var mode = spec[1];
		var size = switch mode { case 'i', 'a': 1; case 'w', 't', 'v', 'd': 3; default: 2; };
		var lo = size > 1 ? bus.read((address + 1) & 0xffff, true) : 0;
		var word = size == 3 ? lo | (bus.read((address + 2) & 0xffff, true) << 8) : 0;
		var operand = switch mode {
			case 'a': ' A';
			case 'n': ' #' + hex(lo, 2);
			case 'z': ' ' + hex(lo, 2);
			case 'u': ' ' + hex(lo, 2) + ',X';
			case 'b': ' ' + hex(lo, 2) + ',Y';
			case 'w': ' ' + hex(word, 4);
			case 't': ' ' + hex(word, 4) + ',X';
			case 'v': ' ' + hex(word, 4) + ',Y';
			case 'd': ' (' + hex(word, 4) + ')';
			case 'x': ' (' + hex(lo, 2) + ',X)';
			case 'y': ' (' + hex(lo, 2) + '),Y';
			case 'r': ' ' + hex((address + 2 + (lo < 128 ? lo : lo - 256)) & 0xffff, 4);
			default: '';
		};
		var bytes = [for (i in 0...size) StringTools.hex(bus.read((address + i) & 0xffff, true), 2)].join(' ');
		return {address: address, bytes: bytes, code: spec[0] + operand, size: size};
	}

	public static function list(bus:Bus, address:Int, count:Int = 20):Array<Instruction> {
		var result = [];
		for (_ in 0...count) {
			var instruction = decode(bus, address);
			result.push(instruction);
			address = (address + instruction.size) & 0xffff;
		}
		return result;
	}
}
