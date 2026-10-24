# Десятый срез: snapshot interpolation + bounded fixed-step clock

2026-10-24. Это визуальная интерполяция согласованных снапшотов и scheduler helper,
НЕ physics engine, сетевой протокол, prediction/reconciliation или синхронизация IDs.
Общий модуль `softgfx/motion` не зависит от DOM, GL, platform clocks и UI.

## Interpolation API

```nim
import softgfx/[instances, motion]
var previous = @[instance([0'f32,0,0],yaw=0,scale=1)]
var current = @[instance([1'f32,0,0],yaw=0.2,scale=1)]
var rendered = newSeq[Instance](current.len) # storage once per stable batch
interpolateInstances(previous,current,0.5,rendered)
cars.updateInstances(rendered)             # or updateVisibleInstances after culling
```

- Обе последовательности и output должны иметь одинаковую длину ≤65535.
  **Идентичность и порядок сущностей гарантирует host**, не функция: одинаковое
  количество объектов не доказывает, что в slot i находится та же сущность.
- Finite alpha clamped в [0,1]; нет extrapolation. При alpha=0/1 поля копируются
  точно, включая исходное представление yaw. Intermediate yaw может быть
  нормализованным: непрерывность гарантируется для ориентации, не численного угла.
- Position, positive uniform scale и linear RGB tint интерполируются линейно.
  Float64 intermediates избегают overflow на противоположных float32 endpoints;
  clamp к endpoint interval не даёт scale выйти ниже минимального входного.
- Yaw: кратчайшая дуга после normalization через sin/cos/atan2. Если направления
  почти противоположны (|abs(delta)-pi|≤1e-6), выбирается отрицательное вращение.
  Это явно заданное правило для неоднозначного случая и float32/JS rounding.
- Все inputs проверяются до первого изменения output. NaN/Inf alpha, invalid
  instance, mismatched lengths не оставляют частично обновлённый результат.
- Output не resize-ится; scalar field writes сохраняют storage. Same-index in-place
  output=previous либо output=current поддержан и проверен. Произвольное shared
  object aliasing через raw JS/unsafe pointers не является контрактом.
- Для teleport/spawn/despawn/reorder нужно reset/remap history. В demo reset
  задаёт previous=current=видимые poses; automatic entity matching не реализован.

Generated JS guard покрывает interpolateInstances/blend/blendYaw: нет прямых
new Float32Array/Float64Array или nimCopy в этих функциях. Это не whole-frame heap
profile: constructor buffers, camera matrices, clock StepPlan и renderer wrappers
могут выделять объекты. На каждом simulation tick demo копирует current в retained
previous buffer скалярно, без новых Instance/typed-array объектов.

## FixedClock

```nim
var clock = initFixedClock(stepSeconds=0.05,maxSteps=4)
let plan = clock.advance(elapsedSeconds) # elapsed берёт host из monotonic clock
for step in 0..<plan.steps:
  # save previous; advance game by exactly clock.stepSeconds; produce current
  simulateFixedStep(clock.stepSeconds)
interpolateInstances(previous,current,plan.alpha,rendered)
```

Параметры конструктора: stepSeconds [0.001,1], maxSteps [1,32],
pauseThresholdSeconds [stepSeconds,10] (default .25); default step — 1/60,
maxSteps — 5. Demo явно выбирает .05/4.

- step budget ограничивает число вызовов simulation за один advance.
- Лишние **целые** steps выбрасываются, а не копятся в бесконечный backlog;
  fractional remainder сохраняется и даёт alpha [0,1).
- При elapsed > pauseThreshold: paused=true, steps=0, alpha=0, remainder сброшен.
  droppedSeconds включает весь elapsed и прежний remainder. Ровно threshold
  обрабатывается обычным bounded catch-up, а не long-pause веткой.
- NaN/Inf/negative elapsed отвергаются до изменения clock state.
- reset сбрасывает только remainder. Он не изменяет simulation или pose buffers.
- Численная tolerance для подсчёта целых ticks — 1e-9 от step; alpha ограничен
  сверху 1-1e-12. Тесты разных RAF partitions получают одинаковые tick counts.

Это осознанная **drop-time** политика, не lockstep/replay clock. При перегрузке
simulation может отставать от wall time. Длинный foreground frame тоже может
попасть под pauseThreshold: helper не умеет распознавать причину задержки.
Host должен выбрать подходящие лимиты и свою suspend/authoritative-state policy.

