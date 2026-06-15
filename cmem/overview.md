# Overview — universalWasmLoader-dart

The **Dart** port of the Universal WASM Loader (Stage 2 of the polyglot loader ecosystem; the JS/TS
`universalWasmLoader-js` is the reference, and `SPEC.md` is the cross-language contract). Intended to
publish to **pub.dev**.

## Status — implemented, web-first (2026-06-15)

Implemented against **SPEC 3.0.0** as a **web-only** package using `dart:js_interop` over the
browser's native `WebAssembly` + `fetch`. All of `wasmImport` / `createSingleton` / `InstancePool`,
WIT auto-detection, the `@N` version pin, and the full Canonical ABI (numerics pass-through; `bool`
1/0 ↔ true/false; string params via `cabi_realloc(0,0,1,len)`; string returns via the
callee-allocated `[ptr,len]` pair + `cabi_post_<name>` release) are in place.

### Runtime decision — RESOLVED: web-first via `dart:js_interop`

The OPEN runtime decision is resolved in favor of the **web** path (browser `WebAssembly`), the
cheapest implementation with no native build step. A native Dart-VM backend (wasmtime via
`dart:ffi`) remains a possible future addition but is out of scope here.

### File layout

- `pubspec.yaml` — package `universal_wasm_loader`, version `0.1.0`, SDK `^3.4.0`; deps `web`,
  dev-deps `test` + `lints`.
- `analysis_options.yaml` — `package:lints/recommended` + `strict-casts`.
- `lib/universal_wasm_loader.dart` — public barrel (exports `wasmImport`, `createSingleton`,
  `InstancePool`, `ModuleExports`, the WIT parser surface).
- `lib/src/wit_parser.dart` — `parseWit` + `WitFunc`/`WitParam`/`ParsedWit` + kebab helpers.
- `lib/src/wasm_interop.dart` — `@JS` bindings for `WebAssembly.instantiate`, `fetch`,
  `Reflect.get/set`, memory views (`memoryBytes`, `readI32`).
- `lib/src/abi.dart` — `buildComponentImportEnv` / `buildComponentExportProxy` + the `ModuleExports`
  handle (`call`/`function`/`has`/`names`/`rawExports`).
- `lib/src/loader.dart` — `wasmImport`, `createSingleton`, `InstancePool`, version-suffix parsing,
  version-global assertion.
- `test/loader_test.dart` (`@TestOn('browser')`) + `test/fixtures/*.{wasm,wit}` (the four
  `*_50` reference fixtures).

### Verification level — `dart analyze` clean + browser tests PASS

Dart SDK 3.12.2 (bundled in the scoop Flutter 3.44.2 install). `dart analyze` → **No issues found**;
`dart format .` clean. **`dart test -p chrome` ran in real Chrome and all 7 tests passed** (math,
booleans, strings incl. the Canonical string return, imports with host callbacks, `createSingleton`
identity, `InstancePool.run`, 2 concurrent pooled runs).

### Key js_interop note (gotcha)

WASM calls each `env` import with the **flattened ABI arity** (a `string` param is two i32s). The
Dart closure handed to `.toJS` must tolerate that exact count — a fixed-arity closure throws
`NoSuchMethodError` when invoked with fewer args. The import wrappers use **optional positional
params** (8 slots) so any arity 0..8 is accepted. Export calls use `Function.prototype.apply`
(bound via `@JS('Function.prototype.apply.call')`) to pass an arbitrary arg count, since
`callAsFunction` is fixed at 4.

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
