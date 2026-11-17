(function (root) {
  'use strict';
  const hex = (value, width = 2) => '$' + (value >>> 0).toString(16).toUpperCase().padStart(width, '0');
  function mount(element, getAPI, onChange = () => {}) {
    element.innerHTML = `<div class="debug-content">
      <div class="debug-actions"><button type="button" data-action="pause">Pause</button><button type="button" data-action="step">Step instruction</button><button type="button" data-action="reset">Reset</button></div>
      <p class="debug-note">Load a ROM to inspect the CPU.</p>
      <dl class="registers">${['PC', 'A', 'X', 'Y', 'SP', 'P', 'Mapper', 'Cycles'].map(name => `<div><dt>${name}</dt><dd data-register="${name}">—</dd></div>`).join('')}</dl>
      <p class="cpu-flags">NV–BDIZC · —</p>
      <table class="code-table"><thead><tr><th scope="col">Address</th><th scope="col">Bytes</th><th scope="col">Instruction</th></tr></thead><tbody></tbody></table>
      <p class="debug-error" role="status"></p>
    </div>`;
    const buttons = Array.from(element.querySelectorAll('[data-action]'));
    const pause = element.querySelector('[data-action=pause]');
    const note = element.querySelector('.debug-note');
    const error = element.querySelector('.debug-error');
    const table = element.querySelector('tbody');
    let state = null;
    let lastRows = '';
    let disposed = false;
    function refresh() {
      if (disposed) return;
      let api;
      try { api = getAPI(); state = api ? api.getState() : null; }
      catch (_) { state = null; }
      buttons.forEach(button => { button.disabled = !state || !state.loaded || state.netplay; });
      pause.textContent = state && state.paused ? 'Resume' : 'Pause';
      if (!state || !state.loaded) {
        note.textContent = api ? 'Load a ROM to inspect the CPU.' : 'The main emulator is not connected. Open this window from CPU inspector.';
        table.replaceChildren(); lastRows = '';
        return;
      }
      note.textContent = state.netplay ? 'Netplay · live inspection only. Disconnect to pause, reset or step.' : state.paused ? 'Paused · next instruction highlighted. Step to advance.' : 'Live · pause to inspect or step. Next instruction highlighted.';
      const registers = { PC: hex(state.pc, 4), A: hex(state.a), X: hex(state.x), Y: hex(state.y), SP: hex(state.sp), P: hex(state.status), Mapper: String(state.mapper), Cycles: String(state.cycles) };
      for (const [name, value] of Object.entries(registers)) element.querySelector(`[data-register="${name}"]`).textContent = value;
      element.querySelector('.cpu-flags').textContent = 'NV–BDIZC · ' + state.status.toString(2).padStart(8, '0');
      const signature = JSON.stringify(state.instructions);
      if (signature !== lastRows) {
        table.replaceChildren();
        state.instructions.forEach((line, i) => {
          const row = document.createElement('tr');
          if (i === 0) { row.className = 'current'; row.setAttribute('aria-current', 'true'); }
          for (const value of [hex(line.address, 4), line.bytes, line.code]) {
            const cell = document.createElement('td'); cell.textContent = value; row.append(cell);
          }
          table.append(row);
        });
        lastRows = signature;
      }
    }
    buttons.forEach(button => button.addEventListener('click', () => {
      try {
        const api = getAPI(); if (!api) return;
        if (button.dataset.action === 'pause') api.setPaused(!api.getState().paused);
        else if (button.dataset.action === 'step') api.step();
        else api.reset();
        error.textContent = ''; refresh(); onChange();
      } catch (exception) {
        error.textContent = 'CPU stopped: ' + (exception.message || String(exception)); refresh(); onChange();
      }
    }));
    refresh();
    const timer = setInterval(() => { if (!document.hidden) refresh(); }, 150);
    return { refresh, dispose() { disposed = true; clearInterval(timer); element.replaceChildren(); } };
  }
  root.NesDebugger = { mount };
})(window);
