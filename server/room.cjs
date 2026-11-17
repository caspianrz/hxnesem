'use strict';
const { VERSION, hashState, validFrame, validInput } = require('../web/rollback.js');

/** Each room owns an emulator. Only input masks are accepted from its two assigned peers. */
class Room {
  constructor(core, { inputDelay = 3, futureLimit = 120 } = {}) {
    this.core = core; this.inputDelay = inputDelay; this.futureLimit = futureLimit;
    this.peers = [null, null]; this.pending = [new Map(), new Map()];
    this.nextFrame = 0; this.last = [0, 0]; this.missing = [0, 0];
    this.running = false; this.closed = false; this.state = core.save();
  }
  send(peer, packet) { if (peer) peer.send(packet); }
  join(peer, hello) {
    if (this.closed || this.running) throw new Error('Room is already running');
    if (hello.version !== VERSION || hello.romHash !== this.core.romHash) throw new Error('ROM or emulator version mismatch');
    if (this.peers.includes(peer)) throw new Error('Already joined');
    const slot = this.peers.indexOf(null);
    if (slot < 0) throw new Error('Room is full');
    this.peers[slot] = peer;
    this.send(peer, { type: 'waiting', slot });
    if (this.peers.every(Boolean)) {
      this.running = true;
      this.peers.forEach((client, player) => this.send(client, { type: 'start', slot: player, version: VERSION,
        romHash: this.core.romHash, nextFrame: 0, state: this.state, inputDelay: this.inputDelay }));
    }
    return slot;
  }
  input(peer, packet) {
    const slot = this.peers.indexOf(peer);
    if (slot < 0 || !this.running || !validFrame(packet.frame) || !validInput(packet.input)) return false;
    if (packet.frame < this.nextFrame || packet.frame > this.nextFrame + this.futureLimit || this.pending[slot].has(packet.frame)) return false;
    this.pending[slot].set(packet.frame, packet.input); return true;
  }
  tick() {
    if (!this.running || this.closed) return null;
    const frame = this.nextFrame;
    const inputs = this.last.map((last, slot) => {
      if (this.pending[slot].has(frame)) {
        const value = this.pending[slot].get(frame); this.pending[slot].delete(frame); this.missing[slot] = 0; return value;
      }
      // Short gaps predict held buttons; a stalled client eventually releases them.
      return ++this.missing[slot] > 30 ? 0 : last;
    });
    this.core.step(inputs, false);
    this.state = this.core.save(); this.nextFrame++; this.last = inputs;
    const packet = { type: 'frame', frame, inputs, hash: hashState(this.state) };
    if (this.nextFrame % 120 === 0) packet.state = this.state;
    this.peers.forEach(peer => this.send(peer, packet));
    return packet;
  }
  snapshot(peer) {
    if (!this.peers.includes(peer)) throw new Error('Not in this room');
    this.send(peer, { type: 'sync', nextFrame: this.nextFrame, state: this.state });
  }
  leave(peer) {
    if (!this.peers.includes(peer)) return;
    this.closed = true; this.running = false; this.pending.forEach(queue => queue.clear());
    this.peers.forEach(client => this.send(client, { type: 'ended', reason: 'A player disconnected. Reconnect both players to start a new session.' }));
    this.peers = [null, null];
  }
}
module.exports = { Room };
