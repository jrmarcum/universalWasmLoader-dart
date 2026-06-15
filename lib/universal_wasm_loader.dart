/// Web-first Dart loader for WebAssembly "DLL" modules.
///
/// Auto-detects the companion `.wit`, applies the Canonical ABI (wasmtime
/// profile), and returns a typed [ModuleExports] handle. Implements the
/// cross-language `SPEC.md` v3.0.0 over the browser's native `WebAssembly` API
/// via `dart:js_interop`.
///
/// ```dart
/// final m = await wasmImport('math_50.wasm');
/// print(m.call('add', [3, 4])); // 7
/// ```
library;

export 'src/loader.dart' show wasmImport, createSingleton, InstancePool;
export 'src/abi.dart' show ModuleExports;
export 'src/wit_parser.dart'
    show
        parseWit,
        ParsedWit,
        WitFunc,
        WitParam,
        kebabToCamel,
        kebabToWasmImportKey;
