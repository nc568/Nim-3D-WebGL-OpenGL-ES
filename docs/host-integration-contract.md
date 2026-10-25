# Контракт первой интеграции host ↔ mini-engine

Практический baseline для текущего API, не обещание стабильного SemVer/production
release. WebGL1/2 — первый приоритет, GLES2/3 — parity; WASM не используется.
UI остаётся отдельным overlay/проектом. Vulkan/Metal не входят в этот checkpoint.

## 1. Кто чем владеет

| Объект | Ответственность host |
|---|---|
| Canvas/native window/context | Создать, выбрать размер backing surface, маршрутизировать loss/restore, не рисовать из параллельных callbacks |
| Renderer/Pipeline/timer | Создать при действующем context; хранить owner references; явно dispose или abandon при loss |
| Simulation/snapshots/EntityId | Собственная физика/сеть/tick/generation policy; mini-engine не принимает владение игровыми сущностями |
| Instance/culling/identity scratch | Выделить bounded capacity до frame loop; resize состава контролировать вне горячего пути |
| Territory CPU map | Сохранять авторитетное CPU-состояние для recreate; передавать валидированные deltas |
| Input/UI | Отдельный DOM overlay/native input; не использовать Canvas2D на том же WebGL canvas |
| Debug exports | Включить явно; проверить строки/метаданные перед передачей третьим лицам |

Renderer/Pipeline/timer являются shared owner handles: копия ссылки — **alias**, не
независимый GPU ресурс. Dispose через один alias делает остальные stale. Обычный
`dispose` для живого context и `abandon` после loss имеют разные обязанности.
Не хранить raw backend handles как долгоживущий игровой API.

## 2. Simulation update и render update — разные этапы

1. Host принимает/создаёт следующий **валидный** snapshot.
2. Если entity order/lifetimes менялись, `alignHistory(previousIds, previous,
   currentIds, current, resetFlags, aligned, scratch)` вызывается **один раз на
   snapshot transition**, а не на каждый RAF.
3. IDs уникальны, nonnegative int32. Teleport/reuse ID требует reset; helper не
   является generation allocator. Новые entities snap к current; despawn убирается.
4. Между ticks: `interpolateInstances(aligned, current, alpha, rendered)` с заранее
   выделенным output. Для постоянного matching order можно обойтись без identity map.
5. Выбрать `updateInstancesIfChanged` или `updateVisibleInstancesIfChanged`.
   Прежний forced-update путь оставить как correctness oracle, не обычный frame path.
6. Culling grid rebuild нужен при изменении соответствующих poses/bounds;
   reuse stale spatial index может ошибочно скрыть видимые объекты.

Не перепутать capacities: 64/256/1024 car fixtures — **provisional**, не согласованные
лимиты реальной игры. MaxInstances — технический предел, не performance budget.
Детали: validation-identity.md, validation-motion.md, validation-grid.md,
validation-dirty.md, validation-instance-ranges.md.

## 3. Кадр, scopes и внешние GL операции

Один `newContextScopes()` на реальный context передаётся всем cooperating pipelines
и elapsed-query timers. Несколько guards на один context не дают взаимного исключения.
Frame/query scopes независимы; overlapping owners отклоняются. Это не thread lock,
не global registry и не автоматическое перехватывание raw GL.

Host последовательно открывает frame, рисует background/terrain/instances, завершает
post pass. При исключении отменяет frame согласно pipeline contract. Не начинать
второй frame из resize/input callback посередине первого; пометить pending update.
Размеры относятся к backing pixels, не CSS pixels. Zero/minimized surfaces должны
идти через существующую pipeline size validation/skip path.

Per-program caches предполагают, что соответствующие uniforms пишет mini-engine.
Если host всё же меняет их напрямую, перед следующим draw нужны
`invalidateCamera()` / `invalidatePostUniforms()`; для scene effects — forced update.
Shared scope guard не отслеживает такие записи. Не вводить глобальный GL state cache
без отдельного контракта владения всеми изменяемыми состояниями.

## 4. Pause, loss и recovery

- Visibility/pause: сбросить fractional fixed-clock state; не подавать длинный
  background interval как валидное доказательство GPU нагрузки для autoscale.
- Loss: прекратить submission; invalidate/abandon graph, не удалять stale handles
  в новом context. CPU snapshots/map/настройки остаются у host.
- Restore/recreate: новый context generation, shared scopes и GPU resources;
  повторно загрузить данные из CPU state. Не переиспользовать старые timer queries,
  uniforms, framebuffer handles или bindings.
- Debug capability snapshot может относиться к прежнему context; после attach
  обновить его. Diagnostic capture не является сохранением полного игрового мира.

См. validation-scopes.md, validation-lifetime.md, validation-native-recovery.md,
validation-native-recreation.md и examples/browser.nim / examples/native_window.nim.

## 5. Что host должен предоставить для acceptance

- Обычный/пиковый entity count, topology meshes/materials, доля движущихся entities.
- Snapshot cadence, reorder/spawn/despawn/teleport patterns, ID reuse policy.
- Territory dimensions, обычный/пиковый размер и частота deltas.
- Backing resolutions/devicePixelRatio, T0/T1 обязательные эффекты и scale policy.
- Целевые CPU/GPU/draw/upload/memory budgets на выбранных устройствах.
- Lifecycle сценарии: pause/resume, resize, UI remount, loss/recreate, teardown.

До этих данных benchmark/soak — инженерные regressions, не game acceptance.
Конкретный E1–E7/device checklist и physical devices остаются отдельным этапом.

## 6. Минимальная приёмка интеграционного PR

- Pure JS build без WASM, WebGL1/2 + forced fallback и тот же snapshot oracle.
- Последовательности reorder/spawn/reset/invalid late input не портят историю.
- Частичный upload совпадает с forced full upload по пикселям; камеры/post cache
  дают ту же картинку после invalidation и retry.
- Teardown/recreate циклы балансируют API resource requests; это не VRAM proof.
- GCC/LLVM/cproc-QBE GLES и native window остаются зелёными.
- Chromium/Firefox/Playwright WebKit matrix, diagnostic export и bounded replay
  проходят; shipping Safari/iOS проверяется отдельно, не считается автоматически.
