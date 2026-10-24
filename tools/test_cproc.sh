#!/bin/sh
# Requires the patched Nim compiler/runtime and the pinned QBE described in docs/cproc.md.
# No fallback compiler. Fail immediately on any compile or runtime regression.
set -eu
NIM_CPROC=${NIM_CPROC:-nim-cproc}
mkdir -p build
for suite in test_core test_math3d test_resources test_instances test_post test_timing test_autoscale test_environment test_culling test_motion test_dirty test_identity test_grid test_recovery test_workloads; do
  "$NIM_CPROC" c -r -d:nimCproc --threads:off --mm:arc --cc:gcc \
    --gcc.exe:"$PWD/tools/cproc_cc.py" --gcc.linkerexe:"$PWD/tools/cproc_cc.py" \
    --nimcache:"build/cache-cproc-$suite" -o:"build/${suite}_cproc" "tests/$suite.nim"
done
if [ "${TEST_GLES:-0}" = 1 ]; then
  set --
  if [ "${ANGLE_SWIFTSHADER:-0}" = 1 ]; then set -- "$@" -d:angleSwiftShader; fi
  if [ -n "${EGL_LIBRARY:-}" ]; then set -- "$@" "-d:eglLibrary=$EGL_LIBRARY"; fi
  "$NIM_CPROC" c -r -d:nimCproc --threads:off --mm:arc --cc:gcc \
    --gcc.exe:"$PWD/tools/cproc_cc.py" --gcc.linkerexe:"$PWD/tools/cproc_cc.py" \
    --nimcache:build/cache-cproc-gles -o:build/test_gles_cproc "$@" tests/test_gles.nim
fi
