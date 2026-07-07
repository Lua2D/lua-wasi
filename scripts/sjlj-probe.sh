#!/bin/sh
# The issue-#18 watch probe: try the constitutional-preference C route
# (plain-C setjmp/longjmp lowered by clang's -mllvm -wasm-enable-sjlj)
# on a given clang, and if it compiles, run the full suite on both
# engines. EXPECTED TO FAIL while LLVM's lowering is broken -- the
# probe's product is its log (which compiler, which failure), recorded
# per LLVM minor on issue #18's cadence: 18 segfaulted, 19.1.1 emitted
# structurally invalid catch placement, 20/21.1 reject the runtime's
# tag symbols (see src/onelua.c's WASI-support header). If this ever
# goes green end to end, the C path has healed: file the switch-over
# as its own issue -- do not flip the default from inside a probe.
#
# usage: scripts/sjlj-probe.sh [clang] [sysroot]   (run from repo root)
set -ex

CLANG=${1:-clang-21}
SYSROOT=${2:-/usr}

$CLANG --version

# The wasm target flags mirror the Makefile's WASM_CFLAGS minus the
# C++-route items (-fwasm-exceptions -nostdlib++), plus the sjlj
# lowering; the standardized-encoding flag matches the shipped
# artifact so the probe answers for the encoding we actually use.
$CLANG --target=wasm32-wasi --sysroot="$SYSROOT" -O2 -fno-strict-aliasing \
  -mllvm -wasm-enable-sjlj \
  -mllvm -wasm-use-legacy-eh=false \
  -Isrc/wasi -Isrc \
  -D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_PROCESS_CLOCKS \
  -DLUA_USE_JUMPTABLE=0 \
  -Wl,-z,stack-size=8388608 \
  -o lua-sjlj.wasm src/onelua.c \
  -lwasi-emulated-signal -lwasi-emulated-process-clocks

# It compiled -- the news since LLVM 18. Now: does it run?
cd tests
node ../scripts/wasm-run.mjs ../lua-sjlj.wasm -e"_port=true" all.lua
python3 ../scripts/wasmtime-run.py ../lua-sjlj.wasm -e"_port=true" all.lua

echo "sjlj probe: GREEN -- the C route compiled and passed the suite on both engines"
