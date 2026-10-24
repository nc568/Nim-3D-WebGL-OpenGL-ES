# Пакет 25: direct float32 shadow и CPU submission observations

## WebGL upload path

Renderer теперь хранит packed shadow в Float32Array. WebGL bufferSubData получает
view этого же backing buffer, а не копию диапазона во второй staging buffer.
Для WebGL1/ANGLE и WebGL2 сохранён один call на bounding span. Байты, передаваемые
в GL, не изменились; убрана дополнительная JS-side copy и staging allocation.

Ранее renderer shadow был Float64Array (72 bytes/instance), staging — Float32Array
(36). Теперь один backing 36 bytes/instance: для 8192 instances 884736 → 294912 bytes
packed CPU storage, без учёта source snapshots, объектов, view wrappers и driver
memory. Fallback также получает float32 shadow, но никогда не делает instance
buffer uploads. Native shadow уже float32, поэтому эта экономия к нему не относится.

Nim 2.2.4 JS присваивание seq в result/field, даже с move, может вставить nimCopy
и вернуть Float64Array. Два узких emit assignment сохраняют representation;
runtime tests проверяют тип и backing identity. `newInstanceData` — fixed-capacity
storage: обычное копирование/resize seq может потерять representation. Прямые
backend callers с обычным seq по-прежнему поддержаны через compatibility staging.

View cache keyed по backing identity + first/count; смена массива при одинаковом
range не может повторно отправить старый view. Dispose/abandon снимают ссылки на
shadow/view/storage. При destroy callback exception CPU storage освобождается в
finally; это не добавляет rollback остальных GL resources.

Не zero-copy до GPU: driver transfer остаётся. Subarray view при смене range всё
ещё создаётся. CPU validation/packing O(N) не изменены. Forced APIs, float32 dirty
comparison, partial upload и full retry после exception сохранены.

## Evidence

CPU type/packing tests; WebGL wrappers проверяют настоящий ArrayBuffer identity,
переходы direct→direct→ordinary→direct, pixel parity, forced/fallback и retries.
GPU fixtures выполняются в Chromium/Firefox/WebKit. Native GCC/LLVM/QBE остаются
в matrix. Release CPU benchmark также использует новый production storage.

Release report дополнен 8 demo submission cases (WebGL1/2 × auto/fallback ×
static/moving): 320×240, 20 warmup, 41 samples, RAF wait вне timed interval.
Измеряется synchronous host update+GL command submission, включая DOM HUD writes;
это НЕ GPU elapsed/FPS, stall-free гарантия или полная игровая сцена. Moving включает
simulation/interpolation/packing; static — render только. WebGL1 T0 и WebGL2 T1
не являются равными quality workloads. Таймеры GPU не включаются автоматически.

Raw samples, median/p95 и реальные successful upload/update counters сохраняются
в release-ENGINE.json; CI не требует ускорения на шумных/shared runners.
