# Архитектура и границы первого этапа

Исходные требования: только разделы 6–7 приложенного плана. Прежнее предложение
писать графику на TypeScript не используется. Графический код — Nim.

## Слои

1. Данные игры, меши/материалы, снапшоты: backend-neutral; никаких GL enum/handles.
2. Политика рендера: возможности, качество, метрики, порядок проходов.
3. Backend: сейчас WebGL и GLES. Общий shader generator применим **только** к GL-семейству.
4. Host: canvas/RAF, EGL/SDL, Android/iOS lifecycle; отдельно от библиотеки.
5. UI: отдельное дерево DOM либо отдельный UI pass с явной передачей владения state.

Текущий `Renderer` — bootstrap, не зафиксированный публичный API. Для Vulkan/Metal
нужно будет выделить backend-neutral pipeline/resource descriptors и shader variants.
Не следует эмулировать весь OpenGL поверх Vulkan. Ни Vulkan, ни Metal сейчас не реализованы.

## Последовательность следующих работ

| Этап | Работы и критерий готовности |
|---|---|
| Корректность ядра | move-only/generation handles, OOM/rollback, лимиты, полная state isolation, resize/lifecycle tests |
| Настоящее 3D | **Сделано:** матрицы, камера, depth, статические боксы с world-space normals. **Далее:** smooth normals/фаски, AO, front-to-back |
| Игра | R8 owner map в ES3/WebGL2; LUMINANCE fallback в ES2/WebGL1; delta uploads, UNPACK_ALIGNMENT=1, nearest/no mipmaps; палитра, ленты следов |
| T0 | подготовленное освещение, градиент неба, согласованный туман, blob shadows; без поста |
| T1 | ambient cube, инстансинг (core/ANGLE/fallback), framebuffer + final FXAA/correction/dither |
| Качество | реальный render-scale, benchmark warmup, median/p95 отдельно CPU/GPU, GPU timer disjoint handling |
| T2 | capsule, shadow map, bloom, MSAA/FSR только после измерений E1–E7 |
| Hosts | SDL desktop, Android EGL, ARM64 CI/device runs, iOS host/ограничения GLES и будущий Metal |

WebGL2 ≈ GLES3, но это **не идентичные API**. Нужны проверки extensions, formats,
FBO completeness, shader precision и лимитов на реальном устройстве. `baseline`
описывает core API, не автоматически разрешает использование расширений.
RGB10_A2, packed normals, multi_draw пока не задействованы.

## Что нельзя упустить

- Pure JS: typed arrays держать долго; текущий upload копирует seq в Float32Array
  один раз, не в render loop. Для динамических данных нужен API persistent typed views.
- Линейное смешивание и sRGB: текущая непрозрачная сцена корректно кодирует выход,
  но будущие прозрачность/пост требуют отдельного решения о пространстве render target.
- Context loss/restore, suspend/resume, нулевой размер окна, DPR и ограничения VRAM.
- UI input routing, pointer capture, clipboard/security, touch и CSS pixel vs framebuffer.
- В примере UI `pointer-events:none`: интерактивные области не реализованы.
- Время из software rasterizer не использовать как доказательство скорости на телефоне.
- iOS/Android/ARM и видимое desktop-окно должны иметь отдельные отчёты: pbuffer их не заменяет.

Deferred G-buffer, SSAO, тяжёлые эффекты и WebGPU-only путь не входят в базовый план.

## Уточнение после второго среза

`render(width, height, viewProjection)` принимает мировую view-projection матрицу;
без неё используется identity (низкоуровневый fixture/совместимость). Локальные
model transforms пока запекаются в статический mesh, не выдаём это за instancing.
Геометрия арены — 3060 вершин, один draw, 110160 байт VBO (9 float32/вершина).
Цветные плитки — декоративные боксы, не реализация владения территориями.
Следующий вертикальный срез: indexed mesh + owner texture и дельта-загрузки;
затем динамические машины/инстансинг и T1 render target/final pass.

## Уточнение после третьего среза

Предыдущие числа геометрии выше относятся к этапу 2. Теперь: 864 вершины,
1296 uint16 индексов; owner texture и palette; 15-byte delta в демо.
Индексированный меш и карта территории готовы как минимальный графический путь.
Далее: динамические машины и instancing с fallback, затем T1 render target/final
pass. Текущий cproc-статус и компромиссы — в `cproc.md`.

