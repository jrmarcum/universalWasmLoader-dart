# Overview — universalWasmLoader-dart

The **Dart** port of the Universal WASM Loader (Stage 2 of the polyglot loader ecosystem; the JS/TS
`universalWasmLoader-js` is the reference, and `SPEC.md` is the cross-language contract). Intended to
publish to **pub.dev**.

## Status — fresh stub (created 2026-06-15)

The repo was just initialized: `README.md`, `LICENSE` (MIT, Jon Marcum), `.gitignore` (Dart), this
`cmem/`, and a `CLAUDE.md`. **No `pubspec.yaml`, no `lib/` source, no tests yet.** Nothing is
implemented — this file records the intended shape so a future session can build it correctly the
first time.

## Intended API surface

Mirror the reference loader in idiomatic Dart (final names TBD):
- `wasmImport(path, {hostCallbacks})` → a future/`Future` resolving to a typed module handle; auto-detect
  the companion `.wit`, apply the Canonical ABI, fall back to raw exports if no `.wit`. Support the
  `@N` version-pin suffix (checked against the module's exported `version` global).
- `createSingleton(path, {hostCallbacks})` — caches the load; same instance every call.
- `InstancePool(path, {hostCallbacks, size})` — `acquire` / `release` / `run` over N instances.

## WASM runtime — OPEN decision (decide before implementing)

Dart has no single canonical WASM host:
- **Web / Flutter web:** `dart:js_interop` over the browser's native `WebAssembly`.
- **Native (Dart VM):** `dart:ffi` to a C wasm runtime (e.g. the wasmtime C API — would share
  marshalling with `universalWasmLoader-c`), or a pure-Dart interpreter. `package:wasm` (Wasmer-based)
  is effectively deprecated — avoid.

A web-first implementation is likely the cheapest path (no native build step).

## Conformance — build against SPEC 3.0.0 directly

`SPEC.md` (cross-language) is at **v3.0.0 (2026-06-15)**. String/aggregate RETURNS use the **canonical
callee-allocated** convention: the export returns an i32 pointer to a callee-allocated `[ptr, len]`
pair; the host reads the little-endian pair, decodes UTF-8, then calls the paired
**`cabi_post_<name>(retPtr)`** export to release it. String PARAMS flatten to `(ptr, len)` written via
`cabi_realloc(0,0,1,len)`. Numerics pass through; `bool` is `1/0` ↔ `true/false`. Implement the NEW
convention from the start — there is **no legacy out-parameter code to migrate** here.

## Tests

`dart test`, against the same fixtures `wasmtk` produces and the reference suite uses
(`math_50` / `booleans_50` / `strings_50` / `imports_50`) plus the lifecycle scenarios
(`createSingleton`, `InstancePool`). `strings_50.wasm` exercises the canonical return path.

## Release flow (planned)

Version lives in `pubspec.yaml` (`version:`). Bump it, then publish to pub.dev via `dart pub publish`
(dry-run with `dart pub publish --dry-run` first). A GitHub Action equivalent of the other ports can
tag `vX.Y.Z` and publish. See the per-language publishing matrix in the wasmtk `cmem/vision.md`.
