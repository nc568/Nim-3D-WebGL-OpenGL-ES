# Пакет 27: per-program camera uniform cache

WebGL1/2 и GLES2/3 теперь отправляют uViewProjection только при изменении canonical
float32 значений. Каждый renderer/program имеет отдельный shared-reference binding:
interleaving разных renderers безопасен для кеша, renderer aliases видят один кеш.
Shader без camera uniform (например sky) не делает этот uniform call вообще.
Остальные draw/state calls и сами draws не пропускаются.

На кадр остаются 16 сравнений; новая матрица не аллоцируется внутри submitMatrix.
WebGL переиспользует Float32Array. Native хранит Mat4 внутри binding. Это уменьшение
GL calls, не доказательство FPS speedup. Raw GL, который меняет uniform того же
program, обязан вызвать `renderer.invalidateCamera()` перед следующим render.
Смена камеры/viewport вычисляет и сравнивает новую матрицу обычным путём.

Binding становится valid только ПОСЛЕ успешного uniform callback. Если он бросил
до или после GL call, следующая попытка отправляет матрицу заново, даже при том же
shadow. GL errors без исключений/необъявленная context loss не обнаруживаются этим
кешем. Context restore по host contract пересоздаёт renderer/program/binding;
новые объекты начинают с invalid cache. Это не глобальный GL state tracker.

`renderer.cameraStats` даёт cumulative saturating uploads/skips; uploads — успешно
завершившиеся uniform callbacks, не число нарисованных кадров. Invalidation не
сбрасывает статистику. Disposed renderer отвергает stats/invalidation.
Browser debug profile экспортирует cameraUploads/cameraSkips для arena+cars.

## Проверки

Общий GPU fixture: static/instanced/fallback, 100 неизменённых renders → 1 camera
upload +100 skips; реальные WebGL uniform calls проверяются wrapper'ом. Изменение
камеры сравнивается с новым renderer по пикселям, interleaving/alias invalidation,
invalid input до GL и retry после callback failure. Native выполняет pixels/counters;
failure injection — JS only. Hot-path codegen guard проверяет submitMatrix.

Release demo submission cases при неподвижной камере (включая движущиеся машины)
требуют 0 camera uploads и 82 skips за 41 sampled frame, по двум scene renderers.
Pixel/GPU oracles, camera-input monkey и context lifecycle suites сохранены.
