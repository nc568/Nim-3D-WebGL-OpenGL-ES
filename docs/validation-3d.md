# Этап 2: 3D-камера и статическая сцена — 24 октября 2026

Это дополнение, не замена исторического отчёта `validation.md`.

## Реализовано

- `math3d.nim`: Vec3, Mat4, умножение, perspective, lookAt, Camera.
  Правосторонняя система, Y вверх, -Z вперёд камеры, GL clip depth [-1,1].
- `geometry.nim`: боксы с мировыми позициями, нормалями и поворотом вокруг Y.
- View-projection uniform в обоих адаптерах; location и JS typed storage кешируются.
- Арена: три машинки из боксов, плитки, деревья; один статический VBO/draw.
- Browser host: pointer drag с capture/cancel, zoom с ограничением дистанции,
  сохранение камеры и восстановление GPU-ресурсов при context loss.
- Нулевая поверхность обнуляет draw stats; нечисловая матрица отвергается до draw.

## Выполненные проверки

| Проверка | Результат |
|---|---|
| core/quality, GCC + Node JS | PASS |
| Math/geometry, GCC + Node JS + LLVM/Clang | PASS |
| Identity, matrix composition, near/far projection, lookAt | PASS |
| Invalid frustum / NaN / Infinity / degenerate camera | PASS |
| Winding и нормали всех шести граней, несколько yaw | PASS |
| 201 положения камеры: target в центре projection | PASS |
| WebGL1 + WebGL2 + UIRelays composition | PASS |
| По 200 seeded resizes для трёх browser сценариев | PASS |
| Drag и wheel реально изменяют framebuffer | PASS |
| Context loss/restore: совпадает полный framebuffer fingerprint | PASS |
| GLES2/3 native, GCC + LLVM, EGL pbuffer | PASS |
| Native occlusion: ближняя красная грань перед дальней синей | PASS |
| Native 3D camera change / return: картинка меняется / точно восстанавливается | PASS |
| ARM64 Linux: math + GLES test, cross-compile/link через LLVM | PASS сборки, **НЕ запуск** |
| cproc ARC | FAIL: const qualifiers в Nim RTTI initializer |

Браузерный smoke больше не предполагает красный центр старого треугольника:
теперь в центре может быть стекло машины. Проверяется наличие красной машины и
тёмной геометрии во всём framebuffer. Дополнительно проверяется изменение картинки
при реальном вводе и её восстановление после context loss.

ARM64 executables проверены через `readelf -h`: ELF64, Machine AArch64.
Проверки на ARM-устройстве/эмуляторе не было. Мобильные hosts, физический GPU и
видимое native-окно всё ещё не проверены. Software render timing не benchmark.

## Воспроизведение

```sh
NIM=/path/to/nim ./tools/test.sh
# При желании добавьте FOSSIL_SRC=/path/to/fossil-nim/src
python3 -m http.server 8080 --bind 0.0.0.0 --directory build
# В другом процессе:
USE_BUNDLED_LIBS=1 npm run test:browser
# С собранным ui_overlay:
TEST_UI=1 USE_BUNDLED_LIBS=1 npm run test:browser
```

Native matrix (GCC всегда, LLVM и GLES включаются явно):

```sh
NIM=/path/to/nim CLANG=/path/to/clang \
  TEST_GLES=1 ANGLE_SWIFTSHADER=1 \
  EGL_LIBRARY="$ANGLE_LIB/libEGL.so" LD_LIBRARY_PATH="$ANGLE_LIB" \
  ./tools/test_native.sh
```

В этой среде CLANG — wrapper `exec /path/to/zig cc "$@"`; использован ziglang
0.17.0. EGL/GLES: ANGLE/SwiftShader из `@sparticuz/chromium@131.0.1`.
Браузер — Chromium 153.0.0, Nim — 2.2.4. UIRelays остался на проверенной ревизии
`1d01eed8870403ca617418bbc6ff5ff52c20f3c8`; upstream-файлы не изменялись.

ARM64 cross-build (Zig Clang wrapper):

```sh
nim c --cpu:arm64 --os:linux --cc:clang \
  --clang.exe:/path/to/zigcc --clang.linkerexe:/path/to/zigcc \
  --passC:--target=aarch64-linux-gnu --passL:--target=aarch64-linux-gnu \
  --nimcache:build/cache-arm64 -o:build/test_gles_arm64 tests/test_gles.nim
```

## cproc: что выяснили дополнительно

Повторён исходный ARC-тест с патчем `nimbase.h`: const mismatch воспроизводится.
Попытки изменить Nim alias/field pragma не дали корректного C field declaration;
они **откачены и не включены в патчи**.

Отдельно старое QBE-зеркало упирается в длину идентификаторов Nim. Проверено более
новое зеркало `kengorab/qbe-mirror`, commit
`120f316162879b6165deba77815cd4193fb2fb59`, с экспериментальным увеличением NString
80 → 1024, но первым блокером полного последовательного билда остаётся RTTI const.
Этот QBE-эксперимент тоже не объявлен рабочей поддержкой и не включён в поставку.

Следующий шаг по cproc — корректное изменение Nim C codegen/runtime RTTI с отдельным
регрессионным тестом, а не отключение const для всего runtime.
