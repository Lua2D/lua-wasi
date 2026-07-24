# Linking Lua into a wasm32-wasi artifact

"Embeddable Lua for WebAssembly" has two consumer shapes:

1. **A host wrapping the finished `lua.wasm`** — a JS/host runtime instantiates
   the standalone interpreter (or the `lua-lib.wasm` reactor) and calls in. This
   is what `doc/wasm.md` and the README's Embed section cover.
2. **A C/C++ project targeting wasm32-wasi that needs Lua *inside* its own
   artifact** — it links the Lua core in and drives it through `lua.h`. This is
   the shape [love-wasm](https://github.com/lua2d) uses, and the one this file
   documents (issue #11).

This is the contract for shape 2: the flags, the two consumption paths, and the
exception-handling choice. The worked, CI-witnessed example is
[`examples/embed/`](../examples/embed/).

## Two paths, one contract

### Recommended — source drop

Compile `src/onelua.c` in your own build alongside your code. Source consumption
makes the contract self-satisfying: one compiler, one flag set, no prebuilt-ABI
drift. This is what `examples/embed/build.sh` does.

### Convenience — `make liblua.a`

A prebuilt archive plus public headers, under the same requirements, with
toolchain-version skew explicitly **the consumer's risk**:

```bash
make liblua.a          # -> liblua.a + include/{lua,luaconf,lualib,lauxlib}.h + lua.hpp
```

Override `WASM_CLANGXX` / `WASM_SYSROOT` / `WASM_AR` as for the `wasm` target
(see `doc/wasm.md`). On hosts without a packaged clang 20, use the `zig c++`
recipe from `doc/wasm.md` and `WASM_AR="python3 -m ziglang ar"`.

## The flag contract

Both paths compile the core under these requirements. They are not optional: the
core, and any Lua error it raises, must share one coherent ABI with your code.

| requirement | why |
| - | - |
| **`--target=wasm32-wasi`** with a **wasi-libc** sysroot | the platform |
| **`clang 20+`** (or `zig c++`) | the standardized wasm-EH encoding needs LLVM 20+ (`doc/wasm.md`) |
| **`onelua.c` compiled as C++** (`-x c++`) | Lua's `LUAI_THROW`/`LUAI_TRY` lower to `throw`/`catch`; the plain-C `setjmp`/`longjmp` route is blocked upstream (#18) |
| **`-fwasm-exceptions`** | Lua errors unwind via wasm-EH; your code and Lua must agree on the mechanism |
| **`-nostdlib++`** | no libc++ is linked — `onelua.c` supplies its own EH runtime (below); no distro ships a libc++abi built with wasm-EH |
| **`-DMAKE_LIB`** | core + libraries only. **Not** `-DMAKE_REACTOR`: the `luaw_*` reactor glue (the coroutine-per-frame host interface) belongs to *this* project's finished artifact, not to an embedded core. You own your control flow and speak `lua.h`. |

`-fno-strict-aliasing` is also applied (a wasm-backend GC miscompile mitigation,
#4); carry it too. See `examples/embed/build.sh` for the exact line.

**The exec model is not part of this contract.** Whether your artifact is a WASI
command (`main`/`_start`) or a reactor (`-mexec-model=reactor`) is your link-time
choice — a property of your program, not of the Lua core. `liblua.a` is
exec-model-agnostic by design.

## Exception-handling runtime: which mode you need

`onelua.c` bakes in a micro-runtime — five `__cxa_*` entry points plus dummy
typeinfo vtables — because Lua throws exactly one pointer and only ever does
`catch(...)`, so it needs no real libc++abi. That runtime ships in **both**
consumption paths. It is correct for Lua alone, but lossy for anyone else: it
does no type matching and runs no destructors.

So the mode depends on your own C++:

- **Internal (default).** Your code raises no C++ exceptions of its own, or none
  that cross into Lua. Keep the bundled micro-runtime: zero external EH
  dependency, `catch(...)`-only. `examples/embed/embed.c` is this mode.
- **External (`WASM_EH=external` / `-DLUAW_EXTERNAL_EH`).** Your host C++ uses
  **typed** catches (`catch (MyError&)`) or exception-object destructors. The
  bundled shim would give those silently wrong behavior, so this mode suppresses
  it and a real `-fwasm-exceptions` libc++abi owns dispatch — Lua's errors and
  your typed exceptions then travel one EH domain. `examples/embed/embed-eh.cpp`
  is this mode.

The flags, the link inputs, the silent-fallback hazard, and the in-tree recipe
for building a wasm-EH libc++abi (`examples/embed/build-eh.sh`, since no distro
ships one — not even zig's bundled one) all live in [`doc/wasm.md`](wasm.md)'s
`WASM_EH` section, the single source for the mechanics.

## Status

- **Source drop + Lua-error-across-the-boundary** —
  CI-witnessed by the `embed` job (`examples/embed/`), and witnessed natively
  before landing.
- **`liblua.a` convenience archive** — built by the Makefile target; the wasm
  archive is exercised by the same toolchain the CI `embed`/`wasm` jobs use.
- **External-EH runtime with a downstream's own *typed* C++ exception** —
  CI-witnessed by the `embed` job's external-EH step (`embed-eh.cpp` +
  `build-eh.sh`): typed catch with exception-object destructor run, and a Lua
  `error()` caught through the same real libc++abi, in one artifact. First
  witnessed 2026-07-06 under wasmtime; enforced under Node 24 in CI.
