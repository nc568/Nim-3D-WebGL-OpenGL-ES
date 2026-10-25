#!/usr/bin/env bash
# The same explicit native matrix locally and on CI. No compiler fallback.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
export NIM="$PWD/build/toolchains/Nim/bin/nim"
export NIM_CPROC="$PWD/build/toolchains/Nim/bin/nim-cproc"
export CLANG="$PWD/build/toolchains/bin/zigcc"
export PATH="$PWD/build/toolchains/local/bin:$PWD/build/toolchains/bin:$PATH"
export EGL_LIBRARY="$PWD/build/toolchains/native-driver/lib/libEGL.so"
export LD_LIBRARY_PATH="$PWD/build/toolchains/native-driver/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export TEST_GLES=1 ANGLE_SWIFTSHADER=1
run() {
  local log=$1
  shift
  echo "Running: $*"
  if "$@" >"$log" 2>&1; then
    tail -n 14 "$log"
  else
    local status=$?
    tail -n 100 "$log"
    return "$status"
  fi
}
run build/ci-native-debug.log ./tools/test_native.sh
run build/ci-cproc-debug.log ./tools/test_cproc.sh
run build/ci-llvm-release.log "$NIM" c -r -d:release --cc:clang \
  --clang.exe:"$CLANG" --clang.linkerexe:"$CLANG" --nimcache:build/cache-ci-llvm-release \
  -d:angleSwiftShader -d:eglLibrary="$EGL_LIBRARY" -o:build/test_gles_ci_llvm tests/test_gles.nim
run build/ci-qbe-release.log "$NIM_CPROC" c -r -d:release -d:nimCproc --threads:off --mm:arc \
  --cc:gcc --gcc.exe:"$PWD/tools/cproc_cc.py" --gcc.linkerexe:"$PWD/tools/cproc_cc.py" \
  --nimcache:build/cache-ci-qbe-release -d:angleSwiftShader -d:eglLibrary="$EGL_LIBRARY" \
  -o:build/test_gles_ci_qbe tests/test_gles.nim
run build/ci-arm64-cross.log "$NIM" c --cpu:arm64 --os:linux --cc:clang \
  --clang.exe:"$CLANG" --clang.linkerexe:"$CLANG" \
  --passC:--target=aarch64-linux-gnu --passL:--target=aarch64-linux-gnu \
  --nimcache:build/cache-ci-arm64 -o:build/test_gles_ci_arm64 tests/test_gles.nim
readelf -h build/test_gles_ci_arm64 > build/ci-arm64-header.log
grep -q 'AArch64' build/ci-arm64-header.log
run build/ci-compiler-patch.log git -C build/toolchains/Nim apply --reverse --check "$PWD/patches/nim-2.2.4-cproc.patch"
echo 'Native matrix PASS; ARM64 cross-link ONLY, not ARM execution or a visible window.'

# CPU-only release observations; the same explicit correctness oracles as browsers.
run build/ci-bench-gcc.log "$NIM" c -r -d:release --nimcache:build/cache-bench-gcc -o:build/bench_gcc tests/bench_release.nim
run build/ci-bench-llvm.log "$NIM" c -r -d:release --cc:clang \
  --clang.exe:"$CLANG" --clang.linkerexe:"$CLANG" --nimcache:build/cache-bench-llvm \
  -o:build/bench_llvm tests/bench_release.nim
run build/ci-bench-qbe.log "$NIM_CPROC" c -r -d:release -d:nimCproc --threads:off --mm:arc \
  --cc:gcc --gcc.exe:"$PWD/tools/cproc_cc.py" --gcc.linkerexe:"$PWD/tools/cproc_cc.py" \
  --nimcache:build/cache-bench-qbe -o:build/bench_qbe tests/bench_release.nim

node tools/percentile_report.cjs
