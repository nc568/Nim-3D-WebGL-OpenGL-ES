# softgfx — Nim → pure JS / native GLES

Десятый **экспериментальный вертикальный срез**, не готовый игровой движок.
Один пример сцены на Nim собирается в JavaScript без WASM для WebGL1/2 и
в C для GLES2/3. Требуется Nim 2.2.4. Зависимостей Nim у ядра нет.

## Что уже работает

- Интерполяция matched instance snapshots: position/scale/linear tint и shortest-arc
  yaw; bounded fixed-step clock. Demo: 20 Hz snapshots + interpolated RAF.

- Conservative frustum culling для instance batches: AABB, stable index prefix,
  direct packing выбранных экземпляров; opt-in checkbox в demo.

- Динамические mesh batches: core instancing WebGL2/GLES3, ANGLE для WebGL1,
  fallback с обычными draw calls. Позы, yaw, uniform scale и tint — 36 байт/экземпляр.
- Demo: один меш машины, три движущихся экземпляра; 2 scene draws или 4 на
  instance fallback, плюс sky draw и final draw при T1: итого 4/6 (T0: 3/5).
- Градиент неба, vertex-distance fog и до четырёх analytic blob shadows.
  Цвет смешивается в linear RGB до sRGB; доступны отдельные переключатели.
- T1: RGBA8 + depth16 target, final pass, FXAA, exposure/vignette/dither, scale
  0.7–1.0; T0/WebGL1/GLES2 остаётся прямым путём без post-ресурсов.

- Индексированные меши (`uint16`, drawElements), static deduplication.
- Owner ID карта: R8 на WebGL2/GLES3, LUMINANCE fallback на WebGL1/GLES2;
  палитра на 256 ID, прямоугольные дельты без перезагрузки геометрии.
- **cproc/QBE:** тесты ядра и native GLES2/3 реально собираются и запускаются
  с экспериментальным патчем Nim; [инструкция и ограничения](docs/cproc.md).

- 3D-камера: perspective/lookAt, column-major матрицы, мировые координаты.
- Статическая сборка боксов с правильными нормалями и winding; демонстрационная
  арена с тремя машинками, orbit/zoom в браузерном host.
- Uniform location кешируется; JS использует один переиспользуемый Float32Array
  для матрицы, а не создаёт typed array на каждом кадре.
- Общие `MeshData`, `Vertex`, `Capabilities`, `Renderer`; выбор адаптера при компиляции.
- WebGL1/2: выбор контекста, загрузка Float32Array один раз, компиляция/линковка
  шейдеров с диагностикой, draw, явное освобождение GPU-ресурсов.
- GLES: загрузка entry points через resolver хоста, без привязки ядра к SDL/EGL.
- GLSL ES 100/300: T0 использует подготовленный цвет, modern-путь — wrap diffuse,
  hemisphere ambient, линейный цвет → sRGB, треугольный дизеринг.
- Отдельные CPU submission/GPU elapsed median/p95: optional disjoint timer queries,
  bounded 4-query queue, warmup, lifecycle и явный CPU-only fallback.
- Отдельная политика scale 0.7–1 с гистерезисом.
  `PostSettings.scale` теперь управляет реальным target; автоматический выбор по
  GPU-времени теперь доступен как opt-in Auto scale с freshness/density guards.
- Browser demo восстанавливает ресурсы после context loss.
- Необязательный пример композиции с HTML-драйвером UIRelays.

**Важные ограничения:** это ещё не полноценный renderer authoritative игровых
снапшотов: нет entity ID/lifetime mapping, network jitter buffer, spatial index
и сортировки. Нет shadow maps, законченного T1/T2
и оконных/mobile host-адаптеров. cproc пока проверен только на Linux x86-64, ARC,
без потоков. Нет доказательств производительности на физическом GPU.

## Быстрый старт

