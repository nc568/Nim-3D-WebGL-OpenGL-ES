# Срез 13: reusable uniform-grid broad phase

API экспортируется через `softgfx/culling`:

```nim
var grid = initSpatialGrid(region, [16, 1, 16], capacity)
grid.rebuild(localBounds, poses) # после изменения poses/order/count/local bounds
var stats: GridQueryStats
let count = frustum(matrix).collectVisible(grid, indices, stats)
renderer.updateVisibleInstancesIfChanged(poses, indices, count)
```

Индекс хранит conservative world AABBs и linked lists по ячейкам. Центр AABB
выбирает ячейку; выходящие за region объекты попадают в крайние ячейки. Bounds
ячейки — **union объектов**, не её геометрический размер: большие объекты и
outliers не теряются. Candidate cells проходят прежний conservative plane test,
затем точно тот же тест применяется к individual AABBs. Результат — возрастающий
prefix исходных индексов, совпадающий с flat collectVisible.

## Стоимость

- Storage выделяется один раз: capacity boxes/links/marks и cells bounds/heads.
  Capacity 1..65535, divisions каждой оси 1..32 (до 32768 ячеек).
- Rebuild O(N + cells), с полной validation до изменения сохранённого индекса.
  Rebuild требуется после любого изменения poses, порядка, count или local bounds.
  Query **не проверяет** соответствие внешнего snapshot: это обязанность host.
- Query O(N + cells + candidate plane tests), не sublinear: marks очищаются,
  затем сканируются для стабильного порядка. Экономия — cached transforms и
  сокращение AABB/plane tests. Per-query allocation/resize отсутствуют в исходнике;
  whole-frame zero-allocation и hardware FPS не заявляются.
- Выгоднее всего для статических/редко меняющихся batches с небольшим visible
  subset. Движущаяся каждый кадр сцена платит за rebuild; один огромный объект
  или плохой region ухудшают pruning. Нет auto-tuning и incremental refit.
- Flat API сохранён. Демо из трёх машин не переведено на grid: такая сцена не
  оправдывает дополнительное хранение и rebuild. Blob casters не culled этим API.
- Invalid rebuild сохраняет старый cache; invalid query не меняет output/stats.
  Новая grid требует rebuild (в том числе пустого) перед первым query.

## Regression fixtures

`test_grid`: 1024 instances, sparse view с проверкой уменьшения individual AABB
checks минимум в 4 раза; 40 snapshots/cameras с yaw/scale, outliers и большими
объектами — exact prefix parity с полным перебором. Также atomic validation,
empty rebuild, uninitialized query, capacity/division limits и clip boundary.
`culling_fixture`: GPU selected uploads берутся из grid, проверяются против flat
indices и картинки без culling на WebGL/GLES instanced/fallback путях.

Счётчики `GridQueryStats`: occupiedCells, candidateCells, instanceTests,
visibleInstances; относятся к одному успешному query, не cumulative.

Реальный native window/mobile/ARM execution и hardware FPS остаются отдельными
пунктами приёмки. Grid не заменяет проверки на физических устройствах.

Обновление пакета 21: описание обязательного O(N) clear/scan выше относится к
первой реализации. Sparse queries теперь используют in-place prefix sorting;
dense queries сохраняют scan. Подробности и новые счётчики — validation-workloads.md.
