# Building and running the wasm artifact

Operational reference for the `wasm` / `wasm-lib` Makefile targets. The README
covers *what* the artifact is and where it stands; this file covers *how* to
build, run, and embed it, plus the sharp edges.

## Toolchain

`clang-19`, `wasi-libc`, `libclang-rt-19-dev-wasm32`, `lld-19` (Ubuntu package
names). `WASM_CLANGXX` and `WASM_SYSROOT` are override points for a custom
compiler or a self-built sysroot:

```bash
make wasm                                            # /usr sysroot, clang++-19
make wasm WASM_CLANGXX=clang++ WASM_SYSROOT=/opt/wasi-sysroot
```

Running the artifact needs a WASI host with wasm exception-handling support —
Node ≥ 24, or a current browser (see *Runtime portability* below for the
non-browser story).

## Exception-handling runtime: `WASM_EH`

Lua's error handling lowers onto the wasm exception-handling proposal (the
artifact compiles as C++ so `LUAI_THROW`/`LUAI_TRY` become `throw`/`catch`).
Two modes select who owns exception dispatch:

| `WASM_EH` | what owns dispatch | semantics | libc++abi |
| - | - | - | - |
| `internal` (default) | the self-contained micro-runtime in `src/onelua.c` | `catch(...)` only — no type matching, no destructors | none needed |
| `external` | a real libc++abi built with `-fwasm-exceptions` | full typed catches | you supply it |

Use `external` when the host embedding Lua has **its own** C++ that needs
*typed* catches — Lua errors and the host's exceptions must then travel one
coherent EH domain, which the bundled `catch(...)`-only shim cannot provide.
It is gated behind `-DLUAW_EXTERNAL_EH`, which suppresses the shim so the
external runtime's `__cxa_*` symbols are the only ones present:

```bash
make wasm WASM_EH=external \
  WASM_EH_FLAGS="-L/path/to/rt/lib" \
  WASM_EH_LIBS="-lc++ -lc++abi /path/to/libunwind_wasm.a"
```

### Hazard: the micro-shim wins silently

Linking a real libc++abi **without** `WASM_EH=external` (i.e. without
`-DLUAW_EXTERNAL_EH`) produces **no** duplicate-symbol error. The bundled
shim's `__cxa_*` definitions satisfy every reference, so the archive members
are simply never pulled — you end up on `catch(...)`-only semantics without any
diagnostic. `WASM_EH=external` closes this two ways: it removes the shim so a
missing external runtime becomes a *link* error, and the target runs a
post-build fingerprint check (`grep` for the libc++abi terminate string in the
artifact) that fails the build if the external runtime was not actually linked.

## Running the official test suite under wasm

WASI has no shell, so `tests/main.lua`'s `assert(os.execute(...))` and the other
non-portable checks cannot pass under the wasm build. The suite's own
portability switch, `_port=true`, skips exactly those. It is **required** here,
not optional:

```bash
cd tests
node ../scripts/wasm-run.mjs ../lua.wasm -e"_port=true" all.lua
```

Note the **attached** form `-e"_port=true"` (no space). `-e <chunk>` also works,
but a following argument that itself begins with `--` (as some suite files and
ad-hoc chunks do) is ambiguous to the standalone interpreter's argument scan;
`-e<chunk>` avoids it. This matters most when driving the artifact purely
through `argv` — the natural path when there is no filesystem to load from.

> **Known limitation.** As of pin `945f810`, an external bring-up audit reports
> that `locals.lua` (the `<close>` / to-be-closed region) segfaults the *host*
> process under the wasm build on Node 22 / V8. See
> [`wasm-audit-2026-07-05.md`](wasm-audit-2026-07-05.md). This is not yet
> reproduced under CI in this repository; it is recorded here so the suite-run
> instructions above are not mistaken for a clean-pass claim.

## Runtime portability

The artifact is emitted with the **legacy** wasm exception-handling encoding
(`try`/`catch`), which is what clang ≤ 19 produces. Browsers and Node run it;
non-browser runtimes such as wasmtime reject it (`legacy_exceptions feature
required`). The standardized encoding (`try_table` / `exnref`, emitted by
LLVM 20+) would restore that runtime breadth. Moving to it is an open design
question — it raises the toolchain floor to LLVM 20 — tracked in
[`wasm-audit-2026-07-05.md`](wasm-audit-2026-07-05.md), finding 2.
