# Пакет 28: final/post uniform cache

Post pass по-прежнему рисуется каждый кадр. Кешируются только пять dynamic uniform
calls: inverse target size, FXAA, dither, exposure, vignette. Cache отдельный для
каждого post program и разделяется aliases/copies PostPass. Изменение одного поля
вызывает один uniform call; scale влияет через реальный размер target, enabled
сам по себе не является shader uniform. Sampler binding uScene задаётся при создании
program и не входит в эти счётчики/инвалидизацию.

CPU settings сравниваются в canonical float32 representation. При exception в
uniform callback кеш invalid: следующая попытка синхронизирует все пять групп.
Счётчик calls отражает успешно завершившиеся callbacks (partial progress включён),
skips — группы, пропущенные в успешно завершённом uniform batch. Raw GL errors без
исключения этим механизмом не обнаруживаются.

`pipeline.postUniformStats` и `pipeline.invalidatePostUniforms()` доступны host'у;
внешний GL-код, меняющий эти uniforms, обязан инвалидировать кеш. Это не разрешение
relink чужого program или interleave framebuffer scopes. WebGL1/GLES2 direct path
не создаёт post и возвращает нулевые stats. Context recreation создаёт новый кеш.

Evidence: CPU masks/canonical equality/saturation; общий WebGL2/GLES3 pixel fixture:
100 повторов → 0 новых calls / 500 skips после initial 5 uploads. Проверены пять
изменений по одному, invalidation/forced parity, alias, disable/enable и JS callback
failure до/после GL call. Existing post/FXAA/depth/resize/lifecycle tests сохранены.

Release demo должен давать 205 post skips / 0 updates за 41 sample на WebGL2,
и 0/0 на WebGL1. Debug report экспортирует postUniformCalls/postUniformSkips.
Это сокращение API calls, не доказательство прироста hardware FPS.
