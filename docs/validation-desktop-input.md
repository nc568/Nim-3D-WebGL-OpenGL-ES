# Срез 18: window-manager/input lifecycle

Linux SDL2 host теперь предоставляет focused/minimized flags, принимает camera
input только при input focus и сохраняет короткий Escape keydown из event queue
(он мог теряться при polling keyboard state после уже доставленного keyup).

Interactive demo останавливает render/simulation при hidden/minimized/unfocused
window, продолжая polling событий с SDL_Delay(10). После resume первый elapsed=0,
clock remainder сбрасывается. Previous/current history привязывается к последнему
rendered pose/phase: нет catch-up за время паузы и отката к предыдущему tick.
Аналогичный reset используется после long-stall plan.paused. Это demo policy,
не обязательная политика middleware для background simulation.

Обычный --smoke остаётся без focus requirement, поскольку старый Xvfb smoke не
запускает window manager. Интерактивный режим и --desktop-test требуют focus.
Последний добавляет telemetry каждые ~100ms и deadline 60s, но не синтетические SDL
keyboard events. ReadPixels/checks — только test modes. Production hot path не
пишет telemetry, buffers не перевыделяются при pause/resume.

## Desktop CI

`tools/desktop_test.py` запускается внутри Xvfb с Openbox, xdotool и xmessage.
Для каждого GCC/LLVM/cproc-QBE binary и каждого Mesa GLES 2.0/3.0 context:

1. XTest keyboard Right/W меняет camera angle/distance.
2. Фокус передаётся отдельному xmessage window. На трёх последовательных
   telemetry reports presents/ticks/camera/rendered phase должны оставаться
   неизменными, даже при Right, посланном другому окну; event polling продолжается.
3. Focus возвращается: simulation/render снова работают.
4. Openbox iconify вызывает настоящий SDL minimized flag; rendering/ticks
   заморожены. EWMH activation восстанавливает окно.
5. Восемь X11 resize requests должны появиться в drawable dimensions.
6. Alt+F4 проходит через Openbox WM_DELETE_WINDOW и штатный cleanup.
7. Новый экземпляр закрывается Escape (реальная keyboard event queue).

Ожидания ограничены deadline, основаны на свежей telemetry, не на фиксированном
числе sleep до предполагаемого успеха. Exit codes и штатный quit marker обязательны;
пропавший процесс/telemetry, GL error или неправильное состояние проваливают test.
Зависимости устанавливаются только в GitHub runner. Логи ci-window-desktop-* входят
в native-evidence. Hardware FPS по этим данным не оценивается.

Это виртуальная desktop integration под software Mesa, не физическая клавиатура,
монитор, desktop-compositor survey, Wayland/native hardware acceptance или mobile.
Openbox default bindings — часть тестового окружения. Не добавлены SDL context-loss
recovery, Windows/macOS ports и ARM execution. Старые ограничения lifetime/one-event-
consumer сохраняются. Документ validation-window.md описывает базовый host.
