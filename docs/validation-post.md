# Пятый срез: T1 target, final pass, scale, FXAA

Проверено 2026-10-24. Это следующий экспериментальный срез, не готовый движок.

## Реализация

- Общий Nim `Pipeline`/`PostSettings`; GL-family детали остаются в backends.
  WebGL2/GLES3: RGBA8 texture + DEPTH_COMPONENT16 renderbuffer, FBO completeness,
  fullscreen triangle (36-byte VBO), GLSL ES 300. Чистый JS, без WASM.
- WebGL1/GLES2, а также выключенный post: default framebuffer, полный размер,
  без final draw. T0 не создаёт post program/buffers/textures/framebuffers.
- Scope `beginFrame` → scene draws с clear=false → `endFrame`; `cancelFrame`
  для finally; минимизированный surface не рисуется. Вложенный begin того же
  pipeline отвергается. Разные pipelines нельзя interleave в одном контексте.
- Scale 0.7–1.0, квантование до 1/1000, pixel rounding half-up, минимум 1 pixel.
  Output dimension 0..16384, hardware texture/renderbuffer limits; default budget
  8×1024×1024 target pixels. Размеры проверяются до выделения GPU-ресурсов.
- Resize сначала создаёт/проверяет новый target; ошибка сохраняет предыдущий.
  Неизменные размеры не выделяют target повторно. Выключение post сохраняет cache.
  `dispose` идемпотентен; `abandon` только при потерянном context, без GL calls.
- Target: 6 bytes/pixel номинально. 800×600 — 2,880,000 bytes; scale .85 даёт
  680×510 — 2,080,800 bytes. Не включает driver padding, default framebuffer,
  programs/VBO. Транзакционный resize временно держит два target (до ~96 MiB
  для двух максимальных default-budget targets, плюс остальная память).
- Demo: T1 on/off, FXAA, dither и manual render scale; context restoration
  сохраняет настройки и CPU scene state. Демо = 3 draws (2 scene + 1 final)
  либо 5 с forced instance fallback. T0 = 2/4, без final.

## Цвет и эффекты

Scene shader уже кодирует sRGB и добавляет scene dither. Target хранит encoded
RGB в обычном RGBA8, НЕ SRGB8. Нейтральный final проход просто семплирует его:
никакого второго encode. Host должен сохранять этот договор и для output target.
Upsampling использует bilinear filtering в encoded space — осознанный компромисс,
не физически корректная linear-light реконструкция, не HDR и не tone mapping.

FXAA — компактный девятисемпловый diagonal-luminance вариант: ранний contrast
threshold, direction clamp 8 texels, сравнение двух фильтров по luma range.
Работает в perceptual/encoded space; это не полный набор вариантов NVIDIA FXAA.
Exposure (0.25–4) и vignette (0–0.6) при включении явно decode → grade → encode.
Дополнительный final dither можно отключить; alpha всегда 1, opaque-only scope.
Default: FXAA+dither on, scale=1, exposure=1, vignette=0.

Final pass отключает depth/blend/cull/scissor, устанавливает color mask, viewport,
attribute layout и нулевые divisors. FBO отвязывается до чтения texture: feedback
loop отсутствует. Полной изоляции произвольного внешнего GL state/VAO/samplers нет.
Ресурсы single-owner по соглашению; compile-time move-only ещё не реализован.

## Проверки и результаты

| Проверка | Результат |
|---|---|
| CPU core/math/resources/instances/post, GCC + Node JS | PASS |
| CPU + native GLES2/3, GCC + LLVM/zigcc | PASS |
| CPU + native GLES2/3, patched Nim → cproc/QBE | PASS |
| Native GPU fixture, release LLVM и release cproc/QBE | PASS |
| Chromium WebGL2/WebGL1, общие GPU fixtures | PASS |
| Browser demo: core/forced fallback × WebGL2/1 + отдельный fossil UI | PASS |
| Linux ARM64 cross-compile/link | PASS, ELF64 AArch64; НЕ запускался |

Общие GPU fixtures:

- direct vs нейтральный 1:1 final: каждый канал ≤1 LSB, без double-encode;
- .7/.8/.9/1 target sizes, cache reuse, disabled path, zero size, nesting,
  cancellation, dispose/recreate, pixel budget failure и повторное использование;
- exposure/vignette, восстановление обычного scene draw после post;
- отдельные диагональные края: FXAA против CPU bilinear/luminance reference,
  каждый канал ≤3 LSB, проверяется ненулевое сглаживание;
- существующие instancing/CPU-reference/depth/empty-overlay/state fixtures
  повторно выполняются внутри offscreen depth16 target на modern API.

Browser monkey tests дополнительно:

- 1000 seeded resizes в пяти сценариях плюс 300 комбинаций post settings/resize;
- unchanged target не reallocates; искусственно incomplete framebuffer при resize
  освобождается, прежний target остаётся рабочим и не пересоздаётся;
- WebGL1 не выделяет post framebuffer даже при программных изменениях controls;
- scale .85 сохраняется через context loss/restore; pixel fingerprint совпадает;
- owner/instance edits при loss, drag/zoom, RAF, upload instrumentation и UI;
- GL errors/page errors/WASM отсутствуют. Screenshot просмотрен визуально.

Артефакты локального прогона (build не хранится в Git):
`post-js.log`, `post-browser.log`, `post-native.log`, `post-qbe.log`,
`post-qbe-release.log`, `post-llvm-release.log`, `post-arm64.log`.
Команды для воспроизведения: tools/test.sh, tools/test_native.sh,
tools/test_cproc.sh и TEST_UI=1 USE_BUNDLED_LIBS=1 node tools/browser_test.cjs;
требуются toolchains/ANGLE/fossil из предыдущих отчётов.

## Дополнительный исправленный блокер cproc

std/unittest активировал генерацию GNU `case a ... b`, которого cproc не понимает.
Под `-d:nimCproc` оба выбора codegen теперь используют portable ветки Nim:
малые диапазоны → case labels, большие → сравнения. Добавлен тест обоих случаев.
Обычный GCC/LLVM codegen не меняется. Экспериментальный patch обновлён:
187 строк / 7 файлов; reverse-apply check PASS. Полный Nim regression suite и
upstream submission всё ещё не выполнены. См. cproc.md.

## Не заявляем

- Нет измерений GPU time/FPS на физической видеокарте или телефоне. Browser и
  native используют software/ANGLE; native — EGL pbuffer, не видимое окно.
  В окружении нет DISPLAY/WAYLAND_DISPLAY и Xvfb/Weston; window host не выполнен.
- ARM проверен только cross-link; mobile/iOS/native-window runtime впереди.
- CPU Quality policy пока не получает валидное GPU timing; manual scale работает,
  но автоматический GPU autoscaler не включён. JS submit time не выдаётся за GPU.
- Не гарантирована работоспособность при реальном GPU OOM/context loss посреди
  синхронного draw; synthetic FBO failure — не физический OOM-тест.
- Нет transparent/HDR pipeline, полноценных T1 blob shadows/fog, T2, Vulkan/Metal.
