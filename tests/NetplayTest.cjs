'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const factory = require('../server/core.cjs');
const { Rollback, VERSION, hashState } = require('../web/rollback.js');
const { Room } = require('../server/room.cjs');

function rom(mapper = 0) {
  const data = new Uint8Array(16 + 32768);
  data.set([78, 69, 83, 26, 2, 0, mapper << 4]);
  const code = [0x78, 0xa9, 0x40, 0x8d, 0x17, 0x40];
  const loop = 0x8000 + code.length;
  code.push(0xa9, 1, 0x8d, 0x16, 0x40, 0xa9, 0, 0x8d, 0x16, 0x40,
    0xad, 0x16, 0x40, 0x85, 0, 0x8d, 0, 0x80, // sample controller and exercise mapper registers
    0xa9, 0, 0x8d, 6, 0x20, 0x8d, 6, 0x20, 0xa5, 0, 0x8d, 7, 0x20, // CHR RAM
    0xad, 0x17, 0x40, 0x85, 1, 0xe6, 2, 0x4c, loop & 255, loop >> 8);
  for (const offset of [16, 16 + 16384]) {
    data.set(code, offset);
    for (const vector of [0x3ffa, 0x3ffc, 0x3ffe]) data.set([0, 0x80], offset + vector);
  }
  return data.buffer;
}
function core() { return factory.create(rom()); }
function peer() { return { packets: [], send(packet) { this.packets.push(packet); } }; }
function toy() {
  let value = 0;
  return { romHash: 'toy', save: () => String(value), load: state => { value = Number(state); }, step: inputs => { value = value * 3 + inputs[0] + 2 * inputs[1]; } };
}
function join(room, client) { return room.join(client, { version: VERSION, romHash: room.core.romHash }); }

test('snapshot restores CPU, PPU, APU, RAM and mapper state deterministically for mappers 0–4', () => {
  for (let mapper = 0; mapper <= 4; mapper++) {
    const machine = factory.create(rom(mapper));
    machine.step([1, 0]); const saved = machine.save();
    machine.step([0, 1]); machine.step([1, 1]); const expected = machine.save();
    machine.load(saved); machine.step([0, 1]); machine.step([1, 1]);
    assert.equal(machine.save(), expected, `mapper ${mapper}`);
    const second = factory.create(rom(mapper)); second.load(saved);
    assert.equal(second.save(), saved, `snapshot transfers to another emulator: mapper ${mapper}`);
  }
});

test('snapshots reject the wrong ROM, version and oversized payload', () => {
  const machine = core(); const original = machine.save();
  const otherROM = new Uint8Array(rom()); otherROM[100] = 1;
  assert.throws(() => factory.create(otherROM.buffer).load(original), /mismatch/);
  assert.throws(() => machine.load(original.replace(VERSION, VERSION.replace(/1$/, '2'))), /mismatch/);
  assert.throws(() => machine.load('x'.repeat(1048577)), /size/);
  assert.equal(machine.save(), original);
});

test('two predictive emulators converge to the authoritative emulator after delayed inputs', () => {
  const authority = core(); const room = new Room(authority);
  const peers = [peer(), peer()]; peers.forEach(client => join(room, client));
  const machines = [core(), core()];
  const clients = machines.map((machine, slot) => {
    const client = new Rollback(machine, slot); client.install(0, authority.save()); return client;
  });
  const inputs = [[1, 0], [0, 1], [1, 1], [0, 0]];
  for (let f = 0; f < inputs.length; f++) {
    peers.forEach((client, slot) => assert.equal(room.input(client, { frame: f, input: inputs[f][slot] }), true));
    clients.forEach((client, slot) => client.predict(inputs[f][slot]));
  }
  for (let f = 0; f < inputs.length; f++) {
    const packet = room.tick();
    clients.forEach(client => assert.equal(client.confirm(packet).resync, undefined));
  }
  machines.forEach(machine => assert.equal(machine.save(), authority.save()));
  clients.forEach(client => { assert.ok(client.rollbacks > 0); assert.equal(client.confirmed, inputs.length - 1); });
});

