# Пакет 32: WebGL2 source-range uploads и расширенный soak

## Оптимизация

`uploadInstancesRange` использует пятиаргументный WebGL2 `bufferSubData`:
исходный Float32Array передаётся напрямую, destination offset задан в **байтах**,
source offset/length — в **элементах**. Смена dirty span больше не создаёт subarray
wrapper. Это снижение количества временных JS-объектов, не обещание FPS/CPU speedup.

WebGL1/ANGLE сохраняет трёхаргументный вызов и кеш диапазонного view. Fallback draws
не загружает instance buffer. Нулевой count остаётся ранним выходом: у WebGL2 API
length=0 означает остаток исходного массива, а не пустую загрузку.

Обычные Nim Float64Array seq прямых backend callers по-прежнему копируются в
совместимое Float32 storage; renderer-owned Float32Array не копируется.
GLES2/3 использует прежний pointer-offset путь, без изменения ABI/public API.

## Регрессии

`tests/upload_range_fixture.nim` выполняется на реальном WebGL1/2 в Chromium,
Firefox и Playwright WebKit:

- 128 меняющихся диапазонов, повтор каждого диапазона, полный начальный upload;
- проверка overload, source identity, byte/element units, payload;
- WebGL2 getBufferSubData сравнивает **весь** GPU buffer с oracle, включая
  неизменённые участки, на каждом шаге;
- смена исходного storage при том же диапазоне, Float64 compatibility и возврат
  к direct Float32, zero-count и fallback no-op;
- 261 upload calls на instanced path; ожидается 0 subarray calls на WebGL2,
  reuse неизменного view на WebGL1. Test-only перехватчики снимаются в finally.

Существующие dirty/workload pixel oracles продолжают сравнивать partial uploads с
полным обновлением и проверять retry-before/after-upload. Их instrumentation теперь
учитывает WebGL2 length argument, а не ошибочно считает весь backing byteLength.
Readback и interception есть только в тестах, не в production renderer.

## Расширенный автоматический checkpoint

Помимо базового soak (по умолчанию 96×2) каждый browser release suite запускает
отдельный фиксированный **240×3×12** checkpoint: **8640 scenario frames + 396 oracle
frames на engine**, **25920 scenario frames** на три engine. Отчёты и recipes:
`extended-ENGINE.json`, `extended-recipe-ENGINE.json`; базовые/replay не перезаписываются.

Это обычная push/PR CI на существующих runner'ах. Ручной workflow_dispatch остаётся
доступным пользователю с соответствующими Actions permissions; интеграции Arena
ранее вернулся HTTP403. Permissions/billing tier/timeouts не расширены. Дополнительный
checkpoint расходует больше обычного CI-времени. Реальное прохождение подтверждается
конкретным зелёным Actions run, не наличием этого документа.

Это не многочасовой soak, не JS heap/VRAM leak proof, не mobile/device acceptance.

## Bounded recipe I/O

Импорт читает один открытый file descriptor, проверяет fstat regular-file/size и
читает не более 16385 байт (лимит + sentinel). Даже рост файла после проверки размера
не приводит к неограниченному readFileSync. Short reads обрабатываются циклом; fd
закрывается при успехе/ошибке. POSIX nonblocking open позволяет отклонить FIFO без
ожидания writer. Тесты моделируют short reads и рост после fstat.
