# Срез 11: пропуск неизменившихся GPU uploads

## Контракт

- `updateInstancesIfChanged` и `updateVisibleInstancesIfChanged` возвращают
  `true`, если обновлено представление batch, и `false`, если запрос пропущен.
  Порядок selected indices строго возрастающий. Проверяется весь snapshot до
  записи; count/selection transitions, включая пустой batch, сохраняются.
- Сравнение packed position/cos(yaw)/sin(yaw)/scale/tint идёт в точности float32,
  без epsilon. Nim JS scalar/seq может хранить double, поэтому обе packing ветки
  явно используют `Math.fround`. Проверяется также чередование forced/conditional.
- Старые `updateInstances`/`updateVisibleInstances` остаются forced. При изменении
  отправляется весь активный prefix, **не** отдельные dirty ranges. Сравнение и
  валидация по-прежнему O(N), включая trig; для постоянно движущегося batch
  conditional-путь не обязан быть быстрее. Нет per-frame scratch buffer.
- `updateEffects` валидирует snapshot и меняет только dirty группы: fog parameters,
  eye, color, либо rect+plane конкретного blob. Выключенные поля canonical zero;
  игнорируемый NaN не попадает в cache/uniforms. `force=true` обновляет все 11
  uniform4f slots, включая неактивные. Изменения сравниваются по полям settings;
  это не approximate visual-equivalence алгоритм.
- Cache принадлежит одному renderer/program. Нельзя менять его buffers/uniforms
  извне и ожидать автоматического обнаружения; используйте forced API для resync.
  После context loss renderer надо пересоздавать, как делает demo. Копирование
  renderer не становится безопасным ownership-механизмом.
- После исключения backend upload следующий запрос повторяет instance submission
  или полностью синхронизирует effects. Это не обнаружение GL error/context loss
  через glGetError и не гарантия atomic GPU update. До успешного retry не рисовать.
- Новые cumulative/saturating stats: `instanceSkippedUpdates`, `effectUpdates`,
  `effectUniformCalls`, `effectSkippedUpdates`. Calls/updates учитывают успешно
  завершённые submissions; частичные вызовы до исключения в них не входят.
  В fallback нет instance buffer uploads, но CPU draw data обновляются.

## Проверено локально

- CPU: GCC, LLVM, cproc/QBE, Node pure JS; decimal rounding/sub-float32 change,
  повторный packing, invalid-snapshot atomicity, canonical effects, dirty groups.
- Shared GPU fixture: WebGL2 core, WebGL1 ANGLE, GLES2/3, forced fallback; 200
  одинаковых instance requests → 0 дополнительных submissions; 100 одинаковых
  effect requests → 0 дополнительных uniforms. Initial fog + один blob: 5 calls;
  изменение только eye: 1; одного blob: 2; force resync: 11.
- Browser wrappers измеряют реальные `bufferSubData`/`uniform4f`, а не только
  внутренние stats. Injected buffer failure → повторная отправка, injected failure
  после первого uniform → полная синхронизация 11 slots, пиксели как forced.
- Pixel equality: cached vs forced, count/selection/empty transitions, выключение
  effects и пересоздание renderer. Счётчики проверены на saturation.
- Пять browser/UI hosts: seeded resize monkey, camera, owner edits, toggles,
  fixed-step interpolation, context loss/restore, animation; PASS. Дополнительно
  timing/autoscale regression suites PASS. Generated-JS guards проверяют отсутствие
  прямых typed-array allocations/nimCopy в новых packing/diff/cache helpers.
- Native GLES debug, LLVM/QBE release, ARM64 cross-link, compiler patch reverse
  check: PASS. Compiler patch не менялся. Новые fixtures подключены к CI matrix.

Доказано сокращение вызовов и сохранение картинки, **не** прирост hardware FPS.
ANGLE/SwiftShader/pbuffer не заменяют видимое native window, мобильное устройство,
физический GPU или ARM execution. Full-frame zero-allocation также не заявляется.

Следующие независимые задачи: entity ID/remap/spawn/despawn, spatial index,
resource ownership, native-window/mobile hosts, hardware E1–E7, расширение T1/T2
и backend implementations Vulkan/Metal.
