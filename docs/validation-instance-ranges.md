# Пакет 22: частичные instance uploads

`updateInstancesIfChanged` / `updateVisibleInstancesIfChanged` теперь передают
один непрерывный диапазон изменённых packed records. Forced APIs остаются full
uploads. Float32 rounding, валидация всего snapshot до первой записи, stable
packed order и public boolean dirty-pack APIs сохранены.

## Политика

- Ничего не изменилось и count прежний: без GL submission.
- Прежний count, есть изменения: `[firstChanged, lastChanged+1)`; gaps включены.
  Это максимум один bufferSubData, без списка dirty chunks и без draw fragmentation.
- Новый count, первая непустая загрузка или pending после исключения: полный prefix.
- Zero count: обновление CPU/count без GL call; fallback также без GPU instance buffer.
- Dirty range — packed slot, НЕ entity ID / source index.

Renderer сохраняет range object между вызовами. CPU validation и comparison всё
ещё O(N); не заявляется пропуск transform/packing на неизменённых исходных данных.
Native использует offset pointer в существующем shadow; WebGL копирует только span
в preallocated Float32Array. WebGL view кешируется по first/count; смена диапазона
создаёт subarray-view, не копию backing buffer. Это НЕ zero-allocation guarantee.
Для двух далёких изменений span может оказаться полным buffer: намеренный простой
компромисс bandwidth/число calls, а не аппаратно оптимальный threshold.

## Исключения

До GL call выставляется pending. Если callback бросил (даже ПОСЛЕ фактической
передачи), следующая валидная submission полностью синхронизирует текущий snapshot.
Нельзя полагаться на CPU diff: shadow уже изменён. Invalid input не сбрасывает
pending. GL ошибки, которые не бросают исключение, этим механизмом не обнаруживаются;
context health/loss — отдельный host contract. Счётчики учитывают успешно
завершившиеся вызовы, не неизвестный объём передачи при исключении.

## Evidence

- CPU C/JS/LLVM/QBE: середина/края диапазона, gaps, packed selection, empty,
  неизменённые snapshots и атомарная валидация.
- WebGL1/2 и GLES2/3: 256 instances, изменения 119, затем 120, затем краёв.
  Core/ANGLE: 36 + 36 + 9216 = 9288 bytes вместо 27648 для трёх full uploads.
- Compact selection [119,120,121]: изменение source 120 передаётся по offset 36,
  length 36. Сравнение пикселей с forced path; fallback bytes = 0.
- JS wrapper проверяет настоящие bufferSubData offset/byteLength; injection до и
  после GL call проверяет full retry и pixel parity. Native injection отсутствует;
  там проверяются реальные pixels/counters через общий fixture.
- Старые full/count-transition/recreation/dirty tests сохранены. Workload JSON
  schemaVersion=2 содержит rangeUploadBytes, compactUploadBytes, 13 pixel comparisons.

Это сокращение CPU copy / GPU upload bytes, не доказательство ускорения FPS.
