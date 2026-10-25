# Пакет 33: rolling percentile storage и lifecycle диагностики

## Изменение профайлера

`FrameWindow` сохраняет прежнюю семантику: последние 120 допустимых samples,
lower median, nearest-rank p95; пустое окно возвращает нули. CPU разрешает zero,
GPU — нет; warmup/reset/profile/autoscale правила не изменены.

Вместо newSeq + sort при каждом `percentiles()` окно поддерживает второй fixed-size
массив отсортированных значений. `add` удаляет один expired duplicate по lower-bound
и вставляет новый sample; при полной очереди и expired == incoming multiset не
меняется. Чтение двух квантилей — O(1), без временного массива/сортировки.

Цена: дополнительный массив 120 float32 в каждом FrameWindow (480 bytes payload
на native; pinned Nim JS array storage может быть Float64 — 960 bytes payload,
без object overhead). Update теперь O(120) shifts worst-case вместо прежнего O(1).
Это осознанный tradeoff для частого чтения статистики. Не обещаем ускорения для
каждой частоты чтения и каждого движка; tuple/report objects всё ещё возможны.

## Проверки

- 4096 sort-oracle comparisons: ascending/modular, descending, duplicates,
  repeated reads, ring wrap, invalid/zero rejection, value-copy isolation/reset.
- Фикстура включена в test_timing: Node JS, native GCC/LLVM/cproc-QBE.
- Pinned JS codegen guard проверяет add/lowerBound/percentiles на прямые
  typed-array allocations/nimCopy. Это не whole-frame allocation profiler.
- Существующие timer/autoscale/loss/render/browser/native-window tests остаются.

## Парный release benchmark

`tests/percentile_benchmark.nim`: постоянные, монотонно меняющиеся и перемешанные
samples; **20 warmups + 41 samples**, каждый sample = **1024 updates × 2 reads** (первоначальные 64 увеличены в пакете 34).
Порядок optimized/reference меняется на каждом sample. Сравниваются checksums,
raw durations сохраняются; нет flaky timing pass/fail threshold.

Browser: `release-ENGINE.json.percentiles`, annotations с median batch time.
Native GCC/LLVM/QBE: `PERCENTILE_BENCH` строки в `ci-bench-*.log`.
Reference воспроизводит прежние copy/sort reads. Это CPU microbenchmark, не FPS,
не GPU timing и не доказательство ускорения всей игры. Timing включает JIT/GC/OS
noise; абсолютные результаты разных машин нельзя ранжировать как engine speed.

## Исправления диагностики

- Повторная загрузка recorder/inspector scripts сохраняет текущую сессию,
  captures и единственную панель; stopped recorder не перезапускается неявно.
- Inspector заимствует кнопку download у recorder и при dispose возвращает её
  исходному DOM parent, если тот ещё подключён. Recorder продолжает работать.
- URL для Blob download получает cleanup даже при синхронной ошибке click.
- Node tests проверяют duplicate init/stop preservation/failed-download cleanup;
  browser tests — duplicate scripts, dispose/remount, сохранение кнопки и captures,
  отсутствие лишних timers/GL readback. OS download-dialog acceptance не заявляется.


### Report hardening (пакет 34)

Первый запуск d12c5ce / Actions 40238286527 показал quantization коротких 64-frame
серий: Chromium mixed pattern median 0.1 ms против 2.5 ms copy/sort; WebKit ordered
median 0 ms при reference 2 ms. **Ноль не означает нулевую стоимость.** Поэтому
текущий benchmark использует 1024-frame series, сохраняя alternating order и 41
raw samples; zero durations всё равно валидны, ratio из них не вычисляется.

Единый `tools/percentile_report.cjs` проверяет browser/native schema, counts,
finite nonnegative timings, median/p95 и patterns. Native aggregate сохраняется
в `percentile-native.json`, а medians выводятся в Actions annotations. Node tests
отклоняют malformed reports/quantiles и разрешают zero-duration clock samples.