## Уточнение после четвёртого среза

Динамический batch теперь отдельный renderer с фиксированной instance capacity:
local geometry + Y rotation/translation/uniform scale/tint, 36-byte stream.
Core/ANGLE и fallback сравниваются с CPU oracle и друг с другом. Демо составляет
кадр двумя opaque batches, второй с clear=false. Детали в validation-instancing.md.
Следующий вертикальный срез: T1 render target + минимальный final pass, а затем
FXAA/scale с проверкой linear/sRGB и pixel parity. CPU политика качества сама по
себе всё ещё не означает наличие динамического render target.


## Уточнение после пятого среза

T1 target/final pass реализованы: RGBA8 (display-referred), depth16, fullscreen
triangle, 9-tap FXAA-вариант, exposure/vignette и final dither. Нейтральный проход
сравнивается с direct path, FXAA — с CPU bilinear/luminance oracle. Scene encode
sRGB не повторяется; прозрачность/HDR и linear-light upsampling не реализованы.
Scale 0.7–1.0 теперь действительно меняет target, но GPU timers/автоматический
выбор масштаба не реализованы. WebGL1/GLES2 остаются T0, без post resources.

Следующий приоритет: воспроизводимый benchmark/warmup и раздельные CPU/GPU
метрики с disjoint/lifecycle handling, затем подключение quality hysteresis на
основании измерений. Оконный desktop host и физические mobile/ARM прогоны остаются
отдельной незакрытой задачей, software pbuffer не считается их заменой.
См. validation-post.md; полного T1 (включая blob shadows и атмосферу) пока нет.


## Уточнение после шестого среза

CPU submission и GPU elapsed теперь разделены: optional timer extensions,
4-query FIFO, availability/disjoint/lifecycle checks, frame-ID warmup и rolling
median/p95. Демо и repeatable smoke workloads подключены. Исправлена ошибка JS
percentiles после ring wraparound. Подробности — validation-timing.md.

Автоскейлер всё ещё выключен: сначала нужны freshness/minimum-sample policy,
контролируемое сравнение workloads и аппаратные прогоны. Software GPU даёт
query saturation и нерегулярную выборку; submit time нельзя выдавать за GPU time,
а независимые CPU/GPU median нельзя складывать в frame time. Window/mobile/ARM
runtime и полный E1–E7 benchmark остаются открытыми задачами.


## Уточнение после седьмого среза

Добавлен отдельный GPU-only AutoScale: matching submission timestamps, ограничение
возраста/плотности выборки, непересекающиеся окна median/p95, down/up hysteresis,
warmup/cooldown. Демо реально меняет FBO, сбрасывая старую эпоху измерений; управление
opt-in. Fixed-scale benchmark остаётся без адаптации. Synthetic timing integration
oracle отделён от реального hardware performance testing. Детали — validation-autoscale.md.

Дальше: аппаратная калибровка и более широкий benchmark, оконный/mobile host,
затем оставшиеся visual T1 features. При недоступном/устаревшем GPU timing scale
замораживается; искусственного CPU fallback и обещания целевого FPS нет.


## Уточнение после восьмого среза

Добавлены отдельный sky shader, vertex-distance fog и bounded analytic blob
shadows на horizontal receiver planes. Работают до sRGB encode и независимо
от post target, включая T0. Это дешёвые аппроксимации, не physical atmosphere или
shadow mapping. Renderer сохраняет прежний layout; настройки опциональны.
Sky adds one draw; fog/blob uniforms не требуют geometry/texture uploads.
См. validation-environment.md: медиумная точность и vertex fog на больших triangles
имеют ограничения. Полный T1/T2, mobile/window hosts и аппаратная калибровка
по-прежнему не объявляются завершёнными.


## Уточнение после девятого среза

Добавлен CPU conservative AABB/frustum culling и stable selected-instance upload.
Ни порядок draw, ни полный CPU snapshot не меняются; caster culling — отдельная
задача. Flat O(N), не spatial hierarchy. Demo checkbox default-off; shared GPU
fixture сравнивает всю картинку culled/unculled. См. validation-culling.md.
Также восстановлены transient toolchains и добавлен воспроизводимый bootstrap;
экспериментальный Nim cproc storage workaround расширен на object constants.


## Уточнение после десятого среза

