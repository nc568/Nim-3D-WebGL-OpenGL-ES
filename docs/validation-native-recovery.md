# Пакет 20: native reset detection, bounded recovery и diagnostics

## 1. Context health и recovery

`softgfx/recovery` — backend-neutral ResetMonitor + RecoveryBudget. Monitor latch-ит
первый nonzero status, инвалидирует ContextScopes и больше не вызывает driver.
Unsupported callback не считается доказательством здоровья; callback exception
latch-ит unknown failure и пробрасывается (host прекращает работу без GL cleanup).
RecoveryBudget ограничивает session тремя автоматическими восстановлениями; четвёртый
reset завершает приложение. Manual R не расходует этот budget.

`softgfx/recovery/gles` разрешает glGetGraphicsResetStatusKHR/EXT только при наличии
соответствующего advertised extension, либо core entry point для GLES 3.2. Отчёт
содержит источник и GL_RESET_NOTIFICATION_STRATEGY. Native demo проверяет reset перед
render iteration; на unfocused pause не опрашивает GL каждый 10ms. Это не исключает
reset между двумя GL calls: мгновенное/asynchronous обнаружение не обещается.

`--robust` явно запрашивает SDL robust-access + lose-context-on-reset context. Запрос
не ослабляется молча: неподдерживаемая конфигурация завершает запуск с ошибкой.
В CI strict robust проверяется через SDL GLX ES-profile path (FORCE_EGL=0):
SDL2 EGL path не переносит reset-notification setting корректно в выбранной версии.
Обычная матрица остаётся на EGL. Проверяются реальные GL_CONTEXT_ROBUST_ACCESS и
GL_RESET_NOTIFICATION_STRATEGY, не cached SDL attributes. Desktop GL вместо GLES
по-прежнему отвергается. Без флага обычный режим остаётся доступен, но наличие status API при strategy
NO_RESET_NOTIFICATION не гарантирует уведомления о hardware reset.

После наблюдаемого loss demo использует Renderer/Pipeline/GpuTimer.abandon, не
GL delete/end calls. SDL context/window teardown всё равно выполняется platform
API. Retained assets/owners/camera/post/poses используются для нового контекста;
первый frame не включает время восстановления. Если новый context создать нельзя,
приложение завершает работу; rollback к потерянному context не выполняется.

## 2. Инъекция и reset storm

--smoke автоматически выполняет 2 planned recreations + 1 loss injection.
--desktop-test принимает L для инъекции; вне test mode L НЕ вызывает потерю.
Инъекция — вызов markLost в исправном контексте, **не физический reset**. Before-loss
framebuffer снимается до markLost, затем проверяется exact RGBA parity после rebuild.
Для настоящего наблюдаемого reset pre-loss readback невозможен/не выполняется.
Stale renderer/pipeline/host/scopes/timer ссылки должны отвергать операции.

--smoke --reset-storm подаёт четыре loss signals. Harness требует nonzero exit,
сообщение budget exhausted и exactly three recovery attempts; это отдельный negative
integration test. CPU tests проверяют latch, отсутствие повторных driver polls,
unsupported/exception branches, scope invalidation и budget exhaustion на JS/GCC/LLVM/QBE.

## 3. Native profiling/report

--profile включает bounded nonblocking GPU timer и rolling CPU submit/swap summaries.
30 warmup frames, максимум 120 samples; CPU submission и swap wait разделены, GPU
results читаются только после availability. Это НЕ CPU+GPU summed time и НЕ FPS.
После context recreation окна статистики сбрасываются: report описывает last context.
GPU disjoint очищает GPU statistics. Нет readPixels или glGetError в обычном --profile.

На выходе печатается JSON строка NATIVE_REPORT: actual API/renderer, robust request,
reset source/strategy, real vs injected reset counts, recovery attempts, CPU/GPU/swap
median/p95/sample counts, upload/skipped counters и target bytes. Нет samples → null,
а не 0 ms. JSON formatting выполняется один раз при выходе, не в render hot path.
Test modes включают profiling автоматически, но тестовые readbacks и software Mesa
не позволяют трактовать эти цифры как production/hardware benchmark.

## CI и границы

Оконная матрица GCC/LLVM/cproc-QBE × GLES2/GLES3 включает обычный smoke, desktop
Openbox/XTest (R и L), strict robust smoke и negative reset storm. JSON schema,
notification strategy robust context и recovery counts проверяет collector;
`build/native-report.json` сохраняется в native-evidence вместе с логами.
Старые JS/WebGL/native/ARM64 cross-link checks сохранены.

Не заявлены hardware reset injection, physical GPU acceptance, Android/iOS host,
ARM runtime, Windows/macOS ports или завершённый E1–E7 benchmark. На драйверах без
robustness automatic hardware-loss recovery остаётся недоступным. CPU-driven fault
injection проверяет host/control flow, но не поведение реального сброшенного GPU.
