#!/usr/bin/env python3
"""Real X11 input/WM actions, not SDL_PushEvent keyboard mocks. Runs inside Xvfb."""
import os
import queue
import subprocess
import sys
import threading
import time


def command(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT, timeout=10).strip()


def stop(process):
    if process is not None and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=3)


class Session:
    def __init__(self, executable, api):
        self.process = subprocess.Popen([executable, '--desktop-test', '--'+api],
                                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        self.events = queue.Queue()
        self.lines = []
        self.reader = threading.Thread(target=self.read, daemon=True)
        self.reader.start()

    def read(self):
        for line in self.process.stdout:
            self.lines.append(line)
            print(line, end='', flush=True)
            if line.startswith('HOST '):
                data = {k: float(v) for k, v in (field.split('=') for field in line.split()[1:])}
                self.events.put((time.monotonic(), data))
        self.events.put((time.monotonic(), None))

    def wait(self, predicate, after=0):
        deadline = time.monotonic()+12
        while True:
            remaining = deadline-time.monotonic()
            if remaining <= 0:
                raise AssertionError('Timed out waiting for desktop telemetry')
            try:
                at, state = self.events.get(timeout=remaining)
            except queue.Empty:
                raise AssertionError('No desktop telemetry; recent output: '+''.join(self.lines[-8:]))
            if state is None:
                raise AssertionError('Window exited before expected state: '+''.join(self.lines[-8:]))
            if at >= after and predicate(state):
                return state

    def frozen(self, state):
        for _ in range(3):
            next_state = self.wait(lambda s: s['paused'] == 1, after=time.monotonic())
            for key in ('presents', 'ticks', 'angle', 'distance', 'phase'):
                assert next_state[key] == state[key], (key, state, next_state)
            assert next_state['skips'] > state['skips']
            state = next_state

    def finish(self):
        code = self.process.wait(timeout=10)
        self.reader.join(timeout=3)
        assert code == 0, ''.join(self.lines[-12:])
        assert any(line.startswith('DESKTOP PASS:') for line in self.lines)


def exercise(executable, api, full):
    app = Session(executable, api)
    sink = None
    try:
        window = command('xdotool', 'search', '--sync', '--all', '--pid', str(app.process.pid), '--name', 'Nim GLES').splitlines()[0]
        command('xdotool', 'windowactivate', '--sync', window)
        initial = app.wait(lambda s: s['focused'] == 1 and s['presents'] >= 2)
        if full:
            command('xdotool', 'keydown', 'Right')
            app.wait(lambda s: s['angle'] > initial['angle']+0.06, after=time.monotonic())
            command('xdotool', 'keyup', 'Right')
            command('xdotool', 'keydown', 'w')
            app.wait(lambda s: s['distance'] < initial['distance']-0.1, after=time.monotonic())
            command('xdotool', 'keyup', 'w')
            sink = subprocess.Popen(['xmessage', '-title', 'SoftgfxFocusSink', '-buttons', 'OK:0', 'focus target'],
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            sink_id = command('xdotool', 'search', '--sync', '--name', '^SoftgfxFocusSink$').splitlines()[0]
            command('xdotool', 'windowactivate', '--sync', sink_id)
            paused = app.wait(lambda s: s['paused'] == 1 and s['focused'] == 0, after=time.monotonic())
            # A real key sent to another focused window must not move this camera.
            command('xdotool', 'keydown', 'Right')
            app.frozen(paused)
            command('xdotool', 'keyup', 'Right')
            command('xdotool', 'windowactivate', '--sync', window)
            app.wait(lambda s: s['paused'] == 0 and s['ticks'] > paused['ticks'], after=time.monotonic())
            stop(sink)
            sink = None
            command('xdotool', 'windowminimize', window)
            minimized = app.wait(lambda s: s['paused'] == 1 and s['minimized'] == 1, after=time.monotonic())
            app.frozen(minimized)
            command('xdotool', 'windowactivate', '--sync', window)
            app.wait(lambda s: s['paused'] == 0 and s['minimized'] == 0 and s['presents'] > minimized['presents'],
                     after=time.monotonic())
            for i in range(8):
                width, height = 200+(i*73 % 220), 150+(i*47 % 160)
                command('xdotool', 'windowsize', window, str(width), str(height))
                app.wait(lambda s: s['width'] == width and s['height'] == height and s['paused'] == 0,
                         after=time.monotonic())
            for generation in (1, 2):
                command('xdotool', 'key', '--clearmodifiers', 'r')
                app.wait(lambda s: s['recreations'] == generation, after=time.monotonic())
                # SDL video teardown destroys the X window ID; never reuse it.
                window = command('xdotool', 'search', '--sync', '--all', '--pid', str(app.process.pid),
                                 '--name', 'Nim GLES').splitlines()[0]
                command('xdotool', 'windowactivate', '--sync', window)
                app.wait(lambda s: s['paused'] == 0 and s['focused'] == 1, after=time.monotonic())
            assert sum(line.startswith('RECREATE PASS:') for line in app.lines) == 2
            command('xdotool', 'key', '--clearmodifiers', 'alt+F4') # Openbox WM_DELETE_WINDOW
        else:
            command('xdotool', 'key', '--clearmodifiers', 'Escape')
        app.finish()
    finally:
        stop(sink)
        stop(app.process)


wm = None
try:
    wm = subprocess.Popen(['openbox', '--sm-disable'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.monotonic()+10
    while 'window id #' not in command('xprop', '-root', '_NET_SUPPORTING_WM_CHECK'):
        if time.monotonic() >= deadline or wm.poll() is not None:
            raise AssertionError('Openbox did not initialize')
        time.sleep(0.05)
    exercise(sys.argv[1], sys.argv[2], True)
    exercise(sys.argv[1], sys.argv[2], False)
    print('DESKTOP INPUT PASS: keyboard, unfocused freeze, minimize/restore, resize, recreation pixel parity, WM close, Escape', flush=True)
finally:
    stop(wm)
