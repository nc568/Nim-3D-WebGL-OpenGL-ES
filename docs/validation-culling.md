# Девятый срез: conservative frustum culling + indexed instance upload

2026-10-24. Отдельный CPU API для небольшого flat batch, не spatial index,
GPU occlusion, автоматическая сортировка или доказательство ускорения игры.

## API

```nim
import softgfx, softgfx/culling
let local = carMesh.meshBounds() # once, in local coordinates
var visibleIndices = newSeq[int](poses.len) # reserve full source capacity once
# Per frame / whenever camera or transforms change:
let count = frustum(cameraMatrix).collectVisible(local,poses,visibleIndices)
cars.updateVisibleInstances(poses,visibleIndices,count)
cars.renderInstances(width,height,cameraMatrix,clear=false)
```

- `Bounds`: lower/upper float64 triples. `meshBounds` включает все vertices,
  даже неиспользуемые indices (это только увеличивает conservative bounds).
- `frustum`: шесть homogeneous GL planes row3 ± row0/1/2, column-major matrix,
  clip depth [-w,+w]. Деления на w нет: объекты около/за камерой не ломают тест.
  Для другой clip-depth convention будущему backend понадобится другой constructor.
- `transformedBounds`: yaw + positive uniform scale + translation, как Instance.
  CPU double arithmetic, outward padding 1e-5 × operand magnitude для float32
  rounding/cancellation. Это conservative approximation, не exact intersection.
- `visible`: maximum-support vertex на каждой плоскости, относительный epsilon.
  Touching boxes сохраняются. Возможны false positives, но не намеренное
  отбрасывание пограничных объектов. Вырожденные projection matrices (кроме явно
  отвергаемой zero matrix) не проверяются на invertibility: host даёт корректную VP.
- `collectVisible`: валидирует весь snapshot до изменения output, сохраняет
  исходный порядок. indices.len >= items.len, output prefix [0..<count], хвост
  не очищается. Не увеличивает/не уменьшает output buffer.
- `updateVisibleInstances`: прямо упаковывает выбранный prefix в существующий
  36-byte instance stream. Не нужен temporary seq[Instance] или toOpenArray slice.
  Indices строго возрастают, без duplicates, в пределах source snapshot.
  Capacity GPU renderer ограничивает выбранное количество, не весь source.
  Source ограничен прежним MaxInstances=65535. Count=0 снимает экземпляры.
- Invalid input не изменяет предыдущую packing/GPU snapshot; upload/statistics
  происходят только после полной проверки. Cumulative counters saturate как прежде.

Один scratch Bounds на вызов collection; на каждый объект он не создаётся.
Generated JS guard проверяет transformedInto/intersects/packVisible на отсутствие
прямых typed-array allocations и nimCopy. Это НЕ whole-frame heap profile:
frustum creation, collection scratch и backend subviews при изменении count всё
ещё могут создавать объекты. Сложность O(N), до 6 planes на object; нет BVH/grid.

Bounds/local inputs, matrices, Instance проверяются; local bounds должны помещаться
в float32, world Bounds ограничены ±1e100 для безопасной CPU arithmetic. Это не
новая гарантия GPU arithmetic для экстремальных scale×position: overflow shader
операций остаётся за пределами обычного small-world renderer contract.

## Demo

Добавлен opt-in checkbox **Frustum culling**. Bounds машины и index buffer
создаются один раз; на кадре отбираются объекты с учётом текущей camera matrix.
Выключение восстанавливает полный batch. Для прежнего upload instrumentation и
сравнения по умолчанию checkbox выключен. В сцене всего 3 автомобиля, поэтому
не заявляем performance win; при обычном ракурсе все 3 могут быть видимы.
`softgfxTiming()` теперь содержит cullingEnabled, sourceCars, visibleCars.

Blob casters НЕ отсекаются этим списком: offscreen car может отбрасывать видимую
тень. CPU poses сохраняются полностью. Terrain и sky остаются как прежде; их
пространственное разбиение и culling не добавлены. При выбранном culling host
переупаковывает visible batch на каждом draw, даже при неподвижных poses — ещё
одна причина не включать его автоматически для крошечной сцены.

