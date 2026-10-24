# Срез 14: shared resource handles

`Renderer` и `Pipeline` теперь `ref object`: assignment передаёт ссылку на **один**
ресурс и его state/cache/stats, а не создаёт независимую копию GL handles.
Это намеренное изменение semantics API; независимый ресурс создаётся только через
initRenderer/initPipeline. Обычные call sites с var продолжают работать.

- dispose через любую ссылку инвалидирует все aliases до GL deletion. Повторный
  dispose не вызывает driver повторно. Reassign одного alias новым init не
  восстанавливает старые ссылки. Нет автоматического GL destructor/finalizer.
- Nil/default handles: cleanup idempotent; операции render/update/frame и getters
  instanceMode/renderSize возвращают ValueError, а не nil dereference.
- Renderer.abandon добавлен к Pipeline.abandon: **только context loss**, без GL
  calls. Все aliases инвалидируются. Browser loss handler вызывает abandon для
  terrain/cars/sky/pipeline до пересоздания на восстановленном контексте.
- Pipeline aliases разделяют active-frame state, а не открывают отдельные scopes.
  cancelFrame сбрасывает active даже при исключении driver binding call.
- При исключении во время dispose handle остаётся invalid. Автоматического retry
  deletion нет: часть GL allocations может сохраниться до уничтожения контекста.
  Это предпочтительнее повторной операции через stale handles, но не гарантия
  cleanup при произвольной ошибке driver.

## Границы

Это runtime shared identity, **не** compile-time linear ownership. Explicit deepCopy,
unsafe casts, прямые backend calls и многопоточный доступ не поддерживаются.
Host обязан вызвать dispose при ещё current исходном контексте либо abandon при
его потере. Нельзя abandon живые ресурсы вместо dispose: это утечка до teardown.
Context identity/generation не проверяется автоматически. Несколько независимых
pipelines/foreign GL framebuffer state всё ещё нельзя interleave. GPU timer pool
в этом срезе не переведён на shared-handle API.

## Regression coverage

CPU tests: nil cleanup и rejection без GL context. Shared GPU fixtures: alias
renderer dispose, stale render/update rejection, новое создание не оживляет старый
alias; pipeline alias dispose/recreation. WebGL wrappers считают реальные delete
calls: второй dispose не удаляет снова. Existing browser context loss/restore,
post frame/resize, instancing/effects/culling/identity/pixel tests остаются в CI.
Матрица — pure JS/GCC/LLVM/cproc-QBE, WebGL/GLES и ARM64 cross-link (не execution).