```sh
./tools/test.sh                  # GCC + JS/Node + browser build
# В браузере: drag — камера, wheel — приближение, «Ехать» / «Шаг» — движение
python3 -m http.server 8080 --bind 0.0.0.0 --directory build
# открыть http://localhost:8080/ или /?webgl1
```

`NIM=/path/to/nim ./tools/test.sh` позволяет задать компилятор.
В sandbox preview сервер также доступен через прокси Arena.

Браузерные тесты (при работающем сервере 8080):

```sh
npm ci
npm run test:browser
# Для минимального Linux без NSS/NSPR:
USE_BUNDLED_LIBS=1 npm run test:browser
```

NPM-зависимости нужны **только тестам**, не игре и не библиотеке.
Тесты проверяют WebGL1/2, реальные пиксели, GL errors, seeded resize fuzz и
orbit/zoom и точное совпадение framebuffer после потери/восстановления контекста. Это не исчерпывающая проверка всего будущего API.

Нативная проверка (установлены EGL/GLES, есть рабочий display либо Mesa surfaceless):

```sh
nim c -r -o:build/test_gles tests/test_gles.nim
# Mesa headless: EGL_PLATFORM=surfaceless nim c -r ...
# LLVM:
nim c --cc:clang -r -o:build/test_core_llvm tests/test_core.nim
```

Для ANGLE/SwiftShader есть `-d:angleSwiftShader` и
`-d:eglLibrary=/absolute/path/libEGL.so`. См. [протокол проверок](docs/validation.md).

## Минимальный контракт

```nim
import softgfx
# context: backend Context, caps: Capabilities, mesh: MeshData
var renderer = initRenderer(context, caps, mesh)
let camera = Camera(eye: [8'f32,9,11], target: [0'f32,0,0],
  up: [0'f32,1,0], fovY: 0.8, nearPlane: 0.1, farPlane: 100)
renderer.render(framebufferWidth, framebufferHeight,
  camera.viewProjection(float32(framebufferWidth)/float32(framebufferHeight)))
renderer.dispose() # пока исходный контекст ещё current
```

Web: `softgfx/backends/web.acquire(canvas, forceLegacy)` возвращает контекст и caps.
Native: `softgfx/backends/gles.acquire(resolver)` загружает функции; host обязан
создать и сделать current GLES-контекст и передать соответствующий API в `baseline`.
`Renderer` — владелец ресурсов: **не копировать**, освобождать явно, не использовать
с другим контекстом/потоком. Нельзя смешивать raw GL/UI GL-команды с renderer:
полное восстановление внешнего GL state ещё не реализовано.

## UIRelays

```sh
FOSSIL_SRC=/path/to/fossil-nim/src ./tools/test.sh
TEST_UI=1 USE_BUNDLED_LIBS=1 npm run test:browser
# открыть /ui.html
```

Нужна ветка `uirelays-web-backends`. UI рисуется в sibling `#uir-viewport`,
графика — в `#scene`; UI refresh не должен удалять WebGL canvas.
Пример подтверждает композицию вывода, **не полноценную интеграцию ввода**.
UI-проект не включён в зависимости основного пакета и не изменялся.

Текущие результаты: [snapshot interpolation и fixed-step clock](docs/validation-motion.md).
Предыдущий этап: [culling, selected uploads и bootstrap](docs/validation-culling.md).
Предыдущий этап: [небо, туман, blob-тени](docs/validation-environment.md).
Предыдущий этап: [GPU autoscale, controls и регрессии](docs/validation-autoscale.md).
Предыдущий этап: [CPU/GPU timing и benchmark smoke](docs/validation-timing.md).
Предыдущий этап: [T1 target, scale и FXAA](docs/validation-post.md).
Предыдущий этап: [динамика и instancing](docs/validation-instancing.md).
Предыдущий этап: [территория, индексы и cproc](docs/validation-territory.md).
Предыдущие результаты: [этап 2](docs/validation-3d.md).

Дальнейшая архитектура и соответствие разделам 6–7: [план](docs/design.md).

## Карта территории