test('rollback replay reuses recorded local inputs and suppresses replay audio', () => {
  const machine = toy(); const audible = [];
  const original = machine.step; machine.step = (pair, sound) => { audible.push(sound); original(pair); };
  const client = new Rollback(machine, 0); client.install(0, '0');
  client.predict(2); client.predict(4);
  const server = toy(); server.step([2, 3]); const packet = { frame: 0, inputs: [2, 3], hash: hashState(server.save()) };
  assert.equal(client.confirm(packet).rolledBack, true);
  server.step([4, 3]); assert.equal(machine.save(), server.save());
  assert.deepEqual(audible, [true, true, false, false]);
});

test('prediction is bounded; duplicate packets, gaps and desync checkpoints are handled', () => {
  const machine = toy(); const client = new Rollback(machine, 0, { maxLead: 2 }); client.install(0, '0');
  assert.equal(client.predict(1), true); assert.equal(client.predict(1), true); assert.equal(client.predict(1), false);
  const authority = toy(); authority.step([1, 0]);
  const packet = { frame: 0, inputs: [1, 0], hash: hashState(authority.save()) };
  assert.equal(client.confirm(packet).resync, undefined); assert.equal(client.confirm(packet).duplicate, true);
  assert.equal(client.confirm({ ...packet, frame: 2 }).resync, true);
  assert.equal(client.confirm({ ...packet, frame: 1, hash: '00000000' }).resync, true);
  client.install(22, '123'); assert.equal(client.nextFrame, 22); assert.equal(client.confirmed, 21); assert.equal(client.frames.size, 0);
  assert.equal(machine.save(), '123');
  assert.throws(() => client.confirm({ frame: -1, inputs: [0, 0], hash: '00000000' }), /Invalid/);
});

test('a client behind the server can apply confirmed frames without generating new local input', () => {
  const authority = toy(); const clientCore = toy(); const client = new Rollback(clientCore, 1); client.install(0, '0');
  for (let frame = 0; frame < 3; frame++) {
    authority.step([frame, frame + 1]);
    assert.equal(client.confirm({ frame, inputs: [frame, frame + 1], hash: hashState(authority.save()) }).resync, undefined);
  }
  assert.equal(clientCore.save(), authority.save()); assert.equal(client.nextFrame, 3);
});

test('server assigns slots, rejects ROM mismatch and clients cannot rewrite inputs or another player', () => {
  const room = new Room(toy()); const first = peer(); const second = peer();
  assert.throws(() => room.join(peer(), { version: VERSION, romHash: 'wrong' }), /mismatch/);
  assert.equal(join(room, first), 0); assert.equal(room.tick(), null); assert.equal(join(room, second), 1);
  assert.throws(() => join(room, peer()), /running/);
  assert.equal(room.input(first, { frame: 0, input: 5, slot: 1 }), true);
  assert.equal(room.input(first, { frame: 0, input: 99 }), false);
  assert.equal(room.input(peer(), { frame: 0, input: 255 }), false);
  assert.equal(room.input(second, { frame: 0, input: 7 }), true);
  assert.deepEqual(room.tick().inputs, [5, 7]);
  assert.equal(room.input(first, { frame: 0, input: 0 }), false);
  assert.equal(room.input(first, { frame: 9999, input: 0 }), false);
  assert.equal(room.input(first, { frame: 1, input: 256 }), false);
  assert.equal(room.input(first, { frame: 1.5, input: 0 }), false);
  room.snapshot(first); assert.equal(first.packets.at(-1).nextFrame, 1);
  assert.equal(first.packets.at(-1).state, room.core.save());
  room.leave(first); assert.equal(room.tick(), null); assert.equal(second.packets.at(-1).type, 'ended');
});

