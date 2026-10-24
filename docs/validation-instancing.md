# Этап 4: динамические машинки и instancing — 24 октября 2026

## Реализация

Один mesh batch получает массив `Instance`: position.xyz, yaw (радианы),
положительный uniform scale, линейный RGB tint. При update CPU один раз вычисляет
sin/cos; GPU-запись — 9 float32 / 36 байт. В шейдере поворачиваются и позиции,
и нормали. Nonuniform/negative scale не поддерживаются.

| Контекст | Выбранный путь |
|---|---|
| WebGL2 | core drawElementsInstanced / drawArraysInstanced |
| WebGL1 + ANGLE_instanced_arrays | ANGLE instancing |
| WebGL1 без ANGLE либо forceFallback | N обычных draw calls, constant vertex attributes |
| GLES3 | core instancing, entry points через resolver |
| GLES2 | fallback; native ES2 extensions пока не используются |

Используются 7 vertex attribute slots (4 mesh + 3 instance), укладываемся в минимум
ES2/WebGL1. Instance divisors и enabled arrays сбрасываются после draw. Обычный
render задаёт identity instance. `clear=false` сохраняет color/depth для следующего
непрозрачного batch. Это пока **не полный state isolation для чужого GL-кода**.

Capacity задаётся при init (1..65535), GPU storage выделяется один раз. Update
использует bufferSubData, не bufferData. JS Float32Array переиспользуется; subarray
view меняется только при изменении количества экземпляров. Fallback вообще не
загружает instance buffer: использует тот же CPU snapshot и constant attributes.
Нулевой count не вызывает draw; clear=true всё равно очищает target, clear=false
оставляет предыдущую картинку. Превышение capacity и невалидные числа отвергаются
до изменения snapshot. Счётчики cumulative bytes/updates saturate на high(int),
чтобы длительная работа не завершалась int overflow (особенно Nim JS int32).

## Демонстрация

- `arenaMesh(..., includeCars=false)` — земля/деревья; отдельный общий `carMesh`.
- Три экземпляра машины, движения по демонстрационным траекториям.
- «▶ Ехать», «Пауза», «Шаг +0,25 с». Старт в паузе для воспроизводимости.
- Ссылки WebGL1/2 и принудительный fallback; UI показывает реальный mode и draws.
- 2 draw calls/frame при core/ANGLE, 4 при fallback (земля + три машины).
- 108 GPU upload bytes на update трёх машин на аппаратном пути, 0 на fallback.
- Geometry GPU storage: 22032 байта (два mesh VBO+IBO), плюс 108 байт instance
  capacity на аппаратном пути. Текстуры двух renderer пока не разделяют ресурсы.
- Позиции сохраняются на host. После context restore пересоздаются оба renderer
  и загружается последняя поза, в том числе изменённая во время потери контекста.

Это демонстрация рендера, не детерминированная физика/предсказание игры. Интерполяция
снапшотов фиксированных игровых тиков пока не реализована.

## Проверено запуском

| Проверка | Результат |
|---|---|
| Instance pack/validation: GCC, LLVM, cproc/QBE, JS Node | PASS |
| WebGL2 core / WebGL1 ANGLE / принудительный fallback | PASS |
| GLES3 core / GLES2 fallback: GCC, LLVM, cproc/QBE | PASS, EGL pbuffer |
| GLES release: LLVM и cproc/QBE | PASS |
| Indexed и non-indexed instance draw | PASS |
| Hardware vs fallback: полное совпадение framebuffer | PASS |
| Независимый CPU-baked transform/normal/tint oracle | PASS, допуск 2/255 |
| 30 seeded snapshots на каждый mesh/path: grow/shrink/overlap/zero | PASS |
| Reject NaN / invalid scale/tint / capacity overflow, старый snapshot цел | PASS |
| JS scalar double → float32 overflow/scale-underflow до GL upload | PASS |
| Opaque batch composition и depth, включая empty overlay | PASS |
| Static draw после instanced: divisors/transform не утекли | PASS |
| Dispose/recreate и восстановление host snapshot | PASS |
| Saturating counters рядом с high(int) | PASS |
| Browser: 5 сценариев × 200 seeded resize, input и RAF | PASS |
| Browser: instance delta без geometry realloc; один reusable typed view | PASS |
| Browser: territory + poses после context loss/edits во время loss | PASS |
| UIRelays overlay | PASS, upstream не изменялся |
| ARM64 Linux GLES executable через LLVM | Compile/link PASS, НЕ запуск |

Проверены те же Nim 2.2.4, GCC 12, Zig/Clang, patched cproc и QBE, Chromium 153,
ANGLE/SwiftShader, что зафиксированы в предыдущих отчётах и `cproc.md`.

При изучении сгенерированного JS обнаружены временные Instance/Float32Array и
nimCopy в for-each packer. Заменены на прямой индексированный доступ; demo snapshot
обновляет существующие поля. `tools/check_js_hotpath.cjs` проверяет отсутствие
**прямых** typed-array allocations/nimCopy в этих трёх функциях. Это не доказательство
нулевых аллокаций всего кадра: камера, UI и runtime отдельно не профилировались.

## Воспроизведение

```sh
NIM=/path/to/nim FOSSIL_SRC=/path/to/fossil-nim/src ./tools/test.sh
python3 -m http.server 8080 --bind 0.0.0.0 --directory build
# В другом процессе, при работающем сервере:
TEST_UI=1 USE_BUNDLED_LIBS=1 npm run test:browser
```

`tools/test_native.sh` и `tools/test_cproc.sh` теперь включают test_instances и
instance GPU probe из test_gles. Настройки LLVM/GLES/cproc описаны в предыдущих
отчётах. Browser GPU probe запускается на `/gpu-test.html` и `?webgl1` независимо
от demo. Node-запуск не выдаётся за проверку WebGL.

## Ещё не проверено / не сделано

Физический GPU, видимое native-окно, ARM execution, Android/iOS и производительность
на слабом телефоне не аттестованы. Меньше draw calls и известный размер upload —
не FPS benchmark. Dynamic buffer orphaning/ring buffers пока не используются;
на некоторых драйверах bufferSubData может stall.

Нет culling, LOD, sorting прозрачности, mesh/material command list, resource sharing,
производственного snapshot/interpolation API. Renderer всё ещё нельзя копировать;
dispose должен происходить при current-контексте. T1 render target/final pass,
FXAA, тени и профилирование остаются следующими этапами.
