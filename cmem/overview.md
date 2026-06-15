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

## Release flow (implemented 2026-06-15)

**Version source:** `pubspec.yaml` (`version:`) is the single source of truth.

**Bump → tag → push:**

1. `dart run scripts/bump.dart [patch|minor|major]` (default `patch`) — or the pure-POSIX
   `scripts/bump.sh` — raises the `version:` line with a targeted edit (rest of the file untouched).
   Mirrors `-js`'s `scripts/bump.ts` UX.
2. `scripts/release.sh` — commits a pending pubspec bump, tags `vX.Y.Z` from the current
   `pubspec.yaml` version, and pushes the tag. It NEVER runs `dart pub publish` locally (mirrors
   `-js`'s `scripts/publish.ts`, which only tags + pushes so CI publishes).
3. The pushed `v*` tag triggers `.github/workflows/publish.yml`, which publishes to pub.dev.

**`.github/workflows/publish.yml` — `run:`-only (org Actions policy).** This org permits only
`jrmarcum`-owned actions; ANY third-party `uses:` step (incl. `actions/checkout`, `dart-lang/setup-dart`,
and the official `dart-lang/setup-dart/.github/workflows/publish.yml` reusable OIDC workflow) causes a
`startup_failure` — nothing runs. So every step is a plain `run:` step:
- checkout via `git clone --depth=1 --branch <tag> https://x-access-token:<token>@github.com/<repo> .`
- install the Dart SDK from the official Dart apt repo (`/usr/lib/dart/bin` → `$GITHUB_PATH`)
- `dart pub get`, `dart analyze`, best-effort `dart test -p chrome` (web-only package; skipped with a
  logged `::warning::` if no Chrome on the runner — does not block publish)
- write the `PUB_DEV_CREDENTIALS` secret to `pub-credentials.json` (in `$HOME/.config/dart/`,
  `$XDG_CONFIG_HOME/dart/` if set, and `$HOME/.pub-cache/credentials.json` for older SDKs), then
  `dart pub publish --force`
- `gh release create` for the tag

**Why credentials-file, not OIDC:** the official pub.dev automated-publishing path is the
`dart-lang/setup-dart/.github/workflows/publish.yml` reusable workflow — a third-party `uses:`,
forbidden by org policy. So we use a credentials-file publish in `run:` steps instead.

### Required owner setup (one-time)

1. **Own the package on pub.dev.** The package name `universal_wasm_loader` must be created/owned by
   the publishing account (a verified publisher is recommended if used). First publish of a brand-new
   name will create it under your account.
2. **Generate the `PUB_DEV_CREDENTIALS` secret.** Locally run `dart pub login` and complete the
   Google OAuth flow. This writes `pub-credentials.json` to Dart's config dir:
   - Linux: `$XDG_CONFIG_HOME/dart/pub-credentials.json` (or `~/.config/dart/pub-credentials.json`)
   - Windows: `%APPDATA%\dart\pub-credentials.json`
   - macOS: `~/Library/Application Support/dart/pub-credentials.json`
   Copy the FULL JSON contents of that file into a GitHub repo secret named **`PUB_DEV_CREDENTIALS`**
   (Settings → Secrets and variables → Actions → New repository secret). It contains a refresh token,
   so treat it as sensitive; rotate by re-running `dart pub login` and updating the secret.

### Validation (no publish performed)

`dart pub publish --dry-run` (Dart 3.12.2) validates the package without uploading: **0 warnings,
exit 0** after `CHANGELOG.md` was added. Both bump scripts verified for patch/minor/major + bad-kind
rejection, leaving `pubspec.yaml` at `0.1.0`. No real publish and no push were performed.
