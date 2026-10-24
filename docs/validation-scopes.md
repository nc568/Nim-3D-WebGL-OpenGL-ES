# Срез 16: explicit per-context scope arbitration

`softgfx/scopes` содержит `ContextScopes` и два независимых channels: frame/query.
Host создаёт **один** guard на реальный GL context и передаёт его всем участвующим
pipelines и GPU timers:

```nim
let scopes = newContextScopes()
var pipeline = initPipeline(context, caps, scopes=scopes)
var timer = initGpuTimer(timerDriver, scopes)
```

Для существующих клиентов параметры optional: nil сохраняет старый режим без
arbitration. Demo явно использует shared guard и создаёт новый после restore.
Нельзя создавать разные guards для одного context и ожидать mutual exclusion.

## Правила

- Разные pipelines не могут открыть overlapping frames; чужой active frame также
  запрещает dispose pipeline. Rejection происходит до allocation/GL calls.
- Разные timers не могут одновременно begin elapsed query; poll/dispose чужого
  timer во время active query также отвергаются до вызовов драйвера.
- Frame и query независимы: query может охватывать begin/draw/endFrame. Между
  кадрами допустимы несколько последовательных measurements. Frame IDs не являются
  проверяемыми clock generations; связь sample и simulation frame задаёт host.
- Пустая поверхность, validation error и успешный end/cancel освобождают frame
  claim; successful endSample освобождает query claim. Обычный dispose не отравляет
  shared guard. Alias одного owner не становится новым scope owner.
- Context loss/abandon инвалидирует shared guard целиком. Driver exception в timer,
  beginTarget или cancelFrame также инвалидирует его: дальнейшая работа запрещена
  до восстановления host и создания **нового** guard/resources. Старый guard не
  сбрасывается in-place, так что stale resource не получит доступ к новой generation.
- Low-level release проверяет owner identity: чужой owner не может снять claim.
  Owner tokens выделяются один раз при init, claim/release не создают объектов.

## Границы

Это не глобальный registry GL contexts. GLES Context — таблица function pointers,
не platform context ID; host сам связывает guard с текущим EGL/SDL context. Guard
не делает makeCurrent, не проверяет thread affinity и не восстанавливает foreign GL
state. Прямые backend calls, raw GL queries, независимые guards, threads/reentrancy
обходят защиту. Renderer draws сами не захватывают frame: они исполняются внутри
scope pipeline или direct path по правилам host. Renderer lifetime остаётся прежним.

Init/resize allocation failures продолжают использовать существующий transactional
backend cleanup; arbitrary driver exception не является гарантией полного cleanup.
После poison/loss освобождайте оставшиеся handles через abandon, не пытайтесь GL
cleanup на invalid guard. Отсутствует hardware FPS claim; CPU checks O(1).

## Regression coverage

CPU timing fixture: два независимых timers, rejection до driver begin, shared scope
для poll/dispose, frame+query coexistence, foreign release, normal cleanup/reuse,
независимые contexts, invalid guard и driver-failure propagation. Shared GPU post
fixture: конкурирующие pipelines на WebGL/GLES, zero-size/invalid-frame release,
sequential reuse, foreign dispose rejection до allocation. Demo browser loss/restore,
synthetic timing/autoscale, alias diagnostics и остальные GPU/UI fixtures остаются
в обязательной CI matrix. Pure JS, GCC/LLVM/QBE; ARM64 только cross-link.
