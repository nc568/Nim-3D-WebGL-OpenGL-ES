# Экспериментальный Nim → C → cproc → QBE

**Статус на 24 октября 2026:** текущие тесты библиотеки компилируются и запускаются
на Linux x86-64: core/quality, math/geometry, indexed meshes/owner deltas,
GLES2/3 framebuffer, 256-ID palette oracle и instancing/fallback oracle. GLES проверен также с `-d:release`.
Ни C-файлы библиотеки, ни тестовые executables не компилировались GCC вместо cproc.
Сам Nim/cproc/QBE bootstrap собирается GCC; cpp/as/ld и libc остаются системными.

Это НЕ универсальная совместимость Nim/cproc. Проверенный режим — ARC,
`--threads:off`, Nim 2.2.4 + приложенный патч. ORC, потоки, C++, Windows/macOS,
Android/iOS и ARM через cproc здесь не аттестованы.

## Зафиксированные исходники

- Nim tag `v2.2.4`, commit `f7145dd26efeeeb6eeae6fff649db244d81b212d`.
- cproc `michaelforney/cproc`, commit `d1c53ddf56571573a7025324c8dd5c6d547a4d1f`.
- QBE `michaelforney/qbe`, ветка `arm64-extern-offset`, commit
  `be4363267bc926ae90ef2cf412139224b78a6795`.

Последняя ревизия QBE не требует наших изменений. Старые зеркала QBE из ранних
отчётов не подходят: сначала предел длины идентификатора, затем отсутствие `extern`
в IR, который выдаёт выбранный cproc. Важно фиксировать **совместимую пару**.

## Что делает патч

`patches/nim-2.2.4-cproc.patch` теперь заменяет ранний однострочный эксперимент.
Применять к чистой копии Nim 2.2.4, не поверх старого патча.

1. Правильный C99 inline declaration для cproc (`NIM_CPROC`).
2. При `-d:nimCproc` RTTI display table становится writable: runtime объявляет
   неконстантный указатель. Это временный ABI workaround, а не полноценная
   const-корректность всех интерфейсов Nim.
3. При том же флаге static array/object constants и global let arrays/objects имеют writable C
   storage, потому что сгенерированные параметры массивов не const-qualified.
   **Nim-правила неизменяемости сохраняются**, но такие массивы переходят из rodata
   в data. Object case подтверждён constant AABB regression в девятом срезе.
   Не отключаем `NIM_CONST` глобально; строки и другие константы сохраняются.
4. `nimCopyMem` использует const-correct libc memcpy вместо wrapper с `void* source`.
5. Хеширование использует существующий portable 64-bit fallback вместо GNU
   `__uint128_t`, которого у cproc нет.
6. При `-d:nimCproc` отключается GNU `case a ... b`: небольшие диапазоны
   разворачиваются в стандартные case labels, большие — в существующие Nim
   comparison chains. Найдено при компиляции std/unittest в пятом срезе;
   добавлена регрессия для малых/больших диапазонов. Без флага поведение прежнее.

Цена: часть данных перестаёт быть read-only/shareable между процессами;
хеширование может стать медленнее. Выигрыш/потери CPU/frame time не измерялись.
Долгосрочно лучше исправить const-корректность Nim C ABI и добавить отдельный
cproc compiler driver, чем полагаться на режим GCC + адаптер флагов.

`tools/cproc_cc.py` удаляет только перечисленные необязательные GCC-флаги,
включая `-fno-math-errno` (его удаление сохраняет более строгую errno-семантику).
Он задаёт `__CHAR_BIT__=8`, `NIM_CPROC` и `_GNU_SOURCE` до системных headers.
Последнее нужно, потому что Nim может включить string.h до собственного define
_GNU_SOURCE и потерять объявление memmem. Не использовать wrapper без `-d:nimCproc`.

## Воспроизведение

Подготовьте отдельную копию Nim указанной версии (не изменяйте системный compiler).
Если ранее применяли старый патч, начните с чистого checkout.

```sh
# $NIM_SRC — корень исходников Nim 2.2.4 с уже рабочим bootstrap bin/nim
# $SOFTGFX — корень этой библиотеки
cd "$NIM_SRC"
git apply "$SOFTGFX/patches/nim-2.2.4-cproc.patch"
bin/nim c -d:release --out:bin/nim-cproc compiler/nim.nim
```

В закреплённых исходниках cproc выполнить `./configure --prefix=...`, `make`,
`make install`; в QBE — `make`. Поместить cproc, cproc-qbe и новый qbe в PATH.
Не подменять путь старым qbe из системной установки.

```sh
cd "$SOFTGFX"
NIM_CPROC="$NIM_SRC/bin/nim-cproc" ./tools/test_cproc.sh

# Native GPU matrix, при наличии описанного в validation.md ANGLE:
NIM_CPROC="$NIM_SRC/bin/nim-cproc" TEST_GLES=1 ANGLE_SWIFTSHADER=1 \
  EGL_LIBRARY="$ANGLE_LIB/libEGL.so" LD_LIBRARY_PATH="$ANGLE_LIB" \
  ./tools/test_cproc.sh
```

Для release повторить конкретную команду со следующими флагами:

```sh
"$NIM_SRC/bin/nim-cproc" c -r -d:release -d:nimCproc --threads:off --mm:arc \
  --cc:gcc --gcc.exe:"$PWD/tools/cproc_cc.py" \
  --gcc.linkerexe:"$PWD/tools/cproc_cc.py" \
  --nimcache:build/cache-qbe-release -o:build/test_resources_qbe_release \
  tests/test_resources.nim
```

Скрипт завершится с ненулевым кодом при ошибке; автоматического fallback нет.
Патчи пока не отправлялись upstream и не проходили полный regression suite Nim.
