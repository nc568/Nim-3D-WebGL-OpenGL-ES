/* Optional DOM inspector, separate from rendering and from the game's UI toolkit. */
(() => {
 'use strict';
 const api=globalThis.softgfxDebug;
 if(!api) return;
 let timer=null,disposed=false,previewId=null;
 const listeners=[];
 const element=(tag,text,parent)=>{const e=document.createElement(tag);if(text)e.textContent=text;if(parent)parent.appendChild(e);return e;};
 const listen=(e,name,fn)=>{e.addEventListener(name,fn);listeners.push(()=>e.removeEventListener(name,fn));};
 const style=element('style');
 style.textContent='#softgfx-inspector{position:fixed;bottom:12px;right:12px;z-index:10000;width:min(440px,94vw);max-height:70vh;overflow:auto;background:#14222ef5;color:#e7edf4;border:1px solid #6b8a9a;border-radius:8px;padding:10px;font:13px system-ui;box-shadow:0 4px 24px #0008}#softgfx-inspector summary{cursor:pointer;font-weight:bold}#softgfx-inspector button,#softgfx-inspector select,#softgfx-inspector input{margin:4px;padding:5px;max-width:95%}#softgfx-inspector pre{white-space:pre-wrap;overflow-wrap:anywhere;font:12px monospace}#softgfx-inspector .controls{display:flex;flex-wrap:wrap;align-items:center}#softgfx-inspector [role=status]{color:#ffc66d}';
 document.head.appendChild(style);
 const panel=element('details');panel.id='softgfx-inspector';
 element('summary','softgfx · Debug inspector',panel);
 element('p','Диагностика, не FPS. Capture не является replay игры.',panel);
 const controls=element('div','',panel);controls.className='controls';
 const button=(id,text,fn,parent=controls)=>{const e=element('button',text,parent);e.id=id;e.type='button';listen(e,'click',fn);return e;};
 const status=element('p','',panel);status.id='softgfx-inspector-status';status.setAttribute('role','status');
 const summary=element('pre','',panel);summary.id='softgfx-inspector-metrics';
 const safely=fn=>()=>{try{fn();status.textContent='';}catch(e){status.textContent=String(e.message||e);}};
 button('softgfx-inspector-refresh','Обновить',safely(()=>refresh()));
 const autoLabel=element('label','Авто 1 Гц',controls),auto=element('input','',autoLabel);auto.type='checkbox';auto.id='softgfx-inspector-auto';
 const pause=()=>{if(timer!==null){clearInterval(timer);timer=null;}auto.checked=false;};
 listen(auto,'change',()=>{pauseTimer();if(auto.checked)timer=setInterval(()=>{if(panel.open&&!document.hidden)safely(refresh)();},1000);});
 function pauseTimer(){if(timer!==null){clearInterval(timer);timer=null;}}
 const filter=element('select','',panel);filter.id='softgfx-inspector-filter';filter.setAttribute('aria-label','Фильтр событий');
 for(const [value,text] of [['all','Все события'],['problems','Ошибки / context / budgets'],['capture','Capture'],['marker','Маркеры'],['frame','Samples кадров']]) {
  const option=element('option',text,filter);option.value=value;
 }
 const events=element('pre','',panel);events.id='softgfx-inspector-events';
 const budgetBox=element('fieldset','',panel);element('legend','Диагностические бюджеты (не меняют качество)',budgetBox);
 const number=(id,text,value)=>{const label=element('label',text,budgetBox),input=element('input','',label);input.type='number';input.min='0';input.step='1';input.value=String(value);input.id=id;return input;};
 const draws=number('softgfx-budget-draws','Draw calls',16),bytes=number('softgfx-budget-bytes','Instance bytes',65536);
 const apply=button('softgfx-budget-apply','Применить',safely(()=>{api.setBudgets({drawCalls:draws.valueAsNumber,uploadBytes:bytes.valueAsNumber});refresh();}),budgetBox);
 const disable=button('softgfx-budget-disable','Отключить',safely(()=>{api.setBudgets(null);refresh();}),budgetBox);
 const captureLabel=element('label','Название capture',panel),name=element('input','',captureLabel);name.id='softgfx-capture-label';name.maxLength=96;name.value='manual';
 const capture=button('softgfx-capture','Сохранить capture',safely(()=>{const id=api.capture(name.value);refresh(id);}),panel);
 const saved=element('select','',panel);saved.id='softgfx-capture-list';saved.setAttribute('aria-label','Сохранённые captures (последние 4)');
 const preview=element('pre','',panel);preview.id='softgfx-capture-preview';
 button('softgfx-capture-export','Скачать capture',safely(()=>api.downloadCapture(Number(saved.value))),panel);
 const oldDownload=document.getElementById('softgfx-debug-download');
 if(oldDownload)panel.appendChild(oldDownload);
 const stop=button('softgfx-inspector-stop','Остановить журнал',()=>{api.stop();pause();refresh();status.textContent='Журнал остановлен. Сохранённые captures доступны для экспорта.';},panel);
 function showCapture(){
  const id=Number(saved.value);if(id===previewId)return;previewId=id;
  const c=api.getCapture(id);
  preview.textContent=c?JSON.stringify({id:c.id,label:c.label,capturedMs:c.capturedMs,settings:c.settings,profile:c.diagnostics.profile},null,2):'Capture не выбран';
 }
 function refresh(selectedId){
  if(disposed)return;
  const s=api.snapshot(),p=s.profile||{};
  const metric=v=>v===null||v===undefined?'нет данных':String(v);
  summary.textContent=[`API: ${s.graphics?.api||'инициализация'} · кадров ${s.frames} · записей ${s.events.length}/${s.capacity}, вытеснено ${s.overwritten}`,
   `CPU median/p95: ${metric(p.cpuMedianMs)} / ${metric(p.cpuP95Ms)} мс (${metric(p.cpuSamples)} samples)`,
   `GPU median/p95: ${metric(p.gpuMedianMs)} / ${metric(p.gpuP95Ms)} мс (${metric(p.gpuSamples)} samples)`,
   `Draws: ${metric(p.drawCalls)} · видимо: ${metric(p.visibleCars)} · target bytes: ${metric(p.targetBytes)}`,
   `Instance uploads bytes: ${metric(p.instanceUploadBytes)} · skips: ${metric(p.instanceSkippedUpdates)}`,
   `Camera calls/skips: ${metric(p.cameraUploads)} / ${metric(p.cameraSkips)}`,
   `Post calls/skips: ${metric(p.postUniformCalls)} / ${metric(p.postUniformSkips)}`,
   `Budgets: ${s.budgets?JSON.stringify(s.budgets):'отключены'} · mask ${s.budgetStatus.mask}`,
   `Превышений: ${s.budgetStatus.breachFrames} кадров / ${s.budgetStatus.episodes} эпизодов · неизвестный upload delta: ${s.budgetStatus.unknownFrames}`].join('\n');
  const rows=s.events.filter(e=>filter.value==='all'||(filter.value==='problems'?['error','rejection','context'].includes(e.kind)||e.kind.startsWith('budget-'):e.kind===filter.value)).slice(-40);
  events.textContent=rows.map(e=>`${e.sequence} · ${e.kind} · ${e.message}`).join('\n')||'Нет событий для фильтра';
  const id=selectedId===undefined?Number(saved.value):selectedId;
  saved.replaceChildren();
  for(const c of api.captures()){const option=element('option',`${c.id} · ${c.label}`,saved);option.value=String(c.id);}
  if(api.captures().some(c=>c.id===id))saved.value=String(id);
  showCapture();
  capture.disabled=apply.disabled=disable.disabled=stop.disabled=auto.disabled=s.stopped;
  if(s.stopped)pause();
 }
 listen(filter,'change',safely(refresh));listen(saved,'change',safely(showCapture));
 listen(panel,'toggle',()=>{if(panel.open)safely(refresh)();});
 listen(window,'pagehide',pause);
 const dispose=()=>{if(disposed)return;pause();disposed=true;for(const remove of listeners.splice(0))remove();panel.remove();style.remove();if(globalThis.softgfxInspector===handle)delete globalThis.softgfxInspector;};
 const handle=Object.freeze({refresh,dispose});
 globalThis.softgfxInspector=handle;
 document.body.appendChild(panel);refresh();
})();
