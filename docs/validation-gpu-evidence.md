# Пакет 26: GPU в CI — evidence, а не предположение

У GitHub Actions есть GPU-powered larger runners. Для macOS XLarge документация
указывает GPU hardware acceleration. Это не означает GPU-доступ у любого standard
runner, и не доказывает hardware path у любого запущенного браузера. Платные runner
labels не включены; permissions/billing для них в этом пакете не проверяются.

Источники GitHub documentation (проверены при реализации):
- https://github.com/github/docs/blob/main/data/reusables/actions/about-larger-runners.md
- https://github.com/github/docs/blob/main/data/reusables/actions/larger-runners-table.md

## Что мы собираем

`gpu-evidence-ENGINE.json` в browser artifacts:

- git revision, browser engine/version, host OS/architecture;
- macOS: allowlisted display/Metal metadata из system_profiler, когда доступно;
- Linux: наличие DRM nodes и доступный nvidia-smi name/driver, без UUID;
- WebGL version, masked renderer/vendor и optional WEBGL_debug_renderer_info;
- фактическая profiler support/sample status для WebGL1 и WebGL2.

Unmasked GPU queries включены только в CI evidence helper, НЕ в production debug
recorder. Экспорт CI может идентифицировать модель GPU; перед публикацией это нужно
учитывать. Обычный browser debug-export по-прежнему не запрашивает unmasked identity.

Linux Firefox явно получает LIBGL_ALWAYS_SOFTWARE=1; Chromium запускается с текущим
Sparticuz configuration, native driver — SwiftShader/Mesa. На macOS эта Linux-переменная
больше не задаётся. Ни hardware preference, ни presence устройства не заменяют
проверку реально выбранного browser renderer.

## Интерпретация

`software-indicated`: renderer string явно называет SwiftShader/llvmpipe/softpipe.
`hardware-indicated-unverified`: driver сообщает узнаваемый GPU, но acceleration и
physical-device performance acceptance НЕ доказаны.
`unknown`: информации недостаточно. Даже Apple renderer на virtual Mac не равен
проверке конечного устройства пользователя. `verifiedPhysicalGpu` всегда false.

Timer status отделён от renderer classification:

- unsupported — API недоступен, GPU times null;
- supported-no-valid-samples — поддержка есть, результатов нет (например disjoint);
- samples-observed — получены реальные query samples, в том числе у software driver.

Два static demo cases используют existing bounded/nonblocking profiler, 100 frames,
его 30-frame warmup, CPU/GPU sample counts и median/p95. `finish` и `readPixels`
запрещены wrappers; query results допускаются только после observed availability.
Тесты проверяют finite/nonnegative times и null vs missing samples, но не FPS и не
speed thresholds. Для Chromium прежние timer loss/restore tests сохранены отдельно.

Это следующий шаг к честным hardware reports; не новый GPU backend и не завершение
физических E1–E7. Если нужен отдельный hosted GPU runner, сначала согласуются
доступность/стоимость и software stack, затем проверяется реальный renderer.
