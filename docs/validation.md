# Протокол проверок — 2026-10-23

Среда: Linux x86_64, Nim 2.2.4 собран из исходников; GCC 12; LLVM/Clang через
`zig cc` из PyPI ziglang 0.17.0. JS запускается Node 22 и Chromium 153
(`@sparticuz/chromium` 153.0.0 + puppeteer-core 25.16.0).

## Фактически выполнено

| Проверка | Результат |
|---|---|
| Nim JS → Node, core + quality | PASS |
| Nim C → GCC, core + quality | PASS |
| Nim C → LLVM/Clang (zig cc), core + quality | PASS |
| Chromium WebGL2, pixels + GL errors | PASS, центр RGBA 198/120/95/255 |
| Chromium forced WebGL1 | PASS, центр RGBA 188/118/97/255 |
| По 200 seeded resize на WebGL1, WebGL2, UI composition | PASS |
| WEBGL_lose_context + restore на трёх сценариях | PASS |
| UIRelays HTML overlay + WebGL2, проверка DOM и пикселя | PASS |
| Native GLES2/3, GCC, EGL pbuffer, pixel readback | PASS |
| Native GLES2/3, LLVM/Clang, EGL pbuffer, pixel readback | PASS |
| cproc/QBE, ARC | FAIL, подробности ниже |
| Видимое нативное окно | НЕ ПРОВЕРЕНО: нет display/window host |
| ARM desktop / Android / iOS / реальные слабые GPU | НЕ ПРОВЕРЕНО |

GLES использовал ANGLE/SwiftShader из тестового пакета `@sparticuz/chromium@131.0.1`
(архив swiftshader.tar.br), а не системный драйвер. Chromium 153 включает placeholder
GLES .so без нужных экспортов: для native теста они непригодны. Ни один бинарный
драйвер не включён в репозиторий. Native harness выбирает ANGLE Vulkan/SwiftShader
headless display при `-d:angleSwiftShader`. Наличие Vulkan внутри тестового драйвера
не означает наличие Vulkan backend в библиотеке.

Пример воспроизведения после распаковки драйверов в `$ANGLE_LIB`:

```sh
LD_LIBRARY_PATH="$ANGLE_LIB" nim c -r -d:angleSwiftShader \
  -d:eglLibrary="$ANGLE_LIB/libEGL.so" -o:build/test_gles tests/test_gles.nim
# LLVM: добавить --cc:clang; если используется Zig, создать исполняемый wrapper:
# #!/bin/sh
# exec /path/to/zig cc "$@"
# --clang.exe:/path/to/wrapper --clang.linkerexe:/path/to/wrapper
```

До установки тестового драйвера native запуск ожидаемо падал с отсутствующей
`libEGL.so.1`. Обычный `eglGetDisplay` с ANGLE также не заработал без headless attrs;
это не было засчитано как PASS.

## cproc / QBE: НЕ ГОТОВО

Проверенные ревизии:

- cproc `d1c53ddf56571573a7025324c8dd5c6d547a4d1f` (michaelforney/cproc).
- QBE `d62b154d05de438e12e8b5e980d43ef65ea1bb6c` (8l/qbe; старое зеркало,
  потребуется перепроверка на актуальном upstream).

Сначала cproc отвергал GCC options `-w`, `-fmax-errors=3`.
`tools/cproc_cc.py` убирает небольшой явный список необязательных флагов,
задаёт `__CHAR_BIT__=8` для проверенной целевой платформы и `NIM_CPROC`.
**Никакого fallback на GCC для компиляции C нет.** cproc сам использует cpp/as/ld.

`nimbase.h` выбирает fallback `rettype __inline name`, некорректный для указательных
результатов и строгого C parser. Экспериментальный патч
`patches/nim-2.2.4-cproc.patch` выбирает стандартный `inline rettype name`.
Патч не меняет глобально все компиляторы и не применяется автоматически.

После него сборка ARC останавливается на RTTI initializer:

```
error: assignment to pointer discards qualifiers
... TNimTypeV2 ... .display = TM__..._3 ...
```

Сгенерированная таблица `static NIM_CONST NU32[...]` присваивается неконстантному
указателю `display`. GCC/Clang принимают это с предупреждением, cproc — нет.
Следующий шаг: правильная const-корректность Nim RTTI/codegen, а не отключение const
во всём runtime. QBE codegen полного приложения ещё не достигнут.
Дополнительная попытка refc остановилась на `-fno-omit-frame-pointer`; это не обход
для production, GC stack scanning требует отдельного аудита.

Воспроизведение ARC (после применения патча к своей копии Nim 2.2.4):

```sh
# cproc и qbe должны быть в PATH
nim c --cc:gcc --threads:off --mm:arc \
  --gcc.exe:"$PWD/tools/cproc_cc.py" \
  --gcc.linkerexe:"$PWD/tools/cproc_cc.py" \
  --nimcache:build/cache-qbe -o:build/test_qbe tests/test_core.nim
```

Не заявляем поддержку QBE/ARM только на основании наличия скрипта.

## UIRelays

Проверена `nc568/fossil-nim`, ветка `uirelays-web-backends`, commit
`1d01eed8870403ca617418bbc6ff5ff52c20f3c8`. Собраны upstream hello в JS/HTML и
локальный `examples/ui_overlay.nim`. Пробный FNV hash для `hello` в JS дал
ожидаемое `1335831723`; ошибки в нём не подтверждены.

Исправлений upstream нет: в выполненном минимальном сценарии подтверждённых
багов не найдено. Полный UI monkey suite и маршрутизация ввода пока не проверены.

## Ограничения тестов

Это smoke/regression tests первого среза, не аттестация полного API и не benchmark.
Скриншоты/логи остаются в игнорируемом `build/`. Для проверки скорости нужны
прогрев, repeatable snapshots, p50/p95 и отдельные реальные GPU/device runs.
