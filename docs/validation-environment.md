# Восьмой срез: sky gradient, vertex fog, analytic blob shadows

2026-10-24. Три лёгких визуальных эффекта работают на WebGL1/2 и GLES2/3.
T0 остаётся direct path без post framebuffer; T1 применяет свой final pass после
уже закодированной сцены. Это не shadow maps, volumetric fog или physical sky.

## Общий API

`softgfx/environment` экспортируется из `softgfx`:

```nim
var effects = SceneEffects(
  fogEnabled: true,
  eye: camera.eye,
  fogNear: 18, fogFar: 55,
  fogColor: [0.42'f32,0.51,0.62], # LINEAR RGB
  blobCount: 1)
effects.blobs[0] = BlobShadow(
  center: [carX,-0.02'f32,carZ], # центр на ПЛОСКОСТИ ПОЛУЧАТЕЛЯ тени
  radiusX: 0.95, radiusZ: 1.6, yaw: carYaw, strength: 0.45)
ground.updateEffects(effects)
effects.blobCount = 0
cars.updateEffects(effects) # fog, но автомобили не получают эти тени

var sky = initSkyRenderer(context,caps,
  [0.42'f32,0.51,0.62], [0.12'f32,0.24,0.42])
if pipeline.beginFrame(width,height,post):
  try:
    let size = pipeline.renderSize()
    sky.renderBackground(size.width,size.height)
    ground.render(size.width,size.height,cameraMatrix,clear=false)
    cars.renderInstances(size.width,size.height,cameraMatrix,clear=false)
    pipeline.endFrame()
  finally:
    pipeline.cancelFrame()
# Явный dispose, пока context current; на loss — пересоздание из CPU assets.
sky.dispose()
```

`SceneEffects()` выключает всё; прежние render API/pixel fixtures сохраняют
поведение. Settings проверяются целиком до изменения uniform state. Неактивные
blob slots и fog settings при выключенном fog игнорируются. Uniform locations
кешируются при создании renderer. `updateEffects` не загружает mesh/VBO/texture.
`initRenderer(..., unlit=true)` отключает modern lighting, но оставляет effects.
`initSkyRenderer` создаёт отдельный background variant; у него запрещены scene
settings и обычный render — используйте renderBackground. Instancing для
background variant не поддерживается.

## Цвет и алгоритмы

**Небо:** screen-space vertical gradient между двумя linear RGB colors,
интерполируемый до sRGB encode + dither. Отдельный минимальный shader не читает
owner/palette textures и не исполняет blob loop. Один indexed quad: 4 vertices,
6 indices, 204 bytes VBO/EBO. Пока используется общий Renderer resource owner:
он также резервирует неиспользуемые небом default owner/palette textures (1025
nominal bytes). Это не полностью специализированный resource allocator.

Background draw отключает depth test/writes, не очищает target и выполняется
**до сцены**. Поэтому одинаково работает с default depth и depth16 FBO; не ставит
геометрию на «почти far plane» и не зависит от квантования глубины. Следующий
обычный renderer восстанавливает depth test/LESS/depth writes.

**Туман:** distance-to-eye вычисляется в vertex shader после instance transform,
linear factor интерполируется по треугольнику. Затем linear shaded RGB смешивается
с linear fogColor, и только потом кодируется sRGB. Дешёвая аппроксимация, НЕ
per-fragment radial fog: на больших треугольниках фактор может быть неточным.
Нет fog height layers/volumetrics/physical atmospheric scattering.
Near/far: 0..1000 world units, span >=0.1; eye components ±10000; color [0,1].

**Blob shadows:** фиксированный бюджет **4** эллипса (в demo 3). В scene fragment
shader world XZ переводится в yaw-local ellipse coordinates; smoothstep radial
profile умножает linear RGB. Перекрывающиеся blobs перемножают attenuation.
Получатель должен иметь normal.y > .5 и высоту в пределах .04 от center.y.
Материал/owner palette затемняются одинаково. Это горизонтальная receiver-plane
аппроксимация, не геометрически корректная тень на склонах, стенах или сложной сцене.
Нет alpha sorting, transparent decals, дополнительных geometry draws, shadow
texture или z-fighting; зато каждый получающий pixel несёт стоимость до 4 blobs.

