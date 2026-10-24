# Состояние и оставшиеся этапы

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

Сначала release workload harness и воспроизводимый hardware report format, параллельно
host lifecycle foundation; затем доступные device runs и выбор T1/T2 budgets.
Добавление Vulkan/Metal не должно нарушать pure-JS/WebGL1 и cproc/QBE regression paths.
Реальные device tests требуют доступного устройства/runner: CI software results нельзя
помечать как пройденные hardware acceptance criteria.
