# Этап 3: индексированные меши, территория и cproc — 24 октября 2026

## Сделано

- Optional uint16 index buffer и drawElements на всех четырёх API. Non-indexed
  fixtures по-прежнему поддерживаются. Static deduplication учитывает все поля,
  включая normal и UV/material mask, не сваривает жёсткие грани.
- Переносимый предел — 65535 вершин и индекс 0..65534. `0xffff` зарезервирован
  WebGL2 fixed-index primitive restart; не выдаём 65536-й индекс за переносимый.
- Owner ID texture: R8/RED (modern), LUMINANCE (legacy), UNSIGNED_BYTE.
  NEAREST + CLAMP_TO_EDGE, без mipmaps, включая NPOT. Палитра — 256×1 RGBA8,
  входные цвета линейные; alpha пока не используется.
- UV и material mask добавлены к Vertex (теперь 12 float32, 48 байт).
- Прямоугольные tight-row дельты, UNPACK_ALIGNMENT=1 при загрузке, затем 4.
  Валидация выполняется до GPU upload и изменения CPU shadow.
- Shared OwnerMap сохраняет изменения при потере контекста. Host пересоздаёт
  renderer из карты; изменения во время потери применяет только к CPU-карте.
- Демо: кнопка перекрашивает 3×5 клеток; вершины не обновляются.

Текущая арена: 864 вершины + 1296 uint16 индексов, 44064 байта VBO+IBO,
713 байт owner map (31×23) + 1024 байта palette, 1 draw/frame. Без индексов
та же геометрия заняла бы 62208 байт. Сравнение с прошлой сценой не является
чистым benchmark: также удалены 49 декоративных box-плиток.

## Реально выполнено

| Проверка | Результат |
|---|---|
| Core / math / geometry / resource tests: JS Node, GCC, LLVM | PASS |
| 1000 seeded CPU delta updates, полное сравнение с reference | PASS |
| Invalid rectangles/length/overflow, NaN vertices, index bounds | PASS |
| Index dedup preserves each input vertex, включая normals/material | PASS |
| Все 256 owner IDs + RGB palette с CPU lighting/sRGB oracle | PASS на WebGL1/2 и GLES2/3 |
| NPOT 17×17; delta 3×5; пиксели внутри и вне прямоугольника | PASS на четырёх API |
| GPU resource disposal/recreation from CPU shadow | PASS |
| Browser: delta — один texSubImage2D, 15 байт, ноль bufferData | PASS |
| Browser: 3 сценария × 200 resize, drag/zoom, context restore | PASS |
| Browser: edit during context loss survives restore | PASS |
| UIRelays overlay | PASS; upstream не изменялся |
| Native GLES tests через GCC, LLVM, **cproc/QBE** | PASS, EGL pbuffer |
| cproc/QBE native GLES с -d:release | PASS |
| Linux ARM64 GLES executable через LLVM | Сборка/линковка PASS, запуск НЕ проверен |

GPU oracle допускает ±4/255 на канал из-за дизеринга, mediump и округления.
Проверяется каждая из 289 клеток тестовой карты, а не только один центральный
пиксель. Browser context restore сравнивает framebuffer fingerprint.

Среда и software GPU — те же, что в предыдущем отчёте. Все executables собирались
заново; cproc начал проходить после нового патча и подбора совместимой ревизии QBE.
Подробности и ограничения: [cproc.md](cproc.md). Предыдущие отчёты с FAIL являются
историей, а не текущим состоянием.

## Ограничения

- Это не механика захвата в игровом ядре, а графический приёмник byte-deltas.
- OwnerMap — mutable shared CPU source. Не изменять его напрямую при активном
  renderer: использовать updateTerritory, иначе GPU-копия будет устаревшей.
  Исключение — период context loss, когда host не обращается к GPU.
- Один renderer обслуживает одну карту/палитру. Multi-device synchronization,
  palette deltas, объединение dirty rects и zero-copy JS uploads ещё не сделаны.
- JS создаёт Uint8Array на каждую дельту, копирует данные в CPU shadow.
  Render loop не пересоздаёт typed matrix buffer или geometry buffers.
- Resource handles ещё не move-only; renderer нельзя копировать. Нет полного
  восстановления чужого GL state, автоматического resource budget/OOM recovery.
- Native window, телефоны, физические GPU/ARM и T1 post-pass остаются следующими этапами.
