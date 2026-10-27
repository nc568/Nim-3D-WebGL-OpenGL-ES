# Пакет 35: active-cell traversal

SpatialGrid хранит заранее выделенный список занятых ячеек. Query обходит только
этот список; rebuild очищает heads только предыдущих занятых ячеек. Проверка входа
по-прежнему выполняется **до** изменения cache. Empty rebuild сбрасывает active list.

Список содержит каждую непустую ячейку один раз, его capacity = min(cellCount,
instanceCapacity). Новых per-query/per-rebuild seq allocations нет. Цена — ещё один
bounded int buffer; остальные cells/heads/boxes не удалены. Bounds остаются union
объектов, а не геометрическими границами ячеек: outliers/large objects безопасны.

Traversal теперь идёт по first-encounter order, но public visible prefix остаётся
строго возрастающим source-order: прежние sparse heapsort/dense scan сохранены.
Количество sort comparisons может измениться; membership и порядок результата — нет.

`GridQueryStats.cellVisits` считает реально посещённые query ячейки. Его ожидаемое
значение совпадает с occupiedCells. CPU workload и release reports сохраняют оба
поля; browser/native validators проверяют равенство и верхнюю границу active count.

Regression: 32768-slot grid, 8 разнесённых объектов -> 8 cell visits (не 32768),
64 цикла смены ячеек с переходами 8 -> 1 -> 0, invalid late input/atomicity,
несколько объектов в одной ячейке, полная active-list capacity, flat-oracle parity.
Старые randomized poses/cameras/outliers, prefix-tail, sparse/dense ordering tests
остаются. Test_grid выполняется на Node JS/GCC/LLVM/cproc-QBE; browser/GLES workload
pixel oracles и расширенный soak также обязательны.

Это снижение числа обходов, не обещание пропорционального FPS/CPU ускорения.
Transform, cell unions, plane tests и stable ordering всё ещё имеют стоимость.
Existing release benchmark измеряет rebuild/gridQuery/flatQuery без flaky time
threshold; физические устройства и реальные игровые counts пока не приняты.
