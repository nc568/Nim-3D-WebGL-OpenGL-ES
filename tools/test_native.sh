#!/bin/sh
# Explicit native matrix. LLVM and GLES are opt-in so missing drivers are not "PASS".
set -eu
NIM=${NIM:-nim}
mkdir -p build
for suite in test_core test_math3d test_resources test_instances test_post test_timing test_autoscale test_environment test_culling test_motion test_dirty; do
  "$NIM" c --nimcache:"build/cache-gcc-$suite" -r -o:"build/${suite}_gcc" "tests/$suite.nim"
  if [ -n "${CLANG:-}" ]; then
    "$NIM" c --cc:clang --clang.exe:"$CLANG" --clang.linkerexe:"$CLANG" \
      --nimcache:"build/cache-clang-$suite" -r -o:"build/${suite}_clang" "tests/$suite.nim"
  fi
done
if [ "${TEST_GLES:-0}" = 1 ]; then
  set --
  if [ "${ANGLE_SWIFTSHADER:-0}" = 1 ]; then set -- "$@" -d:angleSwiftShader; fi
  if [ -n "${EGL_LIBRARY:-}" ]; then set -- "$@" "-d:eglLibrary=$EGL_LIBRARY"; fi
  "$NIM" c --nimcache:build/cache-gles-gcc -r -o:build/test_gles_gcc "$@" tests/test_gles.nim
  if [ -n "${CLANG:-}" ]; then
    "$NIM" c --cc:clang --clang.exe:"$CLANG" --clang.linkerexe:"$CLANG" \
      --nimcache:build/cache-gles-clang -r -o:build/test_gles_clang "$@" tests/test_gles.nim
  fi
fi
