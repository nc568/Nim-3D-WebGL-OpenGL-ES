# Оценка готовности и первый integration release

Оценка после пакетов 1–27, с учётом текущего приоритета пользователя. Это субъективная
инженерная оценка: не code coverage, не процент строк и не обещание календарного срока.
Пакет 28 закрывает ещё одну локальную оптимизацию; сам по себе не меняет оценку.

## Два разных объёма

- **WebGL-first mini-engine + GLES parity, первый integration release:** примерно
  **65–75%**, confidence medium-low до проверки реальной игровой интеграции.
- **Изначальный широкий план**, включая мобильные native hosts, physical E1–E7,
  полный T2, Vulkan/Metal: примерно **40–50%**. Эти направления не являются ближайшей целью.

Нельзя объявлять production-ready по числу зелёных CI jobs. Chromium/Firefox/WebKit
проверены, но shipping Safari/iOS, реальные gameplay workloads и device acceptance
ещё не закрыты. Apple GPU в renderer string — evidence, не полный hardware acceptance.

## Критерии первого integration release

| Блок | Сейчас | Что требуется для закрытия |
|---|---|---|
| WebGL1/2 и GLES2/3 core | Реализован, есть CI | Сохранить parity на game presets, закрепить supported API |
| Ownership/loss/recovery | Есть lifecycle и injected failures | Длительный soak, проверка host-интеграции без накопления ресурсов |
| Game workload | Синтетические batches + demo из 3 машин | Согласованные типовые/пиковые counts, territory deltas, movement/culling/material mixes |
| Оптимизация | Dirty/range/direct-shadow/grid/camera | Профилировать согласованные сцены и закрыть подтверждённые hotspots |
| Debug/evidence | Ring logs, budgets, CPU/GPU reports | Удобный inspector/воспроизводимый seed+settings capture, проверка экспортов |
| Контракт качества | T0 и T1 subset | Зафиксировать обязательные эффекты, draw/memory/CPU budgets; T2 отдельно |
| Интеграция игры | Пока demo и отдельный UI overlay | Подключение реального host/snapshot flow, проверка lifecycle и регрессий |
| Release hygiene | Пинованные toolchains и CI | API/ownership docs, reproducible build/run, checklist без известных blocker bugs |

## План: ориентировочно 6–10 пакетов, не даты

1. **1–2 пакета:** game-like presets и stress/soak, декларация peak counts/budgets.
2. **1–2:** дальнейшие measured optimizations; не глобальный GL state cache без ownership contract.
3. **1–2:** debug inspector/capture и анализ аномалий кадров.
4. **1–2:** интеграционный host/example, API stabilization и документация.
5. **1–2:** финальная regression/soak матрица и устранение найденных blocker bugs.

Пункты могут объединяться. Интеграция может выявить переделки и увеличить оценку.
Чтобы уточнить срок, нужны реальные snapshot shapes, peak counts, resolutions и
обязательные visual presets игры. До этого используем явно помеченные provisional
fixtures, не выдаём их за фактическую нагрузку игры.

Physical devices — отдельный этап после integration release; его длительность
зависит от доступных устройств/runner'ов и результатов. Shadow maps/bloom/FSR/MSAA,
Android/iOS native host, Vulkan/Metal не включены в эти 6–10 пакетов, если отдельно
не пересмотрен scope. UI toolkit и network synchronization остаются вне graphics.