```nim
let owners = newOwnerMap(31, 23) # row zero = v=0, palette хранит linear RGBA8
# До создания renderer: owners.applyDelta(...) заполняет начальные ID.
var r = initRenderer(context, caps, mesh.indexed(), owners)
r.updateTerritory(2, 3, 3, 1, @[1'u8, 128, 255])
```

Для поверхности карты задать `Vertex.territory = [u, v, 1]`; остальные вершины
имеют mask=0 и используют vertex color. Материальный mask должен быть одинаков
у трёх вершин треугольника. Палитра задаётся при `newOwnerMap(width,height,palette)`.
API `updateTerritory` обновляет GPU и CPU shadow; host сохраняет OwnerMap для restore.
Предел каждой стороны карты — 4096 и фактический MAX_TEXTURE_SIZE устройства.

## Динамический batch

```nim
# localMesh — локальная геометрия одного объекта; GPU storage выделяется один раз.
var cars = initRenderer(context, caps, localMesh, instanceCapacity=128)
let poses = @[instance([0'f32,0,0], yaw=0.2, tint=[1'f32,0.3,0.2]),
              instance([3'f32,0,-2], yaw=1.0, scale=0.8)]
cars.updateInstances(poses)       # при изменении snapshot; не пересоздаёт mesh
terrain.render(width, height, cameraMatrix)
cars.renderInstances(width, height, cameraMatrix, clear=false)
echo cars.instanceMode           # coreInstancing / angleInstancing / fallbackDraws
cars.dispose()
```

`forceFallback=true` при init предназначен для сравнения путей/совместимости.
`instance()` создаёт identity transform; zero-initialized `Instance()` имеет
scale=0 и отвергается. Допустимы только положительный uniform scale и конечные
числа, представимые в GPU float32; tint в [0,1] умножает vertex color (не цвет из owner palette).
Порядок экземпляров сохраняется. Batch capacity не растёт автоматически;
нулевой snapshot снимает все экземпляры. `clear=false` требует уже подготовленного
того же target/viewport. Host сохраняет свои poses для context restore.

`stats.instances`, `drawCalls`, `vertices` относятся к последнему draw API вызову;
`vertices` считает submitted vertex/index count × instance count, не уникальные
GPU vertex invocations. `instanceUpdates` и `instanceUploadBytes` — накопительные
счётчики с насыщением на high(int); fallback uploadBytes=0. `bufferBytes` включает
reserved GPU instance capacity, но не CPU shadow.


## T1 frame scope

```nim
var pipeline = initPipeline(context, caps)
var post = defaultPost() # enabled, FXAA, dither; scale=1, exposure=1, vignette=0
post.scale = 0.85
# На каждом кадре; width/height — размеры framebuffer, не CSS pixels.
if pipeline.beginFrame(width, height, post):
  try:
    let size = pipeline.renderSize()
    let matrix = camera.viewProjection(float32(width)/float32(height))
    terrain.render(size.width, size.height, matrix, clear=false)
    cars.renderInstances(size.width, size.height, matrix, clear=false)
    pipeline.endFrame()
  finally:
    pipeline.cancelFrame()
# При shutdown, пока context current:
pipeline.dispose()
```

Все scene draws внутри scope используют **clear=false** и renderSize; camera
aspect — от output size. T0 и `post.enabled=false` используют полный output size.
Для нейтрального 1:1 прохода: scale=1, fxaa=false, dither=false, exposure=1,
vignette=0. Это display-referred RGBA8, не HDR: scene уже кодирует sRGB, final
не кодирует повторно. Линейная фильтрация текстуры происходит в encoded space.

`Pipeline` тоже single-owner: не копировать, не вкладывать разные pipelines,
не смешивать с внешним framebuffer/VAO/sampler state. На context loss вызвать
`abandon()` (без GL calls), на restore — заново `initPipeline`. Размер 0 пропускает
кадр. Неизменный target переиспользуется; отключение post сохраняет cache.
Предел target по умолчанию — 8 Mi pixels, проверяются texture/renderbuffer limits;
resize транзакционный, поэтому пиковая память может включать старый и новый target.
`stats.allocatedBytes` = width × height × 6, без driver padding/program/36-byte VBO;
`finalDrawCalls` — отдельно от scene renderer stats. Подробности и ограничения —
в [отчёте T1](docs/validation-post.md).


