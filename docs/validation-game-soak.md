# Пакет 29: provisional game-like presets и короткий soak

Это шаг к integration readiness, НЕ финальные workloads игры. Используются реальный
low-poly car mesh и arena/territory из demo, но counts/layout/quality schedule заданы
нами предварительно. Game snapshot formats, peak counts и реальные budgets пока
не подтверждены пользователем. RNG нет: generator grid-v1 определяется count/tick.

## Matrix

Chromium, Firefox, Playwright WebKit/macOS ARM; WebGL1/2 × auto/fallback ×
64/256/1024 cars = 12 cases/engine. По умолчанию 2 полных цикла создания/удаления,
96 сценарных кадров/cycle: **2304 scenario frames/engine**, плюс oracle draws.
Это короткий iteration-based CI soak, не многочасовая/суточная проверка.

Каждый цикл включает:

- stationary/sparse-moving/all-moving snapshots;
- orbit и near/far camera, grid-vs-flat exact visible prefix на каждом шаге;
- включение/отключение culling, сравнение выбранного batch с full batch по пикселям
  каждые 24 шага и в конце;
- NPOT territory rectangle updates с точными byte/call counters;
- T1 enable/disable, scale 1/0.7 и FXAA; legacy остаётся direct T0;
- explicit dispose/init на том же context, replay тех же settings/ticks, сравнение
  checkpoint hashes и финальных counters с предыдущим cycle.

ReadPixels/getError используются только в test harness. Это не timing/FPS benchmark;
счётчики uploads включают часть работы oracle, поэтому не являются isolated budgets.
Pixel hash используется для replay между cycles; внутри checkpoint сравнивается
каждый байт optimized/full image. Resource setup/teardown не timed.

## Resource tracking

Test-only wrappers для create/delete Buffer, Texture, Program, Shader, Framebuffer,
Renderbuffer, Query, VertexArray (когда доступны). Отслеживаются successful handles,
live/created/deleted/peak и duplicate/unknown deletion. После каждого stop требуется
zero live + created==deleted для всех отслеживаемых типов. Между cycles сравниваются
steady live counts. Обёртки восстанавливаются после успешного case.

Это баланс API create/delete requests, **не доказательство отсутствия JS heap leak
или driver/physical VRAM leak**. Shader deletion может отложиться до удаления program;
GPU driver также может отложить release. GC, wrapper retention и контекстные ресурсы
в этот счётчик не входят. Максимальные физические memory budgets не утверждаются.

## Запуск / evidence

`tools/test.sh` создаёт release `soak.html`/`browser_soak.js`; общий browser runner
запускает `tools/soak_test.cjs`. Отчёты: `soak-ENGINE.json`, включая параметры,
checkpoints, counters и resource balances. Failure screenshots сохраняются отдельно.

Для более длинного **ручного** прогона можно задать `SOAK_FRAMES` (48..10000) и
`SOAK_CYCLES` (2..100). Например 960/10. Ограничения времени CI jobs не увеличены;
это число итераций, а не гарантия длительности в часах. Сначала проверяйте короткий
preset. Реальные context-loss tests остаются отдельной прежней suite: здесь planned
resource recreation, не физический reset и не восстановление lost context.

Native GCC/LLVM/QBE/GLES regression matrix сохраняется; этот новый orchestration
пока browser-only, не заявляется новый native large-scene soak.
