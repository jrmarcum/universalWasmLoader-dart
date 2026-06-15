/// The public loader API: [wasmImport], [createSingleton], and [InstancePool].
///
/// Web platform only — uses the browser's native `WebAssembly` and `fetch` via
/// `dart:js_interop`.
library;

import 'dart:async';
import 'dart:js_interop';

import 'abi.dart';
import 'wasm_interop.dart';
import 'wit_parser.dart';

class _VersionSuffix {
  final String cleanPath;
  final int? requestedVersion;
  const _VersionSuffix(this.cleanPath, this.requestedVersion);
}

_VersionSuffix _parseVersionSuffix(String wasmPath) {
  final atIdx = wasmPath.lastIndexOf('@');
  if (atIdx != -1) {
    final suffix = wasmPath.substring(atIdx + 1);
    if (RegExp(r'^\d+$').hasMatch(suffix)) {
      return _VersionSuffix(wasmPath.substring(0, atIdx), int.parse(suffix));
    }
  }
  return _VersionSuffix(wasmPath, null);
}

void _assertVersion(
    JSObject rawExports, int requestedVersion, String wasmPath) {
  final versionJs = getExport(rawExports, 'version');
  final global = versionJs == null ? null : versionJs as WasmGlobal;
  final value = global?.value;
  if (global == null || value == null || !value.isA<JSNumber>()) {
    throw StateError(
        'wasmImport: version @$requestedVersion requested for "$wasmPath" but '
        'the module does not export a "version" global');
  }
  final actual = (value as JSNumber).toDartInt;
  if (actual != requestedVersion) {
    throw StateError('wasmImport: version mismatch for "$wasmPath" — requested '
        '@$requestedVersion, module exports version $actual');
  }
}

Future<JSObject> _instantiate(String url, JSObject imports) async {
  final res = await fetch(url.toJS).toDart;
  if (!res.ok) {
    throw StateError('wasmImport: failed to fetch "$url" (HTTP ${res.status})');
  }
  final buffer = await res.arrayBuffer().toDart;
  final source = await WebAssembly.instantiate(buffer, imports).toDart;
  return source.instance.exports;
}

/// Instantiates the `.wasm` at [wasmPath], returning a typed [ModuleExports]
/// handle.
///
/// Auto-detects the companion `.wit` (replace `.wasm` -> `.wit`, fetch) and
/// applies the Canonical ABI. If no `.wit` is found, the raw exports are wrapped
/// with no translation. An optional `@N` suffix pins to the module's exported
/// `version` global (see SPEC §3).
///
/// [hostCallbacks] supplies host import functions keyed by camelCase WIT name
/// (e.g. `envMul`).
///
/// TODO (SPEC §10): `_initialize` and a WASI-P1 shim are optional and not yet
/// implemented; the reference fixtures need neither.
Future<ModuleExports> wasmImport(
  String wasmPath, {
  Map<String, Function> hostCallbacks = const {},
}) async {
  final parsed = _parseVersionSuffix(wasmPath);
  final cleanPath = parsed.cleanPath;
  final requestedVersion = parsed.requestedVersion;

  // Attempt WIT auto-detection; fall back to raw exports if absent.
  final witUrl = cleanPath.replaceFirst(RegExp(r'\.wasm$'), '.wit');
  String? witSrc;
  try {
    final res = await fetch(witUrl.toJS).toDart;
    if (res.ok) witSrc = (await res.text().toDart).toDart;
  } catch (_) {
    // no WIT file available
  }

  if (witSrc == null) {
    final rawExports = await _instantiate(cleanPath, JSObject());
    if (requestedVersion != null) {
      _assertVersion(rawExports, requestedVersion, cleanPath);
    }
    // No WIT: expose raw exports with no ABI translation (empty func table).
    return buildComponentExportProxy(const [], rawExports);
  }

  final parsedWit = parseWit(witSrc);
  final importEnv = buildComponentImportEnv(parsedWit.imports, hostCallbacks);

  final imports = JSObject();
  if (parsedWit.imports.isNotEmpty) {
    jsSet(imports, 'env'.toJS, importEnv.env);
  }

  final rawExports = await _instantiate(cleanPath, imports);
  final memJs = getExport(rawExports, 'memory');
  if (memJs != null) {
    importEnv.memRef.current = memJs as WasmMemory;
  }
  if (requestedVersion != null) {
    _assertVersion(rawExports, requestedVersion, cleanPath);
  }
  return buildComponentExportProxy(parsedWit.exports, rawExports);
}

/// Creates a singleton accessor that loads the WASM instance on the first call
/// and caches the load. Subsequent calls return the same future/instance.
///
/// Appropriate for CLI tools and bounded-call scenarios (SPEC §6.1).
Future<ModuleExports> Function() createSingleton(
  String wasmPath, {
  Map<String, Function> hostCallbacks = const {},
}) {
  Future<ModuleExports>? cached;
  return () {
    cached ??= wasmImport(wasmPath, hostCallbacks: hostCallbacks);
    return cached!;
  };
}

/// A pool of pre-instantiated WASM instances for concurrent or high-throughput
/// scenarios (SPEC §6.2).
///
/// Manages acquire/release semantics so no two concurrent callers share the
/// same instance. Use [run] for an atomic checkout-call-release pattern.
class InstancePool {
  final String _wasmPath;
  final Map<String, Function> _hostCallbacks;
  final int _size;

  Future<void>? _initFuture;
  final List<ModuleExports> _available = [];
  final List<Completer<ModuleExports>> _waiters = [];

  /// Creates a pool of [size] (default 4) independent instances of the module
  /// at [wasmPath]. Instances are lazily created on first [acquire]/[run].
  InstancePool(
    this._wasmPath, {
    Map<String, Function> hostCallbacks = const {},
    int size = 4,
  })  : _hostCallbacks = hostCallbacks,
        _size = size;

  /// Total pool capacity.
  int get size => _size;

  /// The number of currently-idle instances.
  int get available => _available.length;

  Future<void> _ensureInit() {
    return _initFuture ??= Future(() async {
      final instances = await Future.wait(List.generate(
        _size,
        (_) => wasmImport(_wasmPath, hostCallbacks: _hostCallbacks),
      ));
      _available.addAll(instances);
    });
  }

  /// Acquires an available instance, waiting if all are in use.
  Future<ModuleExports> acquire() async {
    await _ensureInit();
    if (_available.isNotEmpty) {
      return _available.removeLast();
    }
    final completer = Completer<ModuleExports>();
    _waiters.add(completer);
    return completer.future;
  }

  /// Releases [instance] back to the pool, handing it to a waiter if present.
  void release(ModuleExports instance) {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete(instance);
    } else {
      _available.add(instance);
    }
  }

  /// Atomically acquires an instance, runs [fn] with it, then releases it —
  /// even if [fn] throws.
  Future<T> run<T>(FutureOr<T> Function(ModuleExports instance) fn) async {
    final instance = await acquire();
    try {
      return await fn(instance);
    } finally {
      release(instance);
    }
  }
}
