# Срез 19: planned native window/context recreation

Native demo принимает R keydown (autorepeat игнорируется): закрывает старое SDL
окно/контекст и создаёт новое, сохраняя CPU-состояние сцены. Это planned lifecycle
transition при исправном current context, **не** обработка аппаратного GPU reset.

Сохраняются meshes, owner map с изменениями, instance poses, отображаемая фаза,
camera angle/distance и post settings. Logical window size сохраняется отдельно
от drawable size (HiDPI). GPU resources удаляются до SDL context teardown;
старый ContextScopes инвалидируется, новые renderer/pipeline/guard создаются заново.
GL entry points повторно разрешаются через SDL для нового current context.

History привязывается к последнему rendered pose. Clock remainder сбрасывается,
время создания окна не включается в simulation elapsed. При ошибке создания новое
приложение не продолжает работать со старыми handles: исключение и cleanup.
Это не transactional rollback к предыдущему окну. Положение окна/focus/window-manager
state не сохраняются, multi-monitor DPI может изменить drawable dimensions.

## Проверки

В --smoke автоматические recreation на frames 20/40; каждый запуск самого приложения
по-прежнему включает два полных sessions. Перед recreation меняются owner cells и
camera; используются non-default post scale/exposure/vignette. Retained poses и
полный RGBA framebuffer сравниваются точно до/после пересоздания (readback только
в test modes). Старые Renderer/Pipeline/SDL host/ContextScopes обязаны отвергать
обращения после transition. При изменении DPI между окнами pixel oracle отклоняет
различные размеры, а не сравнивает несовместимые изображения.

Desktop Openbox/XTest harness нажимает R дважды после resize. Проверяет generation
telemetry и pixel-parity markers, находит новый X window ID, возвращает focus и
проверяет продолжение rendering перед WM close. Это выполняется для GCC/LLVM/QBE
и GLES2/GLES3 вместе со старой browser/native matrix.

Пределы: виртуальный X server + Mesa, не physical GPU, mobile, ARM execution,
Wayland survey или recovery после EGL_CONTEXT_LOST. Для реального context loss
нужны platform loss detection и abandon вместо GL delete. В этом срезе их нет.
Пользовательские GPU assets вне demo автоматически не сериализуются.