## Проверка

- CPU GCC/LLVM/Node/cproc-QBE: шесть clip planes, near/far/behind camera,
  touching bounds, homogeneous scaling invariance, 1000 transformed-corner
  containment cases, stable prefix/packing, invalid snapshots и empty batch.
- Shared GPU fixture: 41 объектов, 20 snapshots, identity/perspective cameras,
  core/ANGLE и forced fallback. Сравнивается вся картинка до/после culling:
  **точное pixel equality**, selected count < source count, atomic invalid update,
  empty draw. WebGL1/2 и GLES2/3 — PASS.
- Native suites GCC/LLVM/cproc-QBE, release LLVM/QBE GPU fixture — PASS.
- Browser seeded monkey + отдельный fossil UI: прежние 5 scenarios PASS;
  culling toggle не меняет pixels и обратимо восстанавливает полный batch.
- Реальные timing и synthetic autoscale tests прошли при восстановлении среды
  (до добавления default-off demo checkbox). Основной browser suite повторён
  после его добавления. Нет новой аппаратной performance аттестации.
- ARM64 cross-compile/link PASS, не исполнение. Native по-прежнему ANGLE pbuffer,
  не видимое native window. Mobile/physical GPU runtime не выполнен.

## Новый подтверждённый cproc случай

Тест `let box = Bounds(...)` обнаружил прежнюю ABI-проблему в новом виде: Nim
помещает object constant в read-only storage, но передаёт его через неконстантный
C pointer. cproc правильно отвергает discarded qualifiers.

Существующий `-d:nimCproc` workaround writable aggregate storage расширен с
arrays на objects в portableConst и global-let declaration. **Только под флагом**;
обычный GCC/LLVM codegen не меняется. Цена та же: часть данных переходит из rodata
в data; это не полное исправление const-корректности Nim ABI. Regression — сам
constant Bounds CPU test. Patch обновлён, full upstream Nim regression не выполнен.

## Восстановление toolchains

В начале среза ignored build/ и node_modules отсутствовали. Всё восстановлено
из исходников/пакетов, новые тесты действительно запущены; прежние PASS не
засчитывались вместо текущего исполнения.

Добавлен `tools/bootstrap.sh nim|cproc|llvm|native-driver|ui`:

- Nim 2.2.4 и cproc/QBE на ранее зафиксированных commits;
- scoped Nim patch, compiler build, cproc без fallback;
- LLVM через ziglang 0.13.0 (pip --target в build/);
- native ANGLE/SwiftShader из @sparticuz/chromium 131.0.1;
- отдельный fossil checkout на проверенном commit.

Требуются git/GCC/make/python3+pip/node/npm/tar, интернет к GitHub/npm/PyPI.
Nim build_all также получает bootstrap C sources из указанного его build scripts
revision. Скрипт не устанавливает system packages, не меняет основной Git branch
и отказывается работать с несовпадающими ревизиями существующих toolchain repos.
Не исправляет автоматически частично применённые/старые патчи: нужен чистый
отдельный checkout, как описано в cproc.md. Сам первый Nim bootstrap занял несколько
минут; бинарные зависимости не сохраняются в Git.

```sh
./tools/bootstrap.sh nim
./tools/bootstrap.sh cproc
./tools/bootstrap.sh llvm
./tools/bootstrap.sh native-driver
./tools/bootstrap.sh ui
npm ci
NIM="$PWD/build/toolchains/Nim/bin/nim" \
  FOSSIL_SRC="$PWD/build/toolchains/fossil/src" ./tools/test.sh
# Browser: запустить build/ server на 0.0.0.0:8080
TEST_UI=1 USE_BUNDLED_LIBS=1 npm run test:browser
```

Native flags/path setup остаются описанными в предыдущих отчётах и test scripts.
Логи: build/culling-{js,gpu,browser,native,qbe,llvm-release,qbe-release,arm64,
autoscale,timing}.log. Они временные; в репозитории сохранены исходники и scripts.
