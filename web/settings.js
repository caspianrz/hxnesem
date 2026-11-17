(function (root) {
  'use strict';
  const STORAGE_KEY = 'hxnesem.settings.v1';
  const ACTIONS = ['A', 'B', 'Select', 'Start', 'Up', 'Down', 'Left', 'Right'];
  const DEFAULT_MAPS = [
    ['KeyZ', 'KeyX', 'ShiftLeft', 'Enter', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'],
    ['KeyG', 'KeyH', 'KeyR', 'KeyT', 'KeyW', 'KeyS', 'KeyA', 'KeyD']
  ];
  const defaults = () => ({ version: 1, maps: DEFAULT_MAPS.map(map => map.slice()), volume: 0.7, muted: false });
  function validCode(code) {
    return typeof code === 'string' && /^(Key[A-Z]|Digit[0-9]|Arrow(Up|Down|Left|Right)|Shift(Left|Right)|Control(Left|Right)|Alt(Left|Right)|Meta(Left|Right)|Numpad[A-Za-z0-9]+|F([1-9]|1[0-9]|2[0-4])|Enter|Space|Tab|Backspace|CapsLock|Backquote|Minus|Equal|BracketLeft|BracketRight|Backslash|Semicolon|Quote|Comma|Period|Slash|Insert|Delete|Home|End|PageUp|PageDown|Pause|ScrollLock|NumLock|ContextMenu|IntlBackslash|IntlRo|IntlYen)$/.test(code);
  }
  function normalize(value) {
    const result = defaults();
    if (!value || value.version !== 1) return result;
    if (Array.isArray(value.maps) && value.maps.length === 2 && value.maps.every(map => Array.isArray(map) && map.length === 8 && map.every(validCode))) {
      const flat = value.maps.flat();
      if (new Set(flat).size === flat.length) result.maps = value.maps.map(map => map.slice());
    }
    if (typeof value.volume === 'number' && Number.isFinite(value.volume)) result.volume = Math.max(0, Math.min(1, value.volume));
    if (typeof value.muted === 'boolean') result.muted = value.muted;
    return result;
  }
  function load(storage) {
    try { return { settings: normalize(JSON.parse(storage.getItem(STORAGE_KEY))), persistent: true }; }
    catch (_) { return { settings: defaults(), persistent: false }; }
  }
  function save(storage, settings) {
    try { storage.setItem(STORAGE_KEY, JSON.stringify(normalize(settings))); return true; }
    catch (_) { return false; }
  }
  function bind(settings, port, action, code) {
    if (!validCode(code) || port < 0 || port > 1 || action < 0 || action > 7) throw new Error('Choose a supported keyboard key.');
    const old = settings.maps[port][action];
    let swapped = null;
    settings.maps.forEach((map, p) => map.forEach((key, i) => {
      if (key === code && (p !== port || i !== action)) {
        map[i] = old;
        swapped = { port: p, action: i };
      }
    }));
    settings.maps[port][action] = code;
    return swapped;
  }
  function label(code) {
    const names = { ArrowUp: '↑', ArrowDown: '↓', ArrowLeft: '←', ArrowRight: '→', ShiftLeft: 'Left Shift', ShiftRight: 'Right Shift', Space: 'Space', ControlLeft: 'Left Ctrl', ControlRight: 'Right Ctrl', AltLeft: 'Left Alt', AltRight: 'Right Alt' };
    return names[code] || code.replace(/^Key|^Digit/, '').replace(/([a-z])([A-Z])/g, '$1 $2');
  }
  function mask(map, pressed) {
    return map.reduce((bits, code, i) => pressed.has(code) ? bits | (1 << i) : bits, 0);
  }
  const api = { STORAGE_KEY, ACTIONS, DEFAULT_MAPS, defaults, normalize, validCode, load, save, bind, label, mask };
  root.NesSettings = api;
  if (typeof module !== 'undefined') module.exports = api;
})(typeof window !== 'undefined' ? window : globalThis);
