# Web-first validation и diagnostics (пакет 23)

Приоритет: **WebGL1/2**, затем **OpenGL ES2/3**. Другие backend'ы и physical device
runs отложены. Это mini-engine под low-poly graphics игры, не универсальный движок.

## CI

Chromium сохраняет полный прежний suite (GPU pixels, UI monkey, lifecycle, timer,
autoscale). Дополнительно тот же скомпилированный JS artifact проверяется через
Playwright 1.58.2:

- Firefox на Ubuntu 24.04 / Xvfb / software GL;
- WebKit на macos-15, с обязательной проверкой process.arch == arm64.

WebGL1 и WebGL2 должны пройти все shared GPU fixtures, включая range uploads,
culling, effects, post и fallback. Silent downgrade WebGL2→1 не считается успехом.
Demo проходит seeded resize fuzz во всех четырёх комбинациях API/fallback.
JSON report содержит фактические engine/version/platform/arch и результаты cases;
failures сохраняются в artifacts. Это пока НЕ полный parity Chromium lifecycle/UI
suite, не shipping Firefox/Safari certification и не iOS runtime. Playwright WebKit
не равен Safari. ARM macOS browser execution не равно native GLES/QBE ARM execution.

## Debug recorder

Открыть `/?debug` или `/?webgl1&debug`, затем «Скачать debug JSON».
Программный API: `softgfxDebug.mark('marker')`, `.snapshot()`, `.download()`, `.stop()`.

- Opt-in: без query flag нет listeners, журнала или capability queries.
- Ring: 256 entries, message <=512 chars; overwritten counter явно отражает потери.
- Error/rejection/context/visibility events и custom markers.
- Каждые 60 submitted frames: draw calls, visible instances, cumulative successful
  instance upload bytes/skips. Это samples, не полный trace и не GPU elapsed time.
- Debug-only initial capability snapshot, без unmasked GPU identity.
- Экспорт добавляет whitelist текущих counters/quality/target memory и CPU/GPU
  median/p95 из существующего profiler. Таймер не включается автоматически:
  используйте «Измерить CPU/GPU»; без samples timings остаются null. Сбор profile
  происходит только при export/snapshot, а не на каждом кадре.
- Export отделён от внутреннего mutable state; stop снимает event listeners.
- Нет перехвата GL calls/console, getError, readPixels, network, localStorage или
  сериализации произвольных Error/payload objects. Нет бесконечного лога на кадр.

**Privacy:** URL/stack автоматически не экспортируются, но error messages и явно
добавленные markers могут содержать пользовательские данные. Просмотрите JSON перед
публикацией. Capability snapshot описывает начальный context, не гарантирует здоровье.
Recorder — первая основа diagnostics, НЕ законченная advanced debug suite.
Native structured timing/recovery reports продолжают работать отдельно.

## Следующие приоритеты

Game-specific workload presets/release warmup, CPU/GPU/memory budgets, inspector
сопоставления frame counters, selective capture shader failures и reproducible
seed/state traces. Полные GL-call traces должны включаться отдельно и иметь budget;
не добавлять blocking GPU diagnostics в normal frame loop. T1/T2 эффекты выбираются
по измеренным затратам наших сцен, физические устройства — следующим этапом.
