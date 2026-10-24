# Срез 12: identity-aware history alignment

`softgfx/identity` — CPU helper, без GL/clock/physics/network ownership.

```nim
var scratch = initIdentityScratch(capacity)
# aligned.len == current.len; память выделяет host при изменении состава.
let changes = alignHistory(previousIds, previous, currentIds, current,
                           resetFlags, aligned, scratch)
interpolateInstances(aligned, current, alpha, rendered)
```

- ID — nonnegative int32 (0 допустим); IDs уникальны внутри каждого snapshot.
  Порядок произвольный, sorting не требуется. Output следует current order.
- Сохранившийся ID получает previous pose; новый — current pose (без появления
  из случайного места). Исчезнувший ID немедленно исключается, без fade-out.
- `resetFlags` пустой либо current.len: teleport/reset существующего ID копирует
  current pose. Reset новых объектов уже подразумевается. `reset` в результате
  считает только существующие IDs; `matched` включает их.
- Host отвечает за lifetimes: не переиспользовать ID для другой сущности между
  соседними snapshots либо явно выставлять reset. Это не generation allocator.
- Все IDs, lengths и poses проверяются до изменения output. При ошибке output
  остаётся неизменным; scratch можно использовать повторно. Staging разрешает
  alias output с previous или current даже при произвольной перестановке.
- Вызов нужен **на simulation snapshot change**, не на каждом RAF. Между ticks
  используйте обычный interpolateInstances. Demo с тремя постоянными машинами
  оставлен на более простом matched-snapshot пути: лишний remap ему не нужен.

## Стоимость и границы

Scratch создаётся один раз: две hash slot tables, каждая power-of-two >=4*capacity,
и capacity staged poses. Вызов не resize-ит seq и не создаёт новые Pose objects.
Скалярное копирование не вызывает Nim JS nimCopy/typed-array allocations;
codegen guard проверяет align/copy/index/lookup helpers. Это не доказательство
zero-allocation всего приложения.

Expected O(capacity + previous.len + current.len), загрузка таблиц <=25%.
Очистка таблиц O(capacity), а не только active count. Linear probing с простым
modulo: специально подобранные colliding IDs дают O(N²), поэтому это helper для
host-controlled IDs, не защита от недоверенных сетевых идентификаторов. Capacity
1..65535, дальнейший рост storage явно управляется host. Spatial index не добавлен.

## Regression coverage

CPU fixture: reorder, spawn/despawn, reset, midpoint, alias permutation, duplicate
и отрицательные IDs, invalid late pose, output atomicity, повтор после ошибки,
пустые snapshots, collision chains, максимальный int32. Включён в GCC/LLVM/QBE и
Node JS suites. GPU motion fixture: identity transition + interpolation против
explicit aligned-history oracle, alpha 0/.5/1, reset, instanced/fallback paths.
Старые WebGL/GLES/browser/UI suites остаются обязательными.

Hardware FPS, native window, mobile и ARM execution этим CPU helper не закрываются.
