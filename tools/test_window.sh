#!/usr/bin/env bash
# Real SDL window/swap/event path. Xvfb is a window server, NOT physical hardware.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
NIM="$PWD/build/toolchains/Nim/bin/nim"
CLANG="$PWD/build/toolchains/bin/zigcc"
export PATH="$PWD/build/toolchains/local/bin:$PWD/build/toolchains/bin:$PATH"
# Deliberately use the system Mesa EGL/GLES for SDL, not the pbuffer ANGLE driver.
unset LD_LIBRARY_PATH EGL_PLATFORM
export SDL_VIDEODRIVER=x11 LIBGL_ALWAYS_SOFTWARE=1 SDL_VIDEO_X11_FORCE_EGL=1
run() {
  local log=$1; shift
  if "$@" >"$log" 2>&1; then tail -n 12 "$log"; else local code=$?; tail -n 100 "$log"; return "$code"; fi
}
run build/ci-window-gcc-build.log "$NIM" c --nimcache:build/cache-window-gcc -o:build/window_gcc examples/native_window.nim
run build/ci-window-llvm-build.log "$NIM" c --cc:clang --clang.exe:"$CLANG" --clang.linkerexe:"$CLANG" --nimcache:build/cache-window-llvm -o:build/window_llvm examples/native_window.nim
run build/ci-window-qbe-build.log "$PWD/build/toolchains/Nim/bin/nim-cproc" c -d:nimCproc --threads:off --mm:arc --cc:gcc --gcc.exe:"$PWD/tools/cproc_cc.py" --gcc.linkerexe:"$PWD/tools/cproc_cc.py" --nimcache:build/cache-window-qbe -o:build/window_qbe examples/native_window.nim
for compiler in gcc llvm qbe; do
  for api in gles2 gles3; do
    if [ "$api" = gles2 ]; then export MESA_GLES_VERSION_OVERRIDE=2.0; else export MESA_GLES_VERSION_OVERRIDE=3.0; fi
    run "build/ci-window-$compiler-$api.log" timeout 60 xvfb-run -a -s '-screen 0 1024x768x24' "build/window_$compiler" --smoke "--$api"
  done
done