Добавлены matched-snapshot interpolation (shortest-arc yaw, linear tint/position/
scale) и bounded fixed-step/drop-time helper. Demo отделяет 20 Hz pose updates от
RAF и подаёт rendered poses в culling, instance stream и blob shadows. Предыдущий
и текущий snapshots должны соответствовать по entity identity/order; lifetime,
network jitter/authoritative synchronization пока отсутствуют. См. validation-motion.md.
Новые helpers backend-neutral, не имеют clock IO или GL calls. Все renderer
resource ownership/window/mobile/hardware acceptance ограничения сохраняются.

## Уточнение после одиннадцатого среза

Persistent float32 instance shadow позволяет optional skip одинаковых uploads;
эффекты используют canonical cache и dirty uniform groups. Pending state после
backend exception требует retry, новые renderer создают собственный cache.
Forced APIs сохранены; ownership и host context-loss lifecycle не изменились.
Это O(N) comparison, без spatial index/partial-range uploads. Подробности и
измеренные GL calls: validation-dirty.md.

## Уточнение после двенадцатого среза

Optional `softgfx/identity` выравнивает previous history по current IDs до вызова
motion interpolation. Spawn/reset snap, despawn immediate; host владеет lifetime
и запрещает случайное переиспользование ID. Scratch allocation вынесена из
snapshot update, GPU ownership не меняется. См. validation-identity.md.

## Уточнение после тринадцатого среза

Optional uniform grid кэширует transformed bounds и отсеивает cell unions перед
individual plane tests. Region лишь задаёт buckets, не ограничивает допустимые
позиции. Host явно rebuild-ит при смене snapshot. Flat API остаётся oracle и
простым путём для малых сцен; query сохраняет стабильный порядок за O(N) scan.
См. validation-grid.md; аппаратные performance claims не добавлены.

## Уточнение после четырнадцатого среза

Renderer/Pipeline переведены на shared reference identity: aliases разделяют
cache/state/lifetime. Dispose/abandon инвалидируют их вместе; explicit cleanup
остаётся обязанностью host, не GC. Timer pool и context identity/interleaving
ограничения пока отдельные задачи. См. validation-lifetime.md.

## Уточнение после пятнадцатого среза

GpuTimer разделяет identity между aliases; rollback cleanup не повторяет deletion
после исключения. Driver callback failures закрывают timer и подавляют partial
samples. Global context/query arbiter не добавлен: отдельные драйверы всё ещё
нельзя interleave. См. validation-timer-lifetime.md.

## Уточнение после шестнадцатого среза

Explicit ContextScopes добавляет независимые frame/query channels с owner identity.
Это opt-in host-managed guard, не глобальное обнаружение GL context или защита raw
backend calls. Demo подключён и заменяет guard при restore. Подробнее:
validation-scopes.md.

## Уточнение после семнадцатого среза

Linux SDL2 host отделён от renderer: window/event/drawable/swap lifecycle, bounded
simulation и teardown до уничтожения context. CI получает Xvfb/Mesa window path
для GCC/LLVM/QBE GLES2/3; физический GPU/монитор/mobile не подменяются виртуальным
X server. См. validation-window.md.

## Уточнение после восемнадцатого среза

SDL demo использует focus-aware pause/resume с сохранением rendered history.
Openbox/XTest integration проверяет native input/window-manager путь в дополнение
к SDL synthetic-quit smoke. Это virtual software desktop, не hardware acceptance.
См. validation-desktop-input.md.

## Уточнение после девятнадцатого среза

Native demo отделяет retained CPU state от пересоздаваемых GPU resources.
R инициирует planned window/context recreation с новым scope guard и повторным
resolver lookup. Hardware-loss detection/abandon path не добавлен. См.
validation-native-recreation.md.

## Пакет 20: native health/recovery/reporting

Добавлены latched reset monitor, advertised GLES reset-status adapter, optional
strict robust context, bounded abandon/rebuild path и native timing/capability JSON.
Normal, robust, injected-loss и reset-storm window scenarios включены в matrix.
Аппаратная надёжность reset path не выводится из software injection. См.
validation-native-recovery.md.

## Пакет 21: workloads и sparse ordering

Uniform grid использует adaptive in-place prefix sort / dense mark scan вместо
безусловного O(N) clear+scan. API stable prefix прежний; добавлены ordering counters.
CPU/GPU workload oracles и strict JSON collectors дают evidence для следующих
hardware экспериментов, но не подменяют их. См. validation-workloads.md.
