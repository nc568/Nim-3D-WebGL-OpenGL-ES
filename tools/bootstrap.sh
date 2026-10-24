#!/bin/sh
# Optional Linux test toolchains, stored ONLY in ignored build/. No system installs.
# Usage: tools/bootstrap.sh nim|cproc|llvm|native-driver|ui
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
T="$ROOT/build/toolchains"
mkdir -p "$T"
fetch() {
  directory=$1 url=$2 revision=$3
  if [ ! -d "$directory" ]; then
    mkdir -p "$directory"
    git -C "$directory" init -q
    git -C "$directory" fetch --depth 1 "$url" "$revision"
    git -C "$directory" checkout --detach FETCH_HEAD
  fi
  [ "$(git -C "$directory" rev-parse HEAD)" = "$revision" ] || {
    echo "Toolchain revision mismatch: $directory (not modifying it)" >&2; exit 1;
  }
}
case "${1:-}" in
nim)
  fetch "$T/Nim" https://github.com/nim-lang/Nim.git f7145dd26efeeeb6eeae6fff649db244d81b212d
  if [ ! -x "$T/Nim/bin/nim" ]; then (cd "$T/Nim" && sh build_all.sh); fi
  ;;
cproc)
  "$ROOT/tools/bootstrap.sh" nim
  if ! git -C "$T/Nim" apply --reverse --check "$ROOT/patches/nim-2.2.4-cproc.patch" 2>/dev/null; then
    git -C "$T/Nim" apply --check "$ROOT/patches/nim-2.2.4-cproc.patch"
    git -C "$T/Nim" apply "$ROOT/patches/nim-2.2.4-cproc.patch"
  fi
  (cd "$T/Nim" && bin/nim c -d:release --out:bin/nim-cproc compiler/nim.nim)
  fetch "$T/qbe" https://github.com/michaelforney/qbe.git be4363267bc926ae90ef2cf412139224b78a6795
  (cd "$T/qbe" && make -j2)
  mkdir -p "$T/bin"
  ln -sf ../qbe/qbe "$T/bin/qbe"
  fetch "$T/cproc" https://github.com/michaelforney/cproc.git d1c53ddf56571573a7025324c8dd5c6d547a4d1f
  (cd "$T/cproc" && ./configure --prefix="$T/local" && make -j2 && make install)
  echo "Set PATH=$T/local/bin:$T/bin:\$PATH and NIM_CPROC=$T/Nim/bin/nim-cproc"
  ;;
llvm)
  python3 -m pip install --target "$T/python" ziglang==0.13.0
  mkdir -p "$T/bin"
  cat > "$T/bin/zigcc" <<'WRAPPER'
#!/bin/sh
exec "$(dirname "$0")/../python/ziglang/zig" cc "$@"
WRAPPER
  chmod +x "$T/bin/zigcc"
  ;;
ui)
  fetch "$T/fossil" https://github.com/nc568/fossil-nim.git 1d01eed8870403ca617418bbc6ff5ff52c20f3c8
  ;;
native-driver)
  mkdir -p "$T/angle-package" "$T/native-driver/lib"
  (cd "$T/angle-package" && npm pack @sparticuz/chromium@131.0.1 && tar -xf sparticuz-chromium-131.0.1.tgz)
  node - "$T/angle-package" <<'JS'
const fs=require('fs'),z=require('zlib'),p=process.argv[2];
fs.writeFileSync(p+'/swiftshader.tar',z.brotliDecompressSync(fs.readFileSync(p+'/package/bin/swiftshader.tar.br')));
JS
  tar -xf "$T/angle-package/swiftshader.tar" -C "$T/native-driver/lib"
  ;;
*) echo 'Usage: tools/bootstrap.sh nim|cproc|llvm|native-driver|ui' >&2; exit 2 ;;
esac
