'use strict';
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const { performance } = require('node:perf_hooks');
const { WebSocketServer } = require('ws');
const { Room } = require('./room.cjs');
const { FPS, VERSION } = require('../web/rollback.js');
const factory = require('./core.cjs');

function argumentsFrom(args) {
  const config = { host: '127.0.0.1', port: 8080, maxRooms: 4, origins: [] };
  for (let i = 0; i < args.length; i += 2) {
    const key = args[i]; const value = args[i + 1];
    if (!value) throw new Error(`Missing value for ${key}`);
    if (key === '--rom') config.rom = path.resolve(value);
    else if (key === '--host') config.host = value;
    else if (key === '--port') config.port = Number(value);
    else if (key === '--max-rooms') config.maxRooms = Number(value);
    else if (key === '--origin') config.origins.push(new URL(value).origin);
    else throw new Error(`Unknown option ${key}`);
  }
  if (!config.rom) throw new Error('Usage: npm start -- --rom /path/game.nes [--host 0.0.0.0] [--port 8080] [--origin http://localhost:8000]');
  if (!Number.isInteger(config.port) || config.port < 1 || config.port > 65535 || !Number.isInteger(config.maxRooms) || config.maxRooms < 1 || config.maxRooms > 16) throw new Error('Invalid port or room limit');
  return config;
}
function main(args) {
  const config = argumentsFrom(args);
  const bytes = fs.readFileSync(config.rom);
  const rom = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
  const romHash = factory.create(rom).romHash; // Validate the cartridge before accepting connections.
  const rooms = new Map();
  const root = path.resolve(__dirname, '../web');
  const mime = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.map': 'application/json' };
  const server = http.createServer((request, response) => {
    if (request.method !== 'GET' && request.method !== 'HEAD') { response.writeHead(405); response.end(); return; }
    let file;
    try {
      const pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
      file = path.resolve(root, '.' + (pathname === '/' ? '/index.html' : pathname));
      if (!file.startsWith(root + path.sep) || !mime[path.extname(file)]) throw new Error();
    } catch (_) { response.writeHead(404); response.end(); return; }
    fs.stat(file, (error, stat) => {
      if (error || !stat.isFile()) { response.writeHead(404); response.end(); return; }
      response.writeHead(200, { 'Content-Type': mime[path.extname(file)], 'Content-Length': stat.size, 'Cache-Control': 'no-cache' });
      if (request.method === 'HEAD') response.end();
      else { const stream = fs.createReadStream(file); stream.on('error', () => response.destroy()); stream.pipe(response); }
    });
  });
  const sockets = new WebSocketServer({ noServer: true, maxPayload: 4096, perMessageDeflate: false });
  server.on('upgrade', (request, socket, head) => {
    const origin = request.headers.origin;
    const sameHost = origin && (() => { try { return new URL(origin).host === request.headers.host; } catch (_) { return false; } })();
    if (request.url !== '/netplay' || (origin && !sameHost && !config.origins.includes(origin))) {
      socket.write('HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n'); socket.destroy(); return;
    }
    sockets.handleUpgrade(request, socket, head, ws => sockets.emit('connection', ws, request));
  });
  sockets.on('connection', ws => {
    let room = null; let name = null; let count = 0; let windowStart = performance.now(); let lastSync = -Infinity;
    const peer = { send(packet) {
      if (ws.readyState !== 1) return;
      if (ws.bufferedAmount > 2 * 1024 * 1024) { ws.close(1013, 'Client cannot keep up'); return; }
      ws.send(JSON.stringify(packet));
    } };
    ws.alive = true; ws.on('pong', () => { ws.alive = true; });
    const handshake = setTimeout(() => { if (!room) ws.close(1008, 'Join timeout'); }, 10000);
    peer.send({ type: 'hello', version: VERSION, romHash, romName: path.basename(config.rom) });
    ws.on('message', (raw, binary) => {
      try {
        const now = performance.now();
        if (now - windowStart > 1000) { count = 0; windowStart = now; }
        if (++count > 300 || binary) throw new Error('Message rate or format rejected');
        const packet = JSON.parse(raw.toString());
        if (packet.type === 'join' && !room) {
          if (process.env.NETPLAY_TOKEN && packet.token !== process.env.NETPLAY_TOKEN) throw new Error('Invalid server token');
          if (typeof packet.room !== 'string' || !/^[a-zA-Z0-9_-]{1,32}$/.test(packet.room)) throw new Error('Room must be 1–32 letters, numbers, underscores or hyphens');
          if (packet.version !== VERSION || packet.romHash !== romHash) throw new Error('Load the same ROM and emulator version as the server');
          name = packet.room;
          let target = rooms.get(name);
          if (!target) {
            if (rooms.size >= config.maxRooms) throw new Error('Server room limit reached');
            target = new Room(factory.create(rom)); rooms.set(name, target);
          }
          target.join(peer, packet); room = target; clearTimeout(handshake);
          if (room.running && room.deadline == null) room.deadline = now + room.inputDelay * 1000 / FPS;
        } else if (packet.type === 'input' && room) room.input(peer, packet);
        else if (packet.type === 'resync' && room && now - lastSync >= 1000) { lastSync = now; room.snapshot(peer); }
        else throw new Error('Unexpected message');
      } catch (error) { peer.send({ type: 'error', reason: error.message || String(error) }); ws.close(1008, 'Netplay request rejected'); }
    });
    ws.on('error', () => {});
    ws.on('close', () => {
      clearTimeout(handshake);
      if (room) { room.leave(peer); if (rooms.get(name) === room) rooms.delete(name); }
    });
  });
  const timer = setInterval(() => {
    const now = performance.now();
    for (const [name, room] of rooms) {
      if (!room.running) continue;
      try {
        let catchUp = 0;
        while (now >= room.deadline && catchUp++ < 2) { room.tick(); room.deadline += 1000 / FPS; }
        if (now - room.deadline > 250) room.deadline = now + 1000 / FPS;
      } catch (error) {
        room.peers.forEach(peer => room.send(peer, { type: 'error', reason: 'Server emulation stopped: ' + (error.message || String(error)) }));
        room.closed = true; room.running = false; rooms.delete(name);
      }
    }
  }, 4);
  const heartbeat = setInterval(() => {
    for (const ws of sockets.clients) { if (!ws.alive) ws.terminate(); else { ws.alive = false; ws.ping(); } }
  }, 5000);
  server.listen(config.port, config.host, () => console.log(`hxnesem authoritative server: http://${config.host}:${config.port} · ROM ${path.basename(config.rom)} · ${romHash}`));
  function shutdown() { clearInterval(timer); clearInterval(heartbeat); for (const ws of sockets.clients) ws.terminate(); sockets.close(); server.close(); }
  process.once('SIGINT', shutdown); process.once('SIGTERM', shutdown);
  return { server, sockets, rooms, shutdown };
}
if (require.main === module) {
  try { main(process.argv.slice(2)); } catch (error) { console.error(error.message); process.exitCode = 1; }
}
module.exports = { main, argumentsFrom };
