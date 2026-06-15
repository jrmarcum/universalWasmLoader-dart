# Changelog

## 0.1.0

- Initial release. Web-first Dart port of the Universal WASM Loader, implementing
  cross-language `SPEC.md` v3.0.0 over the browser `WebAssembly` API via
  `dart:js_interop`.
- `wasmImport`, `createSingleton`, `InstancePool`; WIT auto-detection; the `@N`
  version pin; full Canonical ABI (numerics pass-through, `bool` 1/0 ↔ true/false,
  string params via `cabi_realloc`, callee-allocated string returns +
  `cabi_post_<name>` release).
