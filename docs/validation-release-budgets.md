# Пакет 24: release CPU workloads и WebGL debug budgets

## Что измеряется

`tests/bench_release.nim` — одинаковый Nim release code для C и чистого JS.
Browser harness выполняет 12 cases: 64/1024/8192 instances × static/moving ×
sparse/dense view. Это синтетические ground-oriented batches, проверяющие горячие
пути нашей low-poly графики, НЕ законченная репрезентативная сцена игры.

Каждый case: 20 warmup iterations, затем 41 sample. Измеряются отдельно:
conditional range packing, forced packing, grid rebuild (только moving), flat
query и grid query. Pose mutation, сравнение packed data/indices, initialization,
JSON serialization и сортировка samples вне timed intervals. Static grid строится
один раз до warmup; moving grid каждый раз перестраивается. Чтобы оценить moving
path, нужно учитывать rebuild + query, а не сравнивать только grid query с flat.

Median и nearest-rank p95, min и raw samples сохраняются в `release-ENGINE.json`.
В отчёте engine/version/platform/arch/UA/hardwareConcurrency; это не точное описание
CPU/GPU. GCC/LLVM/QBE выполняют тот же release oracle и сохраняют ci-bench-*.log.
Correctness проверяется explicit exceptions, независимо от включения assertions.

**Ограничения:** фиксированный порядок операций, короткие интервалы, timer rounding,
JIT/GC/OS noise. 20 iterations — фиксированный прогрев, не доказательство JIT steady
state. Zero timings разрешены. Нет speed thresholds, сравнения разных машин или
вывода FPS. GPU drawing и GPU elapsed этим benchmark не измеряются. Старые debug
workloads и GPU pixel/counter oracles сохранены отдельно.

## Debug budgets

В режиме `/?debug`:

```js
softgfxDebug.setBudgets({drawCalls: 16, uploadBytes: 65536});
// ... игра ...
softgfxDebug.snapshot();
softgfxDebug.download();
softgfxDebug.setBudgets(null); // отключить
```

Пороги выше лишь пример, не рекомендованный hardware budget. По умолчанию budgets
отключены. Draw calls — total scene count host demo. Upload bytes — только успешные
instance submissions между соседними sampled host frames; не texture/mesh/driver
traffic. Equality в пределах бюджета. Проверка идёт каждый submitted frame,
обычные journal frame samples остаются раз в 60 кадров.

Пишутся transitions: budget-exceeded (mask 1=draw, 2=upload, 3=оба) и recovered.
Непрерывное превышение с тем же mask не создаёт повторных записей; breachFrames и
число episodes сохраняются отдельно. Counter baseline/reset/context events и
int32 saturation отмечаются как unknown upload coverage, не как нулевая передача.
Смена budgets сбрасывает counters/baseline; invalid configuration атомарно отвергается.
Это диагностика, НЕ automatic quality controller. GL calls/readback не добавлены.

Node tests проверяют границы, coalescing, reset/saturation и экспорт; Firefox/WebKit
проверяют реальные draw-budget episodes в demo. Chromium/Firefox/WebKit запускают
release benchmark на одном generated-JS artifact. WebKit остаётся Playwright,
не сертификатом Safari/iOS. Физические устройства позже.
