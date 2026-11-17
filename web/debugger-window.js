'use strict';
const inspector = window.NesDebugger.mount(document.getElementById('debugger-root'), () => {
  if (!window.opener || window.opener.closed) return null;
  return window.opener.nes || null;
});
window.addEventListener('pagehide', () => inspector.dispose(), { once: true });
