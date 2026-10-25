/* Opt-in host diagnostics. No GL interception/readback, storage or network IO. */
(() => {
  'use strict';
  if (!new URLSearchParams(location.search).has('debug') || globalThis.softgfxDebug) return;
  const capacity = 256, ring = new Array(capacity);
  let total = 0, frames = 0, stopped = false, graphics = null;
  const removers = [];
  const saved = [];
  let nextCapture = 1;
  const clone = value => JSON.parse(JSON.stringify(value));
  let budgets = null, previousUpload = null, budgetMask = 0, unknownUpload = false;
  let breachFrames = 0, episodes = 0, unknownFrames = 0;
  const budgetFrame = (draws, uploaded) => {
    const valid = Number.isSafeInteger(uploaded) && uploaded >= 0 && uploaded < 2147483647;
    const delta = valid && previousUpload !== null && uploaded >= previousUpload ? uploaded-previousUpload : null;
    previousUpload = valid ? uploaded : null;
    if (!budgets) return;
    if (delta === null) unknownFrames++;
    if ((delta === null) !== unknownUpload) {
      unknownUpload = delta === null;
      record('budget-coverage', unknownUpload ? 'upload delta unavailable: baseline/reset/saturation' : 'upload delta available');
    }
    const mask = (draws > budgets.drawCalls ? 1 : 0) | (delta !== null && delta > budgets.uploadBytes ? 2 : 0);
    if (mask) breachFrames++;
    if (mask !== budgetMask) {
      if (mask && !budgetMask) episodes++;
      record(mask ? 'budget-exceeded' : 'budget-recovered', JSON.stringify({frame:frames,mask,draws,uploadDelta:delta}));
      budgetMask = mask;
    }
  };
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
    listen(canvas, event, () => { previousUpload = null; record('context', event); });
  }
  listen(document, 'visibilitychange', () => record('visibility', document.visibilityState));
  const readProfile = () => {
    if (typeof globalThis.softgfxTiming !== 'function') return null;
    try {
      const source = globalThis.softgfxTiming(), result = {};
      for (const key of ['frames','warmupFrames','cpuSamples','gpuSamples','gpuSupported',
        'cpuMedianMs','cpuP95Ms','gpuMedianMs','gpuP95Ms','renderWidth','renderHeight',
        'postUniformCalls','postUniformSkips','drawCalls','cameraUploads','cameraSkips','scale','targetBytes','instanceUploadBytes','instanceUpdates',
        'instanceSkippedUpdates','effectUniformCalls','cullingEnabled','visibleCars',
        'sourceCars','postEnabled','fxaa','contextLost','animated','simulationTicks',
        'simulationStepSeconds','renderAlpha','droppedSimulationSeconds']) {
        const value = source[key];
        if (value === null || typeof value === 'boolean' || (typeof value === 'number' && Number.isFinite(value))) result[key] = value;
      }
      return result;
    } catch { return {unavailable:true}; } // export logs even during failed teardown
  };
  const settingsSnapshot = () => {
    const controls = {};
    for (const id of ['cull-cars','post-enabled','post-fxaa','post-dither','post-scale',
      'auto-scale','env-sky','env-fog','env-shadows']) {
      const e = document.getElementById(id);
      if (!e) continue;
      if (e.type === 'checkbox') controls[id] = !!e.checked;
      else if (e.type === 'range' && Number.isFinite(e.valueAsNumber)) controls[id] = e.valueAsNumber;
    }
    return {controls, width:canvas && Number.isInteger(canvas.width) ? canvas.width : null,
      height:canvas && Number.isInteger(canvas.height) ? canvas.height : null};
  };
  const downloadValue = (value, filename) => {
    const url = URL.createObjectURL(new Blob([JSON.stringify(value, null, 2)], {type:'application/json'}));
    try {
      const a = document.createElement('a'); a.href=url; a.download=filename; a.click();
    } finally { setTimeout(() => URL.revokeObjectURL(url), 1000); }
  };
  const api = {
    attach(gl, apiName) {
      if (stopped) return;
      // One debug-only capability capture, no unmasked renderer/device extension.
      graphics = {api: text(apiName), version: text(gl.getParameter(gl.VERSION)),
        shadingLanguage: text(gl.getParameter(gl.SHADING_LANGUAGE_VERSION)),
        maxTextureSize: gl.getParameter(gl.MAX_TEXTURE_SIZE),
        maxVertexAttributes: gl.getParameter(gl.MAX_VERTEX_ATTRIBS),
        extensions: (gl.getSupportedExtensions() || []).slice(0,128).map(text)};
      record('capabilities', apiName);
    },
    setBudgets(value) {
      if (stopped) return;
      if (value !== null && (!Number.isSafeInteger(value.drawCalls) || value.drawCalls < 0 ||
          !Number.isSafeInteger(value.uploadBytes) || value.uploadBytes < 0)) throw new TypeError('Budgets must be nonnegative safe integers');
      budgets = value === null ? null : {drawCalls:value.drawCalls,uploadBytes:value.uploadBytes};
      previousUpload = null; budgetMask = 0; unknownUpload = false;
      breachFrames = 0; episodes = 0; unknownFrames = 0;
      record('budget-config', budgets ? JSON.stringify(budgets) : 'disabled');
    },
    mark(message) { record('marker', message); },
    // Called after submission. Sample only every 60 frames, never read GL state.
    frame(draws, instances, uploadBytes, skipped) {
      if (stopped) return;
      frames++;
      if (budgets) budgetFrame(draws,uploadBytes);
      if (frames % 60) return;
      record('frame', JSON.stringify({frames, draws, instances, uploadBytes, skipped}));
    },
    snapshot() {
      const events = [];
      for (let i = Math.max(0, total - capacity); i < total; i++) events.push({...ring[i % capacity]});
      return {schemaVersion: 1, scope: 'host diagnostics; not GPU timing', stopped,
        budgets: budgets && {...budgets}, budgetStatus: {mask:budgetMask,breachFrames,episodes,unknownFrames},
        capacity, total, overwritten: Math.max(0,total-capacity), frames,
        userAgent: navigator.userAgent, profile: readProfile(), graphics: graphics && {...graphics, extensions:[...graphics.extensions]}, events};
    },
    capture(label = 'manual') {
      if (stopped) throw new Error('Recorder stopped');
      const name = text(label).slice(0,96);
      const id = nextCapture++;
      record('capture', name);
      const value = {captureVersion:1,id,label:name,scope:'Diagnostic snapshot, NOT deterministic game replay',
        capturedMs:performance.now(),settings:settingsSnapshot(),diagnostics:api.snapshot()};
      saved.push(clone(value));
      if (saved.length > 4) saved.shift();
      return id;
    },
    captures() { return saved.map(c => ({id:c.id,label:c.label,capturedMs:c.capturedMs})); },
    getCapture(id) { const c = saved.find(c => c.id === id); return c ? clone(c) : null; },
    downloadCapture(id) {
      const c = api.getCapture(id);
      if (!c) throw new Error('Capture unavailable (possibly evicted)');
      downloadValue(c,'softgfx-capture-'+c.id+'.json');
    },
    download() { downloadValue(api.snapshot(),'softgfx-debug.json'); },
    stop() { stopped = true; for (const remove of removers.splice(0)) remove(); }
  };
  globalThis.softgfxDebug = Object.freeze(api);
  record('session', 'debug enabled');
  const button = document.createElement('button');
  button.id = 'softgfx-debug-download';
  button.textContent = 'Скачать debug JSON'; button.onclick = () => api.download();
  document.body.appendChild(button);
})();
