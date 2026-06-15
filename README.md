# universalWasmLoader-dart

Universal WASM loader for Dart — the Dart port of the
[Universal WASM Loader](https://github.com/jrmarcum/universalWasmLoader), implementing the
cross-language `SPEC.md` **v3.0.0**.

Load a WebAssembly "DLL" the way the reference loader does: auto-detect the companion `.wit`, apply
the Canonical ABI (wasmtime profile), and get back a typed handle.

> **Web-only.** This package targets the **browser** (and Flutter web): it uses
> `dart:js_interop` over the browser's native `WebAssembly` and `fetch`. There is no Dart-VM /
> native runtime yet (see *Runtime* below).

## Usage

```dart
import 'package:universal_wasm_loader/universal_wasm_loader.dart';

Future<void> main() async {
  // Auto-detects ./math_50.wit, applies the Canonical ABI.
  final m = await wasmImport('math_50.wasm');
  print(m.call('add', [3, 4]));        // 7
  print(m.call('multiply', [2.5, 4])); // 10.0

  // Strings (Canonical ABI: cabi_realloc params, callee-allocated returns).
  final s = await wasmImport('strings_50.wasm');
  print(s.call('greet', ['World']));   // "Hello, World!"

  // Host import callbacks, keyed by camelCase WIT name.
  final i = await wasmImport('imports_50.wasm', hostCallbacks: {
    'envMul': (num a, num b) => a * b,
    'envAdd': (num a, num b) => a + b,
  });
  print(i.call('scale', [3.0, 4.0]));  // 12.0

  // Version pinning (SPEC §3): ./mod.wasm@2 checks the module's `version` global.
  // final v = await wasmImport('mod.wasm@2');
}
```

### Instance lifecycle

```dart
// Singleton — loads once, caches (CLI / bounded-call scenarios).
final getMod = createSingleton('math_50.wasm');
final a = await getMod();
final b = await getMod(); // same instance

// Pool — N independent instances for concurrency.
final pool = InstancePool('math_50.wasm', size: 4);
final result = await pool.run((mod) => mod.call('square', [6])); // 36
```

`ModuleExports` exposes `call(name, [args])`, `function(name)`, `has(name)`, `names`, and the raw
`rawExports` escape hatch.

## Runtime

Implemented against the browser `WebAssembly` API via `dart:js_interop`. A native Dart-VM backend
(e.g. wasmtime via `dart:ffi`) is a possible follow-up but is not part of this package.

Not implemented (SPEC §10, optional in v3.0.0): the `_initialize` reactor call and the WASI-P1 shim.
The four reference fixtures need neither.

## Testing

```bash
dart pub get
dart analyze
dart test -p chrome   # requires a Chrome/Chromium browser
```

Tests run against the `wasmtk` reference fixtures (`math_50`, `booleans_50`, `strings_50`,
`imports_50`) in `test/fixtures/`, covering the SPEC §8 suite plus the lifecycle scenarios.
