# Срез 17: Linux SDL2 GLES window host

`softgfx/hosts/sdl2` + `examples/native_window.nim` добавляют отдельный оконный host,
не заменяя pure-JS browser и EGL pbuffer fixtures. SDL2 загружается динамически;
Nim/C сборка не требует SDL headers, package manager или дополнительных Nim deps.
Текущая платформа — Linux; Windows/macOS/mobile ports пока не реализованы.

```sh
# Нужны SDL2 runtime, EGL/GLES driver и X11/Wayland desktop session.
nim c -o:build/native_window examples/native_window.nim
./build/native_window           # GLES3
./build/native_window --gles2   # GLES2
```

Стрелки left/right вращают camera, W/S меняют дистанцию; Escape или закрытие окна
завершает loop. SDL polling, drawable (не logical) size, resize, hidden/minimized
pause, buffer swap и явный teardown находятся в host layer. Renderer остаётся
platform-independent. SDL video init/quit соответствует каждой window lifetime.
Host — main-thread, один consumer SDL event queue; multi-window routing не добавлен.

CPU snapshots автомобилей обновляются 20 Hz, bounded clock/interpolation отделены
от frame loop; buffers переиспользуются, unchanged upload API сохранён. Pipeline
использует ContextScopes. ReadPixels/getError вызываются только в --smoke oracle,
не interactive render path. FPS claims не делаются. Vsync запрашивается, но драйвер
может его не поддержать; это не гарантия frame pacing.

## Автоматическая оконная проверка

`tools/test_window.sh` собирает host GCC, LLVM и cproc/QBE, запускает GLES2 и GLES3
под Xvfb с SDL X11 + Mesa software driver. Каждая программа создаёт, показывает,
использует и уничтожает окно/контекст **дважды**. Проверяются:

- ES profile/version (не desktop GL), реальное SDL окно и swap path;
- seeded последовательность resize и изменение drawable dimensions;
- hide/show с пропуском render; получение SDL_QUIT через event queue;
- небланковый framebuffer и отсутствие GL errors;
- cleanup renderer/pipeline до SDL GL context teardown, повторный close.

Логи ci-window-* содержат driver/version и presents/skips/resizes. Каждый процесс
ограничен timeout 60 s. Существующая JS/browser/UI и native pbuffer matrix остаётся.
Window job использует system Mesa, не ANGLE из LD_LIBRARY_PATH. Ubuntu runner
устанавливает SDL2/Mesa/Xvfb runtime packages; их версии зависят от apt snapshot,
в отличие от pinned compiler toolchains. Запуск программы без --smoke бесконечен
до пользовательского quit. Screenshot/interactive remote desktop пока отсутствуют.

## Что это НЕ закрывает

Xvfb — настоящий виртуальный X server с mapped windows, но не физический монитор
или аппаратный GPU. Hide/show проверяется без window manager; настоящий minimize,
keyboard input/focus и desktop compositor требуют manual desktop validation.
Не заявлены native context-loss recovery, mobile lifecycle, ARM execution,
Windows/macOS host либо Vulkan/Metal. SDL event storage резервирует aligned 64 bytes
для SDL2 union; текущая runtime matrix Linux x86-64. Host не делает автоматический
resource abandon при неожиданном сбросе драйвера. GPU ресурсы надо dispose до close.