## Измерения

В demo нажать **«Измерить CPU/GPU»**: 30 warmup submission frames, независимые
rolling windows до 120 CPU/GPU samples. GPU использует timer extension, никогда
не подменяется CPU time; отсутствие данных — `null` в `softgfxTiming()`.
`USE_BUNDLED_LIBS=1 npm run test:timing` сохраняет диагностический отчёт в
`build/timing-report.json`. Это software/ANGLE smoke, не физический GPU benchmark.
API `softgfx/timing`, `softgfx/profiling`, adapters `timing/web` и `timing/gles`
и точные ограничения описаны в [отчёте](docs/validation-timing.md).


## GPU autoscale (experimental)

Checkbox **Auto scale** включает GPU-only контроллер в WebGL2 post path.
Нет timer / stale или sparse samples / disjoint → нет решения по CPU-времени.
Down/up hysteresis, warmup, cooldown и сбросы эпох описаны в
[отчёте](docs/validation-autoscale.md). По умолчанию выключен; это ещё не аппаратно
откалиброванная quality policy и не гарантия FPS. Общий Nim API:
`softgfx/autoscale`; integration regression: `npm run test:autoscale`.


## Небо, туман и blob-тени

`SceneEffects` + `renderer.updateEffects(settings)` задают vertex fog и до четырёх
world-space blob receivers. Цвета linear RGB, `SceneEffects()` отключает эффекты.
Небо: `initSkyRenderer(context,caps,bottom,top)` и `renderBackground(width,height)`
после clear, перед scene draws. Ни fog, ни blobs не требуют post framebuffer;
WebGL1/GLES2 сохраняют direct T0 path. API, CPU/GPU oracles и ограничения precision/
receiver planes — в [отчёте](docs/validation-environment.md).


## Frustum culling и восстановление test tools

`softgfx/culling`: `meshBounds`, `frustum`, `collectVisible` и
`renderer.updateVisibleInstances(poses, indices, count)`. Порядок объектов
сохраняется, camera clipping учитывается консервативно. Это O(N) broad phase,
не occlusion/BVH; отдельно учитывайте offscreen shadow casters.
Пример и проверки — [отчёт](docs/validation-culling.md).

Если временные toolchains отсутствуют: `tools/bootstrap.sh` умеет подготовить
`nim`, `cproc`, `llvm`, `native-driver`, `ui` отдельно внутри ignored `build/`.
Интернет/system build prerequisites и ограничения описаны в том же отчёте.


## Интерполяция снапшотов

`softgfx/motion`: `interpolateInstances(previous,current,alpha,rendered)` пишет
в заранее созданный output без изменения длины. Entity identity/order должны
совпадать; для teleport/spawn/despawn сбрасывайте или сопоставляйте history.
`initFixedClock`/`advance` дают bounded steps, fractional alpha и dropped time.
В demo движение использует 20 Hz snapshots, ручной шаг остаётся snap/reset.
У такого rendering есть примерно один tick задержки; это не network prediction
и не physics engine. Пример, пределы и тесты — [отчёт](docs/validation-motion.md).

## GitHub Actions

`.github/workflows/graphics.yml` runs separate browser/UI and native validation
jobs on pushes/PRs. Native includes GCC, LLVM, cproc/QBE, GLES2/3, release runs and
ARM64 **cross-link only**. Logs/screenshots are retained as artifacts; no PAT is
needed in the workflow. Security, triggers, cache behavior and limitations:
[CI guide](docs/ci.md). A local native equivalent is `./tools/ci_native.sh` after
bootstrapping the toolchains.

## Пропуск повторных uploads

