# Пакет 30: WebGL debug-inspector и diagnostic captures

В `/?debug` (или `/?webgl1&debug`) появляется сворачиваемая панель **softgfx · Debug
inspector**. В обычном режиме панель, listeners и refresh timer не создаются.
Это отладочный host overlay, не UI toolkit игры и не замена отдельного fossil UI.

## Что доступно

- Manual refresh; optional 1 Hz refresh только у открытой панели в видимой вкладке.
  Автообновление выключено по умолчанию, не запускает GPU profiler.
- CPU/GPU median/p95 + sample counts, draws/visibility/target bytes, instance,
  camera и post uniform counters. Missing timing отображается как «нет данных».
- Фильтр событий, последние 40 matching записей из bounded ring 256; overwritten
  counter сообщает потерю старых событий. Это не бесконечная timeline.
- Настройка draw/instance-upload budgets, отображение episodes/breach frames и
  unknown delta coverage. Пороги в полях — примеры, сами не включаются.
- Последние **4** diagnostic captures: имя <=96 chars, время, snapshot ring,
  профиль/capabilities, whitelist demo controls и canvas dimensions.
- Выбор capture показывает frozen settings/profile; можно скачать конкретный
  capture JSON или текущий журнал. `stop` останавливает запись и refresh; уже
  сохранённые captures доступны для экспорта. Полный reset — перезагрузка страницы.

API:

```js
const id = softgfxDebug.capture('before quality change');
softgfxDebug.captures();          // bounded metadata list
softgfxDebug.getCapture(id);      // independent copy, null if evicted
softgfxDebug.downloadCapture(id);
softgfxInspector.refresh();
softgfxInspector.dispose();       // removes panel/listeners/timer, NOT recorder
```

## Ограничения

Capture **не является replay игры**: нет полного snapshot poses/entity IDs,
territory cells, camera orbit state, RNG state или trace входных событий. Есть
часть simulation counters и текущие demo controls. DOM settings и active renderer
profile могут расходиться, если host изменил DOM без события; сохранены оба.
Состояние читается синхронно, не останавливает симуляцию и не захватывает GPU image.

Панель использует textContent для сообщений/labels, не вставляет HTML из логов.
URL/stack и произвольные payload objects автоматически не сериализуются. Однако
markers/error messages могут содержать личные данные: просмотрите JSON перед
публикацией. Нет network/storage upload. Unmasked GPU identity не запрашивается.

Snapshot/capture/export аллоцируют bounded CPU objects; это explicit debug overhead,
не zero-allocation feature. Auto-refresh может повлиять на CPU profile, поэтому
измерения performance проводите с закрытой панелью/выключенным auto-refresh.
GL readback/finish/getError в inspector отсутствуют.

## Проверки

Node: bounded retention/eviction, immutable export copies, whitelist controls,
профиль не меняется задним числом, stop запрещает новые captures.
Chromium/Firefox/WebKit: opt-in, реальные кнопки/filter/budgets, текст вместо HTML,
сохранение/выбор/export JSON, eviction, auto timer cleanup, stop/dispose.
В тестах readPixels/finish/getError запрещены wrappers. JSON reports/screenshots:
`inspector-ENGINE.json`, `inspector-ENGINE-webgl*.png` в существующих artifacts.
Export download path заменён test hook; проверяется содержимое Blob, не UI
разрешений/сохранения файлов конкретного браузера.
