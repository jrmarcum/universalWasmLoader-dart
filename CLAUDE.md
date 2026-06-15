> **⚠️ PORTABLE PROJECT MEMORY NOW LIVES IN `cmem/`** — start at [`cmem/INDEX.md`](cmem/INDEX.md).
> When saving new project memory, write it into the matching `cmem/` topic file (and refresh its
> pointer in `cmem/INDEX.md`). The **"update the project memory"** and **"look for code issues"**
> triggers are defined in `cmem/INDEX.md` and are binding. This `CLAUDE.md` remains as the auto-loaded
> historical archive; `cmem/` is the source of truth.

# universalWasmLoader-dart

Universal WASM loader for Dart — the Dart port of the Universal WASM Loader (see the JS/TS reference
`universalWasmLoader-js` and the cross-language `SPEC.md`).

## Project Overview

Early-stage Dart package for loading WebAssembly modules the way the reference loader does — auto-detect
the companion `.wit`, apply the Canonical ABI, and return a typed handle. Intended to be published to
**pub.dev** as the Dart member of the polyglot loader ecosystem.

## Toolchain

- Platform: Dart SDK (and Flutter-compatible).
- Build / test / run: `dart pub get`, `dart test`, `dart run`; format with `dart format`, lint with
  `dart analyze`.
- Package manager / registry: **pub.dev**; package version lives in `pubspec.yaml` (`version:`).
- OS: Windows 11 (development environment).

## WASM runtime — OPEN decision

Dart has no single canonical WASM host. Candidates (decide before implementing):
- **Web:** `dart:js_interop` over the browser's native `WebAssembly` (best fit for Flutter web).
- **Native (Dart VM):** `dart:ffi` bindings to a C wasm runtime (e.g. the wasmtime C API — which would
  share marshalling concepts with `universalWasmLoader-c`), or a pure-Dart interpreter (`package:wasm`
  is Wasmer-based and effectively deprecated).

## Repository Structure

Currently a fresh repo — `README.md`, `LICENSE`, `.gitignore`, this `CLAUDE.md`, and `cmem/`. No
`pubspec.yaml`, `lib/`, or tests yet (matches the other not-yet-implemented ports).

## Conformance

Must implement the cross-language `SPEC.md`. The spec is at **v3.0.0 (2026-06-15)** — string returns
use the **canonical callee-allocated** convention (export returns an i32 pointer to a `[ptr, len]`
pair; host reads it then calls `cabi_post_<name>(retPtr)`). Build directly against 3.0.0; there is no
legacy out-parameter code to migrate. Full detail in [`cmem/overview.md`](cmem/overview.md).

## Notes

- Git safe.directory may need adding for this path when running git outside Claude Code:
  `git config --global --add safe.directory D:/Programs/_ProgramExamples/Example_Programs/GithubProjects/universalWasmLoader/universalWasmLoader-dart`