`updateInstancesIfChanged` / `updateVisibleInstancesIfChanged` сравнивают packed
float32 snapshot и пропускают одинаковые submissions. Старые APIs остаются forced.
`updateEffects` обновляет только изменившиеся uniform-группы (`force=true` для
полной синхронизации). Demo использует эти пути и экспортирует счётчики skips/calls.
Это O(N) comparison, не dirty-range upload или обещание hardware FPS:
[контракт и проверка](docs/validation-dirty.md).

## Entity identity и смена состава

`softgfx/identity.alignHistory` сопоставляет snapshots по nonnegative int32 IDs:
перестановка сохраняет историю, spawn/teleport делает snap, despawn исключает
объект. Scratch переиспользуется; вызывайте при новом simulation snapshot, затем
обычный `interpolateInstances` на каждом кадре. Контракт, стоимость и ограничения:
[identity alignment](docs/validation-identity.md).

## Spatial grid для culling

`softgfx/culling`: `initSpatialGrid` → `rebuild` → `collectVisible` сохраняет
порядок индексов и отсеивает группы conservative AABBs. Полезно для больших
статических/редко меняющихся batches; query всё ещё сканирует marks для стабильного
порядка. Стоимость, инвалидация cache и тесты: [uniform grid](docs/validation-grid.md).

## Resource handle lifetime

`Renderer` и `Pipeline` — shared handles: assignment разделяет один ресурс,
state и stats. `dispose` через любой alias инвалидирует все ссылки; повторный
вызов безопасен. При context loss используйте `abandon`, затем новый `init…`.
Это изменение value-copy semantics; [контракт и границы](docs/validation-lifetime.md).

`GpuTimer` также использует shared identity: aliases разделяют очередь и scope,
а dispose/abandon инвалидируют их вместе. Callback failure прекращает работу timer,
не вызывая слепых GL retries. [Timer lifecycle и ограничения](docs/validation-timer-lifetime.md).

## Общие границы frame/query

Создайте один `newContextScopes()` на GL context и передайте его всем pipelines
(`scopes=…`) и timers (второй аргумент `initGpuTimer`). Guard отвергает overlapping
frames/queries разных owners до driver calls; frame и его GPU measurement совместимы.
После context loss нужен новый guard. Nil сохраняет прежний режим без arbitration.
[Контракт, тесты и ограничения](docs/validation-scopes.md).

## Native SDL2 window (Linux)

`examples/native_window.nim` запускает сцену в SDL2 GLES2/3 окне: resize,
drawable-size rendering, 20 Hz interpolation, стрелки/W/S, Escape/close.
`tools/test_window.sh` проверяет GCC/LLVM/cproc-QBE оконный путь под Xvfb/Mesa,
отдельно от EGL pbuffer. Это software-window validation, **не hardware FPS**.
[Запуск, зависимости и границы](docs/validation-window.md).

Desktop CI также использует Openbox + XTest: keyboard camera control, focus loss,
minimize/restore, resize, WM close и Escape. Interactive host замораживает движение
и rendering без focus, сохраняя displayed pose при resume.
[Desktop input/lifecycle](docs/validation-desktop-input.md).

В native demo клавиша **R** пересоздаёт SDL окно/GL context из retained CPU state:
poses, owner edits, camera и post settings сохраняются. Smoke/desktop tests
сравнивают полный framebuffer до/после и проверяют старые handles.
Это planned recreation, не driver-reset recovery:
[контракт и validation](docs/validation-native-recreation.md).

## Native reset recovery и profiling

`--robust` требует reset-notifying GLES context; `--profile` печатает JSON diagnostics
и rolling CPU submit/GPU/swap timing без блокирующих GPU reads. Reset detection
использует advertised KHR/EXT robustness (либо GLES3.2 core), recovery — abandon и
новый context с budget 3/session. Test-only L и --reset-storm проверяют simulated
loss, а не аппаратный reset. [Пакет recovery/reporting](docs/validation-native-recovery.md).
