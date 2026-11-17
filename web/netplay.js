(function (root) {
  'use strict';
  const { VERSION, FPS, Rollback, validFrame } = root.NesRollback;
  function serverURL(value) {
    const url = new URL(value, root.location.href);
    if (url.protocol === 'http:') url.protocol = 'ws:';
    if (url.protocol === 'https:') url.protocol = 'wss:';
    if (!['ws:', 'wss:'].includes(url.protocol)) throw new Error('Use a ws:// or wss:// server URL');
    if (url.username || url.password || url.search || url.hash) throw new Error('Use a server URL without credentials, query or fragment');
    if (!url.pathname || url.pathname === '/') url.pathname = '/netplay';
    return url.href;
  }
  class Client {
    constructor(api, onStatus = () => {}) {
      this.api = api; this.onStatus = onStatus; this.socket = null; this.timer = null;
      this.session = null; this.queued = new Map(); this.syncing = false; this.delay = 3;
    }
    get connected() { return this.socket !== null; }
    connect(address, room, token = '') {
      if (this.connected) throw new Error('Disconnect the current session first');
      if (!this.api.getState().loaded) throw new Error('Load the same .nes ROM as the server first');
      if (!/^[a-zA-Z0-9_-]{1,32}$/.test(room)) throw new Error('Enter a room name using letters, numbers, underscores or hyphens');
      const socket = new root.WebSocket(serverURL(address));
      this.socket = socket; this.report('Connecting…');
      const timeout = setTimeout(() => { if (!this.session) this.disconnect('Connection timed out; returned to single-player.'); }, 15000);
      socket.onmessage = event => {
        if (this.socket !== socket) return;
        try {
          const packet = JSON.parse(event.data);
          if (packet.type === 'hello') {
            if (packet.version !== VERSION || packet.romHash !== this.api.romHash()) throw new Error('ROM or emulator version does not match the server');
            this.send({ type: 'join', version: VERSION, romHash: this.api.romHash(), room, token });
          } else if (packet.type === 'waiting') {
            clearTimeout(timeout); this.report('Waiting for a second player in room ' + room + '…');
          } else if (packet.type === 'start') {
            clearTimeout(timeout);
            if (packet.version !== VERSION || packet.romHash !== this.api.romHash() || ![0, 1].includes(packet.slot) || !Number.isInteger(packet.inputDelay) || packet.inputDelay < 1 || packet.inputDelay > 8) throw new Error('Invalid session configuration');
            this.api.netplayStart();
            this.session = new Rollback({ save: () => this.api.netplaySave(), load: state => this.api.netplayLoad(state), step: (pair, audible) => this.api.netplayFrame(pair, audible) }, packet.slot);
            this.delay = packet.inputDelay;
            this.install(packet.nextFrame, packet.state);
            this.deadline = performance.now();
            this.timer = setInterval(() => this.pump(), 4);
            this.report('Connected as Player ' + (packet.slot + 1) + ' · ' + room);
          } else if (packet.type === 'frame' && this.session && !this.syncing) {
            const result = this.session.confirm(packet);
            if (result.resync) {
              if (packet.state) this.install(packet.frame + 1, packet.state);
              else { this.syncing = true; this.send({ type: 'resync' }); this.report('Synchronizing with server…'); }
            }
            this.prune();
          } else if (packet.type === 'sync' && this.session) {
            this.install(packet.nextFrame, packet.state); this.report('Resynchronized as Player ' + (this.session.slot + 1));
          } else if (packet.type === 'ended' || packet.type === 'error') this.disconnect(packet.reason + ' Single-player is available.');
        } catch (error) { this.disconnect('Netplay stopped: ' + (error.message || String(error))); }
      };
      socket.onclose = () => { clearTimeout(timeout); if (this.socket === socket) this.disconnect('Server disconnected; returned to single-player.'); };
      socket.onerror = () => { if (this.socket === socket) this.disconnect('Could not connect to the server; single-player is available.'); };
    }
    send(packet) { if (this.socket && this.socket.readyState === 1) this.socket.send(JSON.stringify(packet)); }
    report(text) { this.onStatus(text, this); }
    install(frame, state) {
      if (!validFrame(frame) || typeof state !== 'string') throw new Error('Invalid server checkpoint');
      this.session.install(frame, state); this.syncing = false;
      for (const f of this.queued.keys()) if (f < frame) this.queued.delete(f);
      this.nextInputFrame = frame;
      for (let f = frame; f < frame + this.delay; f++) {
        if (!this.queued.has(f)) { this.queued.set(f, 0); this.send({ type: 'input', frame: f, input: 0 }); }
        this.nextInputFrame = f + 1;
      }
      this.deadline = performance.now();
    }
    prune() { for (const frame of this.queued.keys()) if (frame <= this.session.confirmed) this.queued.delete(frame); }
    pump() {
      if (!this.session || this.syncing) return;
      try {
        const now = performance.now(); let count = 0;
        while (now >= this.deadline && count++ < 3 && this.session.canPredict()) {
          const frame = this.session.nextFrame;
          // Sample the local keyboard once per future frame; never re-sample during replay.
          const target = frame + this.delay;
          // Confirmations can advance nextFrame without prediction. Fill every
          // unsent frame so a slow browser cannot leave holes in the input stream.
          this.nextInputFrame = Math.max(this.nextInputFrame, this.session.confirmed + 1);
          while (this.nextInputFrame <= target) {
            const f = this.nextInputFrame++;
            if (this.queued.has(f)) continue;
            const input = this.api.localInput(this.session.slot) & 255;
            this.queued.set(f, input); this.send({ type: 'input', frame: f, input });
          }
          this.session.predict(this.queued.get(frame) || 0);
          this.deadline += 1000 / FPS;
        }
        if (now - this.deadline > 250) this.deadline = now;
      } catch (error) { this.disconnect('Emulation stopped: ' + (error.message || String(error))); }
    }
    disconnect(reason = 'Disconnected; single-player is available.') {
      const socket = this.socket; this.socket = null;
      if (socket) { socket.onmessage = socket.onclose = socket.onerror = null; socket.close(); }
      clearInterval(this.timer); this.timer = null;
      if (this.session) this.api.netplayStop();
      this.session = null; this.queued.clear(); this.syncing = false;
      this.report(reason);
    }
  }
  root.NesNetplay = { Client, serverURL };
})(window);
