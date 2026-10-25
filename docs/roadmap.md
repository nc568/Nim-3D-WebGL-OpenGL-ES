# Состояние и оставшиеся этапы

## Приоритет пользователя

WebGL — основной target, OpenGL ES — второй; остальное менее важно.
Физические устройства позже. Сейчас оптимизируем графику игры и diagnostics,
расширяем browser matrix (Chromium, Firefox, WebKit/macOS ARM). Vulkan/Metal
не должны отнимать время у этих задач. См. validation-web-debug.md.

## Реализовано (экспериментальное middleware)

Pure JS без WASM, WebGL1/2 и native GLES2/3; GCC/LLVM/cproc-QBE matrix.
Low-poly forward pipeline, T0 direct и T1 post subset, territory owner maps/deltas,
instancing/fallback, culling/grid, identity history/interpolation, conditional/range
uploads, timers/autoscale, explicit resource/context lifecycle. Linux SDL2 host:
input, pause/focus, planned recreation, injected recovery и bounded recovery budget.
Fossil UI остаётся отдельным DOM overlay, не частью graphics middleware.

## Не закончено

1. **Hardware evidence E1–E7.** Физические GPU разных классов, реальный ARM runtime,
   mobile, стабильные release/warmup замеры CPU/GPU/FPS/memory. Software pixels,
   virtual windows и cross-link не заменяют этот этап. Strict robust-context probe
   в software CI отвергает недоступную reset notification; physical reset не испытан.
2. **Mobile/platform hosts.** Android/iOS lifecycle, suspend/resume, orientation,
   touch/input, surface recreation, соответствующие toolchains и устройства.
   Desktop вне текущего Linux SDL2 matrix также требует отдельных runtime прогонов.
3. **Полный T1/T2.** Shadow maps и optional bloom/FSR/MSAA, tier budgets и качественные
   сравнения — после workload/hardware evidence, а не включать всё по умолчанию.
4. **Оптимизация и масштаб.** Более репрезентативные сцены, release benchmark harness,
   identity worst-case collisions, grid rebuild/query tradeoffs, allocation profiles.
   Range uploads пока один bounding span: решение о chunking требует измерений.
5. **Vulkan/Metal.** Будущие backend'ы; существующий shared CPU model оставляет путь,
   но backend-neutral render graph/resource transitions/реализации ещё не готовы.

Network jitter/authoritative synchronization — соседний host/gameplay контракт,
не обещанная реализация graphics §§6–7. UI toolkit также остаётся отдельным проектом.

## Порядок продолжения

Сначала WebGL release workloads под сцены игры, browser diagnostics и frame budgets;
затем OpenGL ES parity. Физические device runs и выбор дорогих T1/T2 опций — позже.
Добавление Vulkan/Metal не должно нарушать pure-JS/WebGL1 и cproc/QBE regression paths.
Реальные device tests требуют доступного устройства/runner: CI software results нельзя
помечать как пройденные hardware acceptance criteria.

## Первый integration release и оценка оставшегося объёма

Актуальные границы, ориентировочная готовность и проверяемые критерии вынесены в
[release-readiness.md](release-readiness.md). Release CPU workloads, GPU evidence,
submission observations и camera/post uniform caches уже добавлены; следующий
крупный пробел — workload/soak под реальные игровые ограничения и интеграция host.