Blob centers ±512, radii .05..64, strength 0..0.8, |yaw|<=10000 radians. Это
small-world path. Scene varyings/fragment math используют mediump для ES2:
на устройствах с настоящим fp16 точность больших координат и plane-height checks
хуже. Проверка диапазона не гарантирует точность .04 world units у границ ±512.
В demo receiver y=-.02 и арена 13×13. Для больших миров нужен другой precision policy.
В fragment stage используются 12 uniform vectors с учётом samplers, в пределах
минимального GLES2 бюджета 16. Vertex layout не меняется (48 bytes, 7 attributes
с instancing); добавлены world position и fog factor varyings.

## Демо и стоимость

Переключатели **Небо / Туман / Blob-тени** работают и на T0, и на T1. Состояние
сохраняется при context loss, blob positions/yaw следуют за retained car poses.
Camera fog parameters обновляются до draw; тени получают ground/tree batch,
но height gate исключает верхушки деревьев. В этом demo деревья не являются
blob casters; автоматически извлекать caster geometry библиотека не пытается.

При включённом небе:

- T1: **4 draws** (sky + ground + cars + final), либо **6** с instance fallback;
- T0/direct: **3 draws**, либо **5** с fallback;
- fog/blobs добавляют **0 draw calls**, uniforms вместо mesh updates;
- отключение sky убирает один draw; instance stream по-прежнему 108 bytes/snapshot.

Environment flags включены в `softgfxTiming()`. Смена settings сбрасывает
profiler/autoscale evidence. Fixed-workload timing после этого среза нельзя
напрямую сравнивать со старым demo: визуальная работа стала другой.
Также исправлен stale HUD после context restore; отсутствие CPU samples теперь
подписано явно, а не как нулевое измеренное время.

## Проверки

Общий environment_fixture на WebGL1/2 и GLES2/3:

- overlapping rotated blob ellipses против CPU radial/linear-color reference,
  каждый RGB канал ≤3 LSB;
- неправильная receiver height не затемняется; invalid setting snapshot не
  меняет прежние uniforms; отключение effects восстанавливает baseline;
- полный и половинный fog против linear RGB → sRGB reference (≤2/3 LSB);
- effects на transformed world positions: instancing и forced fallback против
  CPU-transformed geometry (≤2 LSB);
- sky gradient против linear interpolation reference (≤3 LSB);
- sky в depth16 FBO, затем ближняя и дальняя геометрия: цвет соответствует
  baseline (≤1 LSB), подтверждены восстановление depth test и depth writes.

Node JS, GCC, LLVM, cproc/QBE CPU suites и native GLES fixtures — PASS.
Native release LLVM/QBE GPU suites — PASS. Linux ARM64 cross-link — PASS,
ELF64 AArch64, НЕ запускался. Compiler patch не изменён.

Chromium: общий GPU suite, прежние seeded resize/settings/instance/owner/input/
context-loss monkey tests, 5 demo/fallback/UI scenarios — PASS. Дополнительно
каждый environment toggle меняет pixels и обратимо восстанавливает fingerprint.
Реальные timing и synthetic-autoscale suites также прошли. Full-page screenshot
просмотрен визуально, включая отдельный fossil UI overlay.

Воспроизведение: прежние tools/test.sh, test_native.sh, test_cproc.sh,
TEST_UI=1 USE_BUNDLED_LIBS=1 npm run test:browser,
USE_BUNDLED_LIBS=1 npm run test:timing / npm run test:autoscale.
Для быстрой проверки только GPU fixtures: GPU_ONLY=1 USE_BUNDLED_LIBS=1 npm run test:browser.
Логи: build/env-{js,browser,gpu-final,native,qbe,llvm-release,qbe-release,arm64,auto,timing}.log.

## Границы результата

Software/ANGLE, native EGL pbuffer, а не видимое окно. Нет физического desktop/
mobile GPU performance acceptance, ARM runtime, E1–E7, shadow maps или завершённого
T1/T2. Нет утверждения о FPS/выигрыше на телефоне. Эффекты добавляют ALU/uniform/
background fill cost; выбор бюджета на устройстве требует отдельного измерения.
