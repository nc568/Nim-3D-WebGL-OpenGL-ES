/* Opt-in host diagnostics. No GL interception/readback, storage or network IO. */
(() => {
  'use strict';
  if (!new URLSearchParams(location.search).has('debug')) return;
  const capacity = 256, ring = new Array(capacity);
  let total = 0, frames = 0, stopped = false;
  const removers = [];
  // Intentionally omit location, stack URLs, arbitrary objects and user payloads.
  const text = value => typeof value === 'string' ? value.slice(0, 512) : typeof value;
  const record = (kind, message) => {
    if (stopped) return;
    ring[total % capacity] = {sequence: total, ms: performance.now(), kind, message: text(message)};
    total++;
  };
  const listen = (target, event, cb) => {
    target.addEventListener(event, cb);
    removers.push(() => target.removeEventListener(event, cb));
  };
  listen(window, 'error', e => record('error', e.message || 'resource error'));
  listen(window, 'unhandledrejection', e => record('rejection', typeof e.reason === 'string' ? e.reason : 'unhandled rejection (object omitted)'));
  const canvas = document.getElementById('scene');
  if (canvas) for (const event of ['webglcontextlost', 'webglcontextrestored', 'webglcontextcreationerror']) {
    listen(canvas, event, () => record('context', event));
  }
  listen(document, 'visibilitychange', () => record('visibility', document.visibilityState));
  const api = {
    mark(message) { record('marker', message); },
    // Called after submission. Sample only every 60 frames, never read GL state.
    frame(draws, instances, uploadBytes, skipped) {
      if (stopped || ++frames % 60) return;
      record('frame', JSON.stringify({frames, draws, instances, uploadBytes, skipped}));
    },
    snapshot() {
      const events = [];
      for (let i = Math.max(0, total - capacity); i < total; i++) events.push({...ring[i % capacity]});
      return {schemaVersion: 1, scope: 'host diagnostics; not GPU timing',
        capacity, total, overwritten: Math.max(0,total-capacity), frames,
        userAgent: navigator.userAgent, events};
    },
    download() {
      const url = URL.createObjectURL(new Blob([JSON.stringify(api.snapshot(), null, 2)], {type:'application/json'}));
      const a = document.createElement('a'); a.href=url; a.download='softgfx-debug.json'; a.click();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
    },
    stop() { stopped = true; for (const remove of removers.splice(0)) remove(); }
  };
  globalThis.softgfxDebug = Object.freeze(api);
  record('session', 'debug enabled');
  const button = document.createElement('button');
  button.textContent = 'Скачать debug JSON'; button.onclick = () => api.download();
  document.body.appendChild(button);
})();
