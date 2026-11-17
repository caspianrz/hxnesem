(function () {
  'use strict';
  const $ = id => document.getElementById(id);
  const config = window.NesSettings;
  let storage;
  try { storage = window.localStorage; } catch (_) { storage = null; }
  const saved = config.load(storage);
  let settings = saved.settings;
  let api = null;
  let binding = null;
  let restorePlayback = false;
  let fileRequest = 0;
  let inspector = null;
  let popup = null;
  let dragDepth = 0;
  const pressed = new Set();
  const dialog = $('settings');
  const message = $('message');
  function notify(text, error = false) {
    message.textContent = text;
    message.dataset.error = String(error);
  }
  function clearInput() {
    pressed.clear();
    if (api) { api.setController(0, 0); api.setController(0, 1); }
  }
  function sendInput() {
    if (!api) return;
    settings.maps.forEach((map, port) => api.setController(config.mask(map, pressed), port));
  }
  function persist() {
    const ok = config.save(storage, settings);
    $('mapping-message').textContent = ok ? 'Saved automatically in this browser.' : 'Browser storage is unavailable. Changes apply for this session only.';
    if (!ok) notify('Settings apply for this session; browser storage is unavailable.', true);
  }
  function refreshAudio() {
    $('volume').value = Math.round(settings.volume * 100);
    $('volume-value').value = Math.round(settings.volume * 100) + '%';
    $('mute').textContent = settings.muted ? 'Unmute' : 'Mute';
    $('mute').setAttribute('aria-pressed', String(settings.muted));
    if (api) { api.setVolume(settings.volume); api.setMuted(settings.muted); }
  }
  function refreshSummary() {
    $('control-summary').textContent = 'P1 · A: ' + config.label(settings.maps[0][0]) + ' · B: ' + config.label(settings.maps[0][1]) + ' · Start: ' + config.label(settings.maps[0][3]);
  }
  function renderMappings() {
    const port = Number($('controller-port').value);
    const list = $('key-map'); list.replaceChildren();
    config.ACTIONS.forEach((action, index) => {
      const row = document.createElement('div'); row.className = 'key-row';
      const name = document.createElement('span'); name.textContent = action;
      const button = document.createElement('button'); button.type = 'button';
      const listening = binding && binding.port === port && binding.action === index;
      button.textContent = listening ? 'Press a key…' : config.label(settings.maps[port][index]);
      button.setAttribute('aria-label', 'Map ' + action + ', currently ' + config.label(settings.maps[port][index]));
      if (listening) button.className = 'capturing';
      button.addEventListener('click', () => {
        clearInput(); binding = { port, action: index }; renderMappings();
        list.children[index].querySelector('button').focus();
        $('mapping-message').textContent = 'Press a key for ' + action + '. Escape cancels.';
      });
      row.append(name, button); list.append(row);
    });
    refreshSummary();
  }
  function stateChanged() {
    if (!api) return;
    const state = api.getState();
    $('pause').disabled = $('reset').disabled = !state.loaded;
    $('pause').textContent = state.paused ? 'Resume' : 'Pause';
    $('run-state').textContent = state.loaded ? (state.paused ? 'Paused' : 'Running') + ' · Mapper ' + state.mapper : 'Ready';
    $('empty-state').hidden = state.loaded;
    if (state.paused) clearInput();
    if (inspector) inspector.refresh();
  }
  function tryAction(action) {
    if (!api) return;
    try { clearInput(); action(); stateChanged(); }
    catch (error) { notify('Emulator stopped: ' + (error.message || String(error)), true); stateChanged(); }
  }
  async function loadFile(file) {
    if (!file) return;
    if (!api) { notify('The emulator is still starting. Try again in a moment.', true); return; }
    const request = ++fileRequest;
    if (!/\.nes$/i.test(file.name)) { notify('Choose a .nes ROM file.', true); return; }
    clearInput(); notify('Loading ' + file.name + '…');
    try {
      const data = await file.arrayBuffer();
      if (request !== fileRequest) return;
      api.loadRom(data);
      refreshAudio();
      $('rom-name').textContent = file.name;
      $('rom-name').title = file.name;
      notify('Loaded ' + file.name + '. Click the screen to play.');
      stateChanged(); $('webgl').focus();
    } catch (error) {
      if (request === fileRequest) notify('Could not load ROM: ' + (error.message || String(error)), true);
    }
  }
  function attach() {
    if (!window.nes) return;
    api = window.nes; refreshAudio(); stateChanged();
    notify(saved.persistent ? 'Open a .nes ROM to begin.' : 'Open a ROM to begin. Settings may not persist in this browser.');
  }
  $('open-rom').addEventListener('click', () => $('rom').click());
  $('empty-open').addEventListener('click', () => $('rom').click());
  $('rom').addEventListener('change', event => { const file = event.target.files[0]; event.target.value = ''; loadFile(file); });
  $('pause').addEventListener('click', () => tryAction(() => api.setPaused(!api.getState().paused)));
  $('reset').addEventListener('click', () => tryAction(() => { api.reset(); notify('ROM reset.'); }));
  $('mute').addEventListener('click', () => { settings.muted = !settings.muted; refreshAudio(); persist(); });
  $('volume').addEventListener('input', () => { settings.volume = Number($('volume').value) / 100; refreshAudio(); persist(); });
  $('settings-open').addEventListener('click', () => {
    clearInput(); binding = null;
    restorePlayback = !!(api && api.getState().loaded && !api.getState().paused);
    if (restorePlayback) api.setPaused(true);
    renderMappings(); dialog.showModal(); stateChanged();
  });
  dialog.addEventListener('close', () => {
    clearInput(); binding = null;
    if (restorePlayback && api) api.setPaused(false);
    restorePlayback = false; stateChanged(); $('webgl').focus();
  });
  $('controller-port').addEventListener('change', () => { binding = null; renderMappings(); });
  $('restore-controls').addEventListener('click', () => {
    clearInput(); binding = null; settings.maps = config.defaults().maps; renderMappings(); persist();
  });
  document.addEventListener('keydown', event => {
    if (binding) {
      event.preventDefault(); event.stopImmediatePropagation();
      if (event.repeat) return;
      if (event.code === 'Escape') { binding = null; renderMappings(); $('mapping-message').textContent = 'Mapping cancelled.'; return; }
      const { port, action } = binding;
      try {
        const swapped = config.bind(settings, port, action, event.code);
        binding = null; renderMappings(); persist();
        if (swapped) $('mapping-message').textContent += ' Swapped with Player ' + (swapped.port + 1) + ' ' + config.ACTIONS[swapped.action] + '.';
      } catch (error) { $('mapping-message').textContent = error.message; }
      return;
    }
    if (dialog.open || !api || !api.getState().loaded || api.getState().paused) return;
    if (event.target !== $('webgl') && event.target !== document.body && event.target !== $('screen')) return;
    // Leave browser shortcuts intact. Modifier keys can still be mapped on their own.
    if (event.metaKey || event.ctrlKey || event.altKey) {
      if (!/^(Control|Alt|Meta)(Left|Right)$/.test(event.code)) { clearInput(); return; }
    }
    if (!settings.maps.some(map => map.includes(event.code))) return;
    event.preventDefault(); pressed.add(event.code); sendInput();
  }, true);
  document.addEventListener('keyup', event => { pressed.delete(event.code); sendInput(); }, true);
  window.addEventListener('blur', clearInput);
  document.addEventListener('visibilitychange', clearInput);
  $('webgl').addEventListener('pointerdown', () => $('webgl').focus());
  function closeInspector() {
    if (inspector) inspector.dispose(); inspector = null;
    $('cpu-panel').hidden = true; $('debug-toggle').setAttribute('aria-expanded', 'false');
  }
  $('debug-toggle').addEventListener('click', () => {
    if (!$('cpu-panel').hidden) { closeInspector(); return; }
    $('cpu-panel').hidden = false; $('debug-toggle').setAttribute('aria-expanded', 'true');
    inspector = window.NesDebugger.mount($('debugger-root'), () => api, stateChanged);
  });
  $('debug-close').addEventListener('click', closeInspector);
  $('debug-popout').addEventListener('click', () => {
    if (popup && !popup.closed) { popup.focus(); return; }
    popup = window.open('debugger.html', 'hxnesem-cpu', 'popup,width=520,height=760');
    if (!popup) { notify('The CPU window was blocked. Allow pop-ups or use the docked inspector.', true); return; }
    clearInput(); closeInspector();
  });
  // Prevent the browser from navigating away when a ROM is dropped outside the canvas.
  window.addEventListener('dragover', event => { if (Array.from(event.dataTransfer.types).includes('Files')) event.preventDefault(); });
  window.addEventListener('drop', event => { event.preventDefault(); dragDepth = 0; $('drop-hint').hidden = true; });
  const screen = $('screen');
  screen.addEventListener('dragenter', event => {
    if (Array.from(event.dataTransfer.types).includes('Files')) { event.preventDefault(); dragDepth++; $('drop-hint').hidden = false; }
  });
  screen.addEventListener('dragleave', () => { dragDepth = Math.max(0, dragDepth - 1); if (!dragDepth) $('drop-hint').hidden = true; });
  screen.addEventListener('dragover', event => { event.preventDefault(); event.dataTransfer.dropEffect = 'copy'; });
  screen.addEventListener('drop', event => { event.preventDefault(); loadFile(event.dataTransfer.files[0]); });
  window.addEventListener('nes-ready', attach);
  window.addEventListener('nes-error', event => { clearInput(); notify('CPU paused: ' + event.detail, true); stateChanged(); });
  window.addEventListener('pagehide', () => { clearInput(); if (inspector) inspector.dispose(); });
  setInterval(() => { if (api && !document.hidden) stateChanged(); }, 250);
  refreshAudio(); renderMappings();
  if (window.nes) attach();
})();
