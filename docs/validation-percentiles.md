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
samples; **20 warmups + 41 samples**, каждый sample = **64 updates × 2 reads**.
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
