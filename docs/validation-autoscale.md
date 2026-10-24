# Седьмой срез: GPU autoscale + host controls + regression package

2026-10-24. Experimental/opt-in, **не гарантия 60 FPS** и не настройка под
физическое устройство. Default demo mode по-прежнему manual.

## Контроллер

`softgfx/autoscale` не зависит от GL/DOM. Он принимает только GPU samples из
`softgfx/timing`, номер submission frame и монотонное время хоста в миллисекундах.
CPU submission time не используется как fallback. `Quality` остаётся отдельным
старым CPU-policy prototype; новый контроллер не меняет его поведение.

Фиксированные начальные правила (эвристики, ещё не аппаратно откалиброваны):

- scale 0.7–1.0, шаг 0.05, хранение в целых тысячных;
- первые 30 submission frames — warmup; timestamps в bounded ring на 64 записи;
- matching frame ID; возраст результата ≤8 submission frames и ≤200 ms;
- duplicates/out-of-order/future IDs не считаются новыми samples;
- окно из 12 новых samples должно уложиться в 32 submission-frame intervals
  и 600 ms по времени доставки; разрыв >8 frames сбрасывает evidence;
- вниз: 3 последовательных окна с median >1.1×budget;
- вверх: 10 последовательных окон с p95 <0.8×budget;
- средний диапазон, invalid/stale/sparse sample сбрасывают накопленные голоса;
- budget по умолчанию 16.667 ms GPU elapsed для текущего scene+final scope;
- после смены масштаба: минимум 60 submission frames и 1000 ms settling;
- пауза между submissions >250 ms запускает повторный warmup;
- durations NaN/Inf/≤0/>250 ms не используются контроллером. Profiler продолжает
  хранить валидные долгие GPU durations: фильтр контроллера — не цензура отчёта.

Недостаточная/устаревшая выборка означает **оставить текущий scale**, а не
переключаться на CPU, автоматически снижать качество или обещать восстановление FPS.
При постоянно насыщенной очереди software GPU масштаб может не меняться вообще.
Down/up используют непересекающиеся окна; каждый GPU sample учитывается один раз.

## Host integration

```nim
import softgfx/[autoscale, timing]
var controller = initAutoScale(1)
# frame строго возрастает; now — монотонные миллисекунды хоста.
controller.submitted(frame, now)
# Только готовые результаты GPU timer:
if controller.observe(sample, now):
  settings.scale = controller.scale
  # Отбросить pending timer queries/old-resolution measurements, restart frame IDs.
  timer.reset()
  controller.reset(settings.scale, settling=true)
```

Полный пример — examples/browser.nim. На resize/manual settings/disjoint/
visibility/context restore одновременно сбрасываются timer evidence, profiler и
контроллер. После auto-change остаток текущей readback batch от старого размера
не используется. Следующий beginFrame реально меняет размер framebuffer.
`reset(..., settling=true)` сохраняет wall-time cooldown и устанавливает новый
60-frame warmup; обычный reset — 30-frame warmup. Host должен сам разделять эпохи:
в `GpuSample` отдельного generation ID нет, поэтому очищать timer обязательно.

Checkbox **Auto scale (GPU, experimental)** включает отдельный RAF measurement
loop, даже без кнопки измерения/движения. Active только для WebGL2 + enabled post
+ доступного GPU timer. WebGL1 и отсутствующий timer отключают control. Direct path
и потерянный context не могут оставаться active. Ручные controls сохраняются.
В `softgfxTiming()` добавлены `autoRequested`, `autoActive`, `scaleChanges`.
Автоматическая работа выключена по умолчанию и не влияет на fixed-scale benchmark.

## Проверки

- Node JS / GCC / LLVM / cproc-QBE: warmup, 36 slow/120 fast samples, deadband,
  clamps, cooldown, timestamps, stale readbacks, duplicates, frame-span/wall-time
  density, invalid durations, reset и p95 recovery guard — PASS.
- Release controller tests LLVM и cproc/QBE — PASS.
- `tools/autoscale_test.cjs`: **синтетические GPU durations**, настоящие WebGL
  scene/FBO. Проверены down/up, размер 64→61 при scale .95, отсутствие изменений
  на disjoint, direct path, context loss и восстановление без старых slow votes.
  PASS. Это integration oracle, НЕ измерение GPU производительности.
- Полные native GLES2/3, timer/territory/instances/post fixtures GCC/LLVM/QBE — PASS.
- Основной Chromium monkey/UI suite и реальный fixed-scale timing smoke — PASS.
- ARM64 controller cross-compile/link — PASS, не исполнялся.
- Compiler patch не изменён; reverse-apply check сохранён.

Воспроизведение:

```sh
NIM=/path/to/nim FOSSIL_SRC=/path/to/fossil/src ./tools/test.sh
# build/ served on port 8080
USE_BUNDLED_LIBS=1 npm run test:autoscale
TEST_UI=1 USE_BUNDLED_LIBS=1 npm run test:browser
USE_BUNDLED_LIBS=1 npm run test:timing
# native prerequisites/commands unchanged: tools/test_native.sh, tools/test_cproc.sh
```

Логи: build/auto-{js,browser,regression,timing,native,qbe,llvm-release,qbe-release,arm64}.log.

## Native window / незакрытые задачи

Повторно проверено окружение: DISPLAY/WAYLAND_DISPLAY не заданы; Xvfb/Weston и
SDL/GLFW не обнаружены. В этом пакете не добавлялся непроверенный оконный host.
Native execution по-прежнему EGL pbuffer; физический GPU/mobile/ARM runtime не
выполнялись. Не заявляем аппаратный выигрыш от scale или полную адаптацию качества:
AA/shadow/bloom degradation, E1–E7, tuning budget под реальную игру, window/mobile
hosts и compile-time single-owner resources остаются отдельными задачами.
