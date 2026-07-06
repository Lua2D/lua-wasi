# wasm audit — love-wasi bring-up, 2026-07-05

Record of an external audit of the wasm build, produced while bringing lua-wasm
up as the Lua VM for [love-wasi](https://github.com/andy-emerson/love-wasi).
Filed against this repo at pin `945f810`. The original lives in that repo at
`wasi/lua/AUDIT-lua-wasm.md`, alongside the build recipes and witnesses it
cites; this file is the in-tree record and tracks each finding's status here.

**Provenance and grading.** The audit is a **by-hand, single-engine** report
(Node 22 / V8, plus a wasmtime attempt). Its crash and portability findings
have **not been independently reproduced under CI in this repository** — this
environment cannot build the wasm artifact (no clang-19 / wasi-libc sysroot).
Findings are recorded at the strength the evidence supports and no higher.

## Findings and status

| # | Finding | Status in this repo |
| - | - | - |
| 1 | `locals.lua` (`<close>` / coroutine region) segfaults the **host** under the wasm build; isolation matrix pins it to V8's legacy wasm-EH path, not the reporter's toolchain | **Open.** Recorded in `doc/wasm.md` and README. Not reproduced in CI here; the fix candidate is finding 2. |
| 2 | Artifact uses the **legacy** wasm-EH encoding (`try`/`catch`); wasmtime rejects it — only browsers/Node run it. Standardized `try_table`/`exnref` (LLVM 20+) restores breadth and is the leading dodge for #1 | **Open — design decision.** Raises the toolchain floor to LLVM 20; needs a maintainer call. Documented in `doc/wasm.md`. |
| 3 | `LUAW_EXTERNAL_EH` did not exist: embedders needing typed C++ catches could not suppress the bundled `catch(...)` micro-runtime | **Done.** Guard added in `src/onelua.c`; wired to the `WASM_EH=external` Makefile knob. |
| 4 | The micro-shim wins **silently** — linking a real libc++abi without the guard raises no error, leaving you on `catch(...)` semantics unknowingly | **Mitigated.** `WASM_EH=external` removes the shim (missing runtime → link error) and the `wasm` target runs a post-build libc++abi fingerprint check. Documented in `doc/wasm.md`. |
| 5 | Smaller items: no documented way to run the suite under wasm (`_port=true` is required — WASI has no shell); Makefile EH-runtime had no knob; `-e<src>` attached form needed when a chunk starts with `--` | **Done.** Suite-under-wasm run, the `-e<src>` form, and the `WASM_EH` knob are documented in `doc/wasm.md`; the knob is implemented in the Makefile. (`WASM_CLANGXX`/`WASM_SYSROOT` were already command-line overridable; the Makefile now says so.) |

## What the audit confirmed working (recorded for balance)

With love-wasi's own toolchain (clang 18.1.3, self-built wasi-libc sysroot,
wasm-EH libc++abi, `LUAW_EXTERNAL_EH`): a 9/9 step-1 witness on Node and
headless Chromium (pcall/error through a real libc++abi, coroutine error
containment, yield/resume, 5.4 integer semantics, string.pack, GC cycle); the
`MAKE_LIB` reactor passed a 12-check stress battery (contained stack overflow,
table error objects, resident-program replacement, a 50k-frame pump, GC under
load); and suite files `main.lua` (port mode), `gc.lua`, `db.lua`, `calls.lua`,
`strings.lua`, `literals.lua`, `tpack.lua`, `attrib.lua` ran clean before the
`locals.lua` crash point.

## Open items worth tracking as issues

- **Finding 1** — the host segfault. Needs in-repo reproduction and a minimal
  wasm module to file upstream with V8, independent of the finding-2 fix.
- **Finding 2** — migrate to the `try_table`/`exnref` EH encoding (LLVM 20+).
  A maintainer decision on the toolchain-floor bump; also the non-V8
  cross-check (wasmtime) the audit could not complete.
- **CI witness** — the audit's standing recommendation: run the suite under the
  wasm build in CI (`-e"_port=true"`, Node) so the README's "witnessed" claim is
  continuously true rather than by-hand. Already an open goal in the README.
