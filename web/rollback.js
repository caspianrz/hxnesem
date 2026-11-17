(function (root) {
  'use strict';
  const VERSION = 'hxnesem-rollback-1';
  const FPS = 60.0988;
  function hashState(state) {
    let hash = 0x811c9dc5;
    for (let i = 0; i < state.length; i++) hash = Math.imul(hash ^ state.charCodeAt(i), 0x01000193);
    return (hash >>> 0).toString(16).padStart(8, '0');
  }
  const validFrame = frame => Number.isSafeInteger(frame) && frame >= 0;
  const validInput = input => Number.isInteger(input) && input >= 0 && input <= 255;
  class Rollback {
    constructor(core, slot, { history = 120, maxLead = 8 } = {}) {
      if (slot !== 0 && slot !== 1) throw new Error('Invalid player slot');
      this.core = core; this.slot = slot; this.historyLimit = history; this.maxLead = maxLead;
      this.frames = new Map(); this.rollbacks = 0;
    }
    install(frame, state) {
      if (!validFrame(frame)) throw new Error('Invalid checkpoint frame');
      this.core.load(state); this.state = state; this.nextFrame = frame; this.confirmed = frame - 1;
      this.remote = 0; this.frames.clear();
    }
    canPredict() { return this.nextFrame - this.confirmed - 1 < this.maxLead; }
    advance(inputs, audible) {
      const before = this.state;
      this.core.step(inputs, audible);
      this.state = this.core.save();
      this.frames.set(this.nextFrame, { before, inputs: inputs.slice(), hash: hashState(this.state) });
      this.nextFrame++;
      for (const frame of this.frames.keys()) if (frame < this.nextFrame - this.historyLimit) this.frames.delete(frame);
    }
    predict(local) {
      if (!validInput(local) || !this.canPredict()) return false;
      const pair = [0, 0]; pair[this.slot] = local; pair[1 - this.slot] = this.remote;
      this.advance(pair, true); return true;
    }
    confirm(packet) {
      const { frame, inputs, hash } = packet;
      if (!validFrame(frame) || !Array.isArray(inputs) || inputs.length !== 2 || !inputs.every(validInput) || !/^[0-9a-f]{8}$/.test(hash)) throw new Error('Invalid confirmation');
      if (frame <= this.confirmed) return { duplicate: true };
      if (frame !== this.confirmed + 1) return { resync: true, reason: 'Confirmation gap' };
      if (frame === this.nextFrame) this.advance(inputs, false);
      const entry = this.frames.get(frame);
      if (!entry) return { resync: true, reason: 'Rollback history expired' };
      let rolledBack = false;
      if (entry.inputs[0] !== inputs[0] || entry.inputs[1] !== inputs[1] || entry.hash !== hash) {
        const end = this.nextFrame;
        const future = [];
        for (let f = frame; f < end; f++) {
          const old = this.frames.get(f);
          if (!old) return { resync: true, reason: 'Missing predicted frame' };
          const pair = inputs.slice();
          if (f !== frame) pair[this.slot] = old.inputs[this.slot];
          future.push(pair);
        }
        this.core.load(entry.before); this.state = entry.before; this.nextFrame = frame;
        for (const pair of future) this.advance(pair, false);
        this.rollbacks++; rolledBack = true;
      }
      if (this.frames.get(frame).hash !== hash) return { resync: true, reason: 'State hash mismatch' };
      this.confirmed = frame; this.remote = inputs[1 - this.slot];
      this.frames.delete(frame);
      return { rolledBack };
    }
  }
  const api = { VERSION, FPS, hashState, validFrame, validInput, Rollback };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.NesRollback = api;
})(typeof window !== 'undefined' ? window : globalThis);
