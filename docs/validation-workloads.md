# Пакет 21: workloads, adaptive grid ordering и проверяемые отчёты

## Оптимизация grid query

До этого grid каждый раз очищала N marks, затем сканировала их для стабильного
порядка, даже если видны 4 из 8192 объектов. Теперь candidates собираются напрямую
в caller-owned indices. Для sparse output сортируется только prefix K (in-place
heapsort); для dense output выставляются marks и выполняется линейный stable scan,
одновременно очищающий marks. Полный upfront clear удалён.

Выбор: K <= N/(2*levels), levels ~= floor(log2(K))+1. Это детерминированная
эвристика количества операций, НЕ аппаратный autotuner. Query complexity теперь
O(cells + candidate tests + min(N, K log K)) по ordering heuristic; большие константы
и плохое размещение могут убрать выигрыш. Dense path остаётся O(N), rebuild
O(N+cells). Storage не увеличился, новых scratch seq нет. Существующий ascending
prefix contract не изменён. `orderScans` и `orderComparisons` — per-query counters.

Generated-JS guard проверяет sorter/sift на прямые typed-array allocations/nimCopy;
это не whole-frame heap proof (debug Nim instrumentation само может аллоцировать).

## CPU workload suite

`tests/test_workloads.nim`: 64, 1024, 8192 objects; sparse/dense views, 12 repetitions.
Проверяется exact prefix parity с flat collector, смена dense→sparse, 12 skipped
unchanged packs и 12 реально изменённых snapshots. Отдельные diagnostic intervals:
unchanged pack, forced pack, moving mutation+pack, rebuild, flat query, grid query.

Инициализация storage вне timed intervals; explicit long warmup нет. Сборки здесь
DEBUG, интервалы короткие, moving interval включает мутацию. Эти числа нельзя
использовать как честный ranking компиляторов или FPS. Compiler/buildMode/iterations
включены в JSON. CI проверяет finite/nonnegative timing, но НЕ скорость/ratio.
Для production benchmark нужны release, длительный warmup, повторения, hardware
metadata и контролируемые budgets. Это не завершение исходного E1–E7 плана.

## GPU workload suite

`tests/workload_fixture.nim`, общий для WebGL/GLES:

- 256 instances: forced vs conditional initial frame exact pixel parity.
- 32 одинаковых snapshot submissions: conditional path делает 32 skips.
  Core/ANGLE saving = 32*256*36 = 294912 bytes; fallback saving = 0, поскольку
  instance GPU buffer там отсутствует (CPU submissions всё равно пропущены).
- 8 moving snapshots: каждый rebuild grid, чередование dense/sparse views;
  selected indices равны flat oracle, а картинка — full batch без culling.
- Draw-call counts соответствуют реальному instance mode и visible count.
- Auto instancing и forced fallback используют одинаковые исходные snapshots.

Измерения byte/call savings основаны на renderer counters; реальные GL-call wrappers
проверены отдельно в dirty_fixture. GPU timing здесь не измеряется. ReadPixels —
только correctness oracle, не production frame path. GLES2 может иметь fallback
даже без force: report содержит и mode, и forcedFallback.

## Отчёты и CI

`tools/collect_workloads.py browser|native [log paths...]` строго проверяет schema,
полноту compiler/API/mode matrix, счётчики и numeric intervals. Он создаёт
`build/workload-browser.json` и `build/workload-native.json` в соответствующих
CI artifacts. Native GPU cases также выполняются в LLVM/QBE release fixtures.
Повторить browser report локально после test.sh/browser_test:

```
python3 tools/collect_workloads.py browser build/workloads-local.log build/workloads-gpu.log
```

Старые 40×1024 grid-oracle tests, GPU pixel fixtures, browser/UI monkey, native
windows/recovery/profiling и ARM64 cross-link сохранены. Software CI не доказывает
hardware FPS, mobile performance или ARM execution. Малое demo не переключено на
spatial grid: для трёх машин это лишняя работа.