test('missing inputs predict held keys briefly, then release; queues remain bounded', () => {
  const room = new Room(toy()); const first = peer(); const second = peer(); join(room, first); join(room, second);
  room.input(first, { frame: 0, input: 1 }); room.tick();
  for (let i = 0; i < 30; i++) assert.equal(room.tick().inputs[0], 1);
  assert.equal(room.tick().inputs[0], 0); assert.equal(room.pending[0].size, 0);
});

test('browser connection state: handshake, start, local-input delay, sync and single-player fallback', () => {
  const sockets = []; let active = false; let value = 0; let stopped = 0; let now = 0;
  class Socket {
    constructor(url) { this.url = url; this.readyState = 1; this.sent = []; sockets.push(this); }
    send(text) { this.sent.push(JSON.parse(text)); }
    close() { this.readyState = 3; }
    receive(packet) { this.onmessage({ data: JSON.stringify(packet) }); }
  }
  const window = { NesRollback: require('../web/rollback.js'), location: { href: 'http://localhost:8080/' }, WebSocket: Socket };
  const context = { window, URL, performance: { now: () => now }, setTimeout: () => 1, clearTimeout() {}, setInterval: () => 2, clearInterval() {} };
  vm.runInNewContext(fs.readFileSync(require.resolve('../web/netplay.js'), 'utf8'), context);
  const api = {
    getState: () => ({ loaded: true }), romHash: () => 'toy', localInput: slot => [5, 9][slot],
    netplayStart() { active = true; }, netplayStop() { active = false; stopped++; },
    netplaySave: () => String(value), netplayLoad: state => { value = Number(state); },
    netplayFrame: inputs => { value += inputs[0] + inputs[1]; }
  };
  const client = new window.NesNetplay.Client(api);
  client.connect('http://localhost:8080', 'main'); const socket = sockets[0];
  assert.equal(socket.url, 'ws://localhost:8080/netplay');
  socket.receive({ type: 'hello', version: VERSION, romHash: 'toy' }); assert.equal(socket.sent[0].type, 'join');
  socket.receive({ type: 'start', slot: 1, version: VERSION, romHash: 'toy', nextFrame: 0, state: '0', inputDelay: 3 });
  assert.equal(active, true); client.pump();
  assert.ok(socket.sent.some(packet => packet.type === 'input' && packet.frame === 3 && packet.input === 9));
  assert.equal(value, 0, 'input delay initially uses neutral input');
  for (let frame = 0; frame < 4; frame++) socket.receive({ type: 'frame', frame, inputs: [0, 0], hash: hashState('0') });
  now = 20; client.pump();
  for (let frame = 3; frame <= 7; frame++) {
    const packets = socket.sent.filter(packet => packet.type === 'input' && packet.frame === frame);
    assert.equal(packets.length, 1, `frame ${frame} is sent exactly once after confirmations outrun prediction`);
    assert.equal(packets[0].input, 9);
  }
  const sentBeforeSync = socket.sent.length;
  socket.receive({ type: 'sync', nextFrame: 5, state: '0' });
  assert.equal(socket.sent.length, sentBeforeSync, 'resync preserves already submitted future inputs');
  assert.equal(client.queued.get(5), 9);
  socket.receive({ type: 'sync', nextFrame: 7, state: '42' }); assert.equal(value, 42); assert.equal(client.session.nextFrame, 7);
  client.disconnect(); assert.equal(active, false); assert.equal(client.connected, false); assert.equal(stopped, 1);
  client.connect('ws://localhost:8080', 'main');
  sockets[1].receive({ type: 'start', slot: 0, version: VERSION, romHash: 'toy', nextFrame: 0, state: '0', inputDelay: 3 });
  client.pump();
  assert.equal(sockets[1].sent.find(packet => packet.type === 'input' && packet.frame === 3).input, 5, 'Player 1 samples controller 1');
  client.disconnect();
  client.connect('ws://localhost:8080', 'main'); sockets[2].receive({ type: 'hello', version: VERSION, romHash: 'different' });
  assert.equal(client.connected, false); assert.equal(active, false);
  assert.throws(() => window.NesNetplay.serverURL('javascript:alert(1)'), /server URL/);
});
