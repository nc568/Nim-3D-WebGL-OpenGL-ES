# Срез 15: shared timer queue и failure isolation

`GpuTimer` теперь ref object, аналогично Renderer/Pipeline. Assignment разделяет
одну очередь из четырёх queries, counters и active scope. Независимый timer требует
нового timerDriver и initGpuTimer. Нельзя повторно использовать один driver с
замыканиями, владеющими теми же query handles, для двух независимых timer objects.

- Через alias нельзя открыть второй query или poll во время active query.
  endSample через любую ссылку завершает scope один раз; dispose инвалидирует все
  aliases до cleanup. Новый init не оживляет старые ссылки.
- abandon при context loss не вызывает end/delete и инвалидирует все aliases.
  Nil cleanup/reset/end/poll безопасны; beginSample на nil/dead возвращает ValueError.
  Poll на dead/unsupported по-прежнему выдаёт пустой batch для CPU-only fallback.
- Rollback частичной allocation вынесен за create exception handler: исключение
  delete больше не запускает повторное удаление уже обработанных slots.
- Cleanup пытается удалить каждый известный slot максимум один раз, продолжая
  после delete failure. При наблюдаемом context loss дальнейших GL calls нет.
  Ошибка проверки context state также прекращает cleanup. Ошибка rollback/dispose
  сообщает ValueError; при create exception сохраняется исходная ошибка.
- Callback exception в begin/end/poll инвалидирует timer; poll обнуляет count,
  даже если часть samples уже прочитана. Повторного end/GL retry нет. Ошибки
  неправильного scope (nested begin/poll) не инвалидируют исправный timer.

## Ограничения

Если driver бросает после частично выполненного begin/end, состояние GL неизвестно.
Host должен восстановить/пересоздать контекст либо отдельно привести его в известное
состояние; просто создать новый timer и продолжить на том же контексте недостаточно.
Abandon в этом случае может оставить allocations до teardown. Это намеренный
fail-closed путь, а не обещание cleanup после произвольного driver failure.
Create callback обязан сам очищать slot, если выделил его, но не вернул success.

Между разными timerDriver/профайлерами на одном контексте нет глобального arbiter.
Shared aliases защищены, foreign query interleaving и multithread use не защищены.
Нет wait/finish/readPixels или увеличения query pool. Counters после invalidation
сохраняются для диагностики; supported становится false. Public stats не следует
менять извне. Это runtime identity, не compile-time linear ownership/GC cleanup.

## Проверки

CPU suites JS/GCC/LLVM/cproc-QBE: alias lifecycle, scope rejection, stale references,
nil operations, partial allocation + rollback-delete exception, create exception
preservation, full deletion failure, begin/end/read callback failure, partial batch
suppression. Старые FIFO/availability/disjoint/loss/rolling-statistics tests сохранены.
Browser lifecycle diagnostic хранит старую timer reference и проверяет отказ begin
во время реального WebGL context loss и после restore; synthetic timing/autoscale
и GLES smoke tests остаются в общей CI matrix.
