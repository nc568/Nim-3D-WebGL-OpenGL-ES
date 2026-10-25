# Пакет 31: workload recipes и расширенный iteration soak

## Что воспроизводится

`soak-recipe-ENGINE.json` задаёт generator grid-v1, frames/cycles и ordered presets
(WebGL API, count, fallback). SHA-256 compiled `browser_soak.js` и runner sources
проверяются до запуска scenario. Проверяется также SHA-256 файла, реально отдаваемого
локальным HTTP server, чтобы stale served build не совпадал только на диске. Git revision — provenance metadata; authoritative
code identity — hashes, поэтому documentation-only commit не ломает replay.

Это воспроизведение **тестового workload**, не импорт diagnostic capture из inspector
и не replay произвольной игры. Browser version/driver/OS, timing, GPU faults и состояние
других ранее выполненных тестов рецептом не фиксируются. Pixel equality проверяется
внутри одного engine/run, а не между разными драйверами.

Runner всегда сохраняет рецепт, включая failure cases. Failure report содержит
preset index, cycle и последний tick (если страница ещё доступна). Можно повторить
весь ordered рецепт; для локализации можно оставить subset cases. Subset может не
воспроизвести проблему, зависящую от предыдущих presets/других suites.

## Валидация и ограничения

Только JSON file <=16 KiB, strict keys/version, whitelisted API/counts, boolean
fallback, no duplicate presets. Никаких URL, callbacks, произвольных shader/scripts
или eval из файла. Fixture tracker по-прежнему внедряет только доверенный repo code.
Frames 48..10000, cycles 2..100, 1..12 presets и общий cap **120000 scenario frames**.
Противоречащие recipe + frame/cycle environment overrides запрещены, code mismatch
не приводит к silent fallback. Для сравнения изменённого кода создайте новый рецепт.

## Ручной запуск

1. `npm ci`; собрать `tools/test.sh` или скачать matching `web-test-bundle` в build/.
2. `node tools/serve_tests.cjs` — отдельный процесс.
3. На Linux с pinned Chromium:

```sh
USE_BUNDLED_LIBS=1 SOAK_RECIPE_FILE=path/to/soak-recipe-chromium.json node tools/run_soak.cjs
```

Firefox: предварительно `npx playwright install --with-deps firefox`, затем
`BROWSER_ENGINE=firefox LIBGL_ALWAYS_SOFTWARE=1 SOAK_RECIPE_FILE=... xvfb-run -a node tools/run_soak.cjs`.
WebKit: pinned Playwright engine на macOS ARM64. Для non-replay прогона можно задать
SOAK_FRAMES/SOAK_CYCLES, но не одновременно с SOAK_RECIPE_FILE. Браузер закрывается
в finally; ошибки дают nonzero exit. Schema tests не требуют browser/toolchain.

## Actions

workflow_dispatch предлагает frames 96/240/960 и cycles 2/3/10. Push/PR сохраняют
96×2. Runner classes, billing tier и job timeouts не меняются; более длинные тесты
занимают больше обычного CI-времени. Ни GPU larger runner, ни self-hosted не добавлены.

Расширенный checkpoint этого пакета: **240×3×12 = 8640 scenario frames/engine**,
плюс **396 oracle draws/engine** (11 checkpoints на цикл). Это всё ещё bounded
iteration soak, не 8/24-часовая проверка и не доказательство отсутствия driver/JS
heap leaks. Итог прогона подтверждается конкретным Actions run, не наличием рецепта.


Standalone replay сохраняет `replay-ENGINE.json`/`replay-recipe-ENGINE.json`, не
перезаписывая исходный soak report. В CI первый preset дополнительно выполняется
через standalone CLI из записанного recipe; его checkpoints/counters/resources
сравниваются с исходным запуском в том же engine/environment. Этот дополнительный
replay не включён в приведённые выше 8640 scenario frames основного soak.

### Автоматический extended checkpoint (пакет 32)

Из-за отсутствия Actions-write у интеграции ручной запуск пакета 31 не состоялся
(HTTP403). Теперь browser release suite дополнительно выполняет фиксированный
240×3 checkpoint через обычную push/PR CI. Его `extended-*.json` отделены от
базовых и replay outputs. Детали: [validation-upload-ranges.md](validation-upload-ranges.md).