## Demo integration

«Ехать» теперь производит poses с 20 Гц и интерполирует их на каждом RAF.
Используются три retained buffers: previous/current/rendered. Цена previous→current
interpolation — примерно один simulation tick визуальной задержки (50 ms в demo).
Это не утверждение о network/input latency полноценной игры.

- Максимум 4 simulation ticks за один render update.
- Фоновая вкладка и context loss не выполняют simulation; last RAF timestamp
  сбрасывается, fractional history сохраняется для обычного pause/resume.
- При неожиданном elapsed >.25 demo сохраняет видимую позу, переустанавливает
  snapshot history и продолжает с отображённой аналитической фазы. Это правило
  примера, не рекомендация откатывать авторитетное состояние настоящей игры.
- «Шаг +0,25 с» по-прежнему явный snap аналитического demo, с reset history.
  Во время context loss меняются только CPU poses; restore загружает их заново.
- Culling и blob positions используют **rendered** poses, а не будущий current
  snapshot. Полный caster list сохранён. Draw-call бюджет не меняется.
- Публикуются simulationStepSeconds, simulationTicks (saturating), renderAlpha,
  droppedSimulationSeconds через softgfxTiming(). softgfxAdvance(seconds) —
  только demo/test hook для deterministic time injection, не глобальный API ядра.
- CPU submit profiling по-прежнему не включает host interpolation/pose generation
  и обычный instance upload до drawFrame. Его нельзя выдавать за total game time.

## Результаты

CPU GCC / LLVM / Node JS / cproc-QBE:

- endpoints/clamping, wrap 350°→10°, antipodal tie, midpoint linear tint;
- 1000 независимых yaw midpoint oracles через normalized sum unit vectors;
- previous/current in-place aliases, atomic rejection включая bad second record;
- extreme finite endpoints и exact float32 subnormal scale;
- fractional accumulation, budget/drop accounting, pauses, reset, invalid elapsed;
- 10 секунд при RAF 30/60/120/144 Гц → одинаковые 200 simulation ticks;
- PASS.

Shared WebGL1/2 и GLES2/3 GPU fixture: interpolated midpoint vs независимо заданные
reference poses/tints, ≤2 LSB; endpoint images совпадают точно, core/ANGLE/forced
fallback — PASS. Native release LLVM/QBE GPU fixtures также PASS.

Browser main harness (пять demo/fallback/UI scenarios): deterministic elapsed
.02/.03/.025, pixel change на midpoint, 5-second pause без скачка изображения,
.25-second catch-up ограничен четырьмя ticks; затем прежние input/owner/instance/
resize/context-loss/RAF tests — PASS. Реальный timing smoke и synthetic GPU
autoscale integration также прошли. Native использует EGL pbuffer, не окно.
ARM64 cross-compile/link — PASS, исполнения на ARM не было.

У pinned Nim JS codegen есть уже релевантная численная особенность: float32
min-subnormal literal может печататься как `1e-45`, но JS scalar остаётся double.
Тест использует точное runtime значение pow(2,-149), чтобы проверять interpolation,
а не decimal approximation компилятора. Строгий прежний instance validator не
ослаблялся. GPU subnormal/FTZ behavior на физических устройствах не аттестован.
Compiler patch в этом срезе **не менялся**; reverse-apply check сохранён.

## Воспроизведение / ограничения

Те же tools/test.sh, test_native.sh, test_cproc.sh; browser:
TEST_UI=1 USE_BUNDLED_LIBS=1 npm run test:browser.
Быстрые GPU fixtures: GPU_ONLY=1 USE_BUNDLED_LIBS=1 npm run test:browser.
Прочие проверки: npm run test:timing / test:autoscale с USE_BUNDLED_LIBS=1.
Логи: build/motion-{core,js,gpu,browser,native,qbe,llvm-release,qbe-release,arm64,
autoscale,timing}.log (ignored, временные).

Без physics/collision simulation, entity lifetime/ID mapping, server timestamps,
network jitter buffer, extrapolation/prediction, visible native window/mobile
hosts или аппаратного FPS acceptance. Снапшоты одинаковой длины пока сопоставляет
пользователь библиотеки. Полным renderer игровых authoritative snapshots этот
срез не объявляется.
