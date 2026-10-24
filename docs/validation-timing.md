# Шестой срез: раздельные CPU/GPU измерения

2026-10-24. Это измерительная инфраструктура и smoke benchmark, не аппаратный
performance verdict и пока не автоматический подбор качества.

## API и границы

- `softgfx/timing`: backend-neutral `TimerDriver`, single-owner `GpuTimer`,
  фиксированная очередь из **4** query objects. При переполнении пропускается
  измерение, а не кадр. Нет роста очереди, ожидания, glFinish, readPixels или flush.
- `timing/web`: EXT_disjoint_timer_query_webgl2 для WebGL2,
  EXT_disjoint_timer_query для WebGL1. Расширение и ненулевые counter bits проверяются.
- `timing/gles`: GL_EXT_disjoint_timer_query, точная проверка имени extension,
  всех необходимых entry points и counter bits. Результат читается как uint64,
  затем переводится из ns в ms; JS использует Number, не signed int32.
- Результат запрашивается только после QUERY_RESULT_AVAILABLE. Poll строго вне
  активного query scope; читается готовая часть FIFO, максимум 4 samples за вызов.
- Disjoint до/после readback выбрасывает всю пачку и pending measurements.
  Reset отбрасывает pending результаты; GL query objects переиспользуются.
  `invalidations` считает и disjoint, и явные resets, **не число GPU resets**.
- `dispose` идемпотентен, завершает активный запрос и освобождает pool.
  На context loss: `abandon`, без GL calls; на restore — новый driver/timer.
  Native host обязан передать достоверный callback потери контекста.
- Другие elapsed queries нельзя вкладывать/interleave; ресурсы single-owner по
  соглашению, без compile-time защиты от копирования. GPU OOM/driver failures
  не покрыты полностью. Allocation failure очищает созданную часть pool.

`softgfx/profiling` — отдельный накопитель с frame-ID warmup. Поздние GPU samples
от первых 30 submission frames тоже исключаются. CPU и GPU имеют независимые
rolling windows до 120 samples: lower median и nearest-rank p95. Реальные долгие
кадры НЕ отбрасываются (в отличие от pause rule отдельного Quality prototype).
NaN/Inf/negative/непредставимые float32 значения исключены. Нулевой CPU duration
допустим из-за квантования performance.now; GPU durations принимаются положительные.

## Пример использования

```nim
import softgfx/[timing, profiling]
# Web: import softgfx/timing/web as gpuClock
# var timer = initGpuTimer(gpuClock.timerDriver(gl, modern=true))
# GLES: import softgfx/timing/gles as gpuClock
# var timer = initGpuTimer(gpuClock.timerDriver(resolver, contextLost))
var profile = initFrameProfile(warmupFrames=30)
var ready: GpuBatch
# В начале кадра:
timer.poll(ready)
# При изменении timer.invalidations: profile.resetGpu().
for i in 0..<ready.count: profile.recordGpu(ready.samples[i])
let frame = profile.nextFrame()
let started = hostMonotonicMilliseconds()
discard timer.beginSample(frame) # false = unsupported/full/disjoint; это не GPU=0
try:
  drawSceneAndFinalPass()
finally:
  timer.endSample()
profile.recordCpu(frame,hostMonotonicMilliseconds()-started)
# Получать отчёт не в inner draw loop:
let report = profile.report()
# При ошибке draw отбросить измерение через reset; при потере контекста abandon.
```

Полный host-код с обработкой ошибок и lifecycle — examples/browser.nim.
`FrameProfile` принимает измеренное время CPU от хоста; это не скрытый platform clock.
Полная игра/physics/UI/RAF latency не входят в текущую demo CPU-метрику.
GPU и CPU работают асинхронно: их median нельзя складывать как frame time/FPS.

## Browser demo и воспроизведение

Кнопка **«Измерить CPU/GPU»** включает статический RAF-прогон (или измеряет
движущуюся сцену, если включено «Ехать»). Измеряется matrix + scene + final submission;
CPU interval включает query begin/end overhead, но не poll, HUD и статистику.
GPU elapsed охватывает scene + final commands. HUD обновляется каждые 30 кадров.

`softgfxTiming()` возвращает JSON-compatible snapshot: samples, median/p95,
query support/skips/invalidations, размеры target, draws, память, scale/effects,
instance mode, animated. При отсутствии данных значение времени — **null**, не 0.
Resize/settings/visibility/context restore начинают новую выборку. Query unavailable
не заменяется CPU time. Одновременно активный application RAF использует ту же очередь.

```sh
NIM=/path/to/nim FOSSIL_SRC=/path/to/fossil/src ./tools/test.sh
# Сервер build/ на 0.0.0.0:8080, как в предыдущих отчётах
USE_BUNDLED_LIBS=1 npm run test:timing
```

`tools/timing_test.cjs` прогоняет direct, neutral final, FXAA, FXAA scale .85,
WebGL1 T0 и принудительно отсутствующий timer extension. Не менее 180 submission
frames на workload, 30 warmup; output — `build/timing-report.json` с фактическими
sample counts. **120 — ёмкость окна, не обещание получить 120 GPU samples.**
В software GPU очередь может заполняться: timings редеют и sample population
отличается от CPU. Незавершённые запросы при остановке не дожидаются. Это причина
не делать вывод о превосходстве варианта по этому smoke-прогону и не включать
автоскейлер на его основании. Полный E1–E7 benchmark пока не реализован.

Browser harness запрещает finish/readPixels в профилировании и result reads без
availability; проверяет loss/restore во время измерения и CPU-only fallback.
Основной browser monkey/UI harness также проходит без регрессий.

## Исправленная ошибка

Старый `FrameWindow.percentiles` делал sort(array.toOpenArray(...)). Nim JS
генерировал slice(), сортировал временную копию и выбирал процентили из исходного
несортированного массива. На возрастающих первых 100 значениях тест случайно
проходил; после wraparound median/p95 были неверными. Теперь сортируется явно
выделенная копия фактической длины, одинаково на JS/native. Это локальное исправление
библиотеки, не изменение Nim JS compiler. Добавлены reverse-order, wraparound,
finite/float32-boundary, warmup и long-frame regression tests.

## Матрица проверки

- Node JS + native GCC/LLVM/cproc/QBE: queue-full, no blocking reads, FIFO,
  nesting rejection, disjoint до/во время readback, partial allocation cleanup,
  loss в активном scope и между двумя проверками dispose, repeated dispose,
  unsupported path, frame-ID warmup, window wraparound и quantiles — PASS.
- Chromium WebGL1/2: реальные extension readbacks получены; forced no-extension
  выдаёт CPU-only и null GPU; измерение переживает context loss/restore — PASS.
- Native GLES2/3 ANGLE/SwiftShader: extension доступен, получен валидный sample;
  GCC/LLVM/cproc/QBE, включая release LLVM/QBE — PASS. В native smoke существующий
  readPixels fixture синхронизирует сцену перед poll: это НЕ native async benchmark.
- Обычные territory/instances/post GPU fixtures и browser/UI monkey suite — PASS.
- ARM64 cross-compile/link — PASS, не запускался.

Локальные логи: build/timing-{js,browser,live,native,qbe,llvm-release,qbe-release,arm64}.log.
Результаты software/ANGLE не являются измерением скорости на физической GPU.
Native по-прежнему EGL pbuffer, не видимое desktop-окно; mobile/ARM runtime не выполнен.
Compiler patch не изменён в этом срезе. Автоматическое изменение scale пока выключено;
следующий шаг — политика свежести/минимального числа samples и управляемое сравнение
workloads перед подключением GPU-driven quality hysteresis.
