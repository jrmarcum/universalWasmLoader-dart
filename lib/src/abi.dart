/// Canonical ABI (wasmtime profile) translation between Dart and WASM.
///
/// Mirrors the behavior of the reference loader's `abi.js`: numerics pass
/// through, `bool` maps to `1/0` <-> `true/false`, and `string` flattens to a
/// `(ptr, len)` pair using `cabi_realloc` (params) / callee-allocated returns
/// with `cabi_post_<name>` (returns).
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'wasm_interop.dart';
import 'wit_parser.dart';

/// A mutable reference to the active WASM linear memory.
///
/// Set [current] to `instance.exports.memory` after instantiation so that
/// string-param host imports can decode from linear memory.
class MemRef {
  /// The active memory, or `null` before instantiation / for memory-less modules.
  WasmMemory? current;
}

/// The `env` import object plus its [MemRef], built from the WIT `import` list.
class ImportEnv {
  /// The JS object to register under the `env` namespace at instantiation.
  final JSObject env;

  /// The memory reference shared with string-param import wrappers.
  final MemRef memRef;

  const ImportEnv(this.env, this.memRef);
}

dynamic _asDartNum(JSAny? v) {
  if (v == null) return null;
  if (v.isA<JSNumber>()) {
    final n = (v as JSNumber).toDartDouble;
    // Preserve integer-ness for whole numbers (s32/s64 round-trip).
    return n == n.truncateToDouble() ? n.toInt() : n;
  }
  return v;
}

JSAny? _toJsArg(dynamic v) {
  if (v is bool) return (v ? 1 : 0).toJS;
  if (v is int) return v.toJS;
  if (v is double) return v.toJS;
  return v as JSAny?;
}

/// Builds the WASM `env` import object for the Canonical ABI (wasmtime) profile.
///
/// [userCallbacks] is keyed by the camelCase WIT name (e.g. `envMul`); the WASM
/// import key is the underscore form (e.g. `env_mul`).
ImportEnv buildComponentImportEnv(
  List<WitFunc> importFuncs,
  Map<String, Function> userCallbacks,
) {
  final memRef = MemRef();
  final env = JSObject();
  final dec = const Utf8Decoder();

  for (final fn in importFuncs) {
    final wasmKey = kebabToWasmImportKey(fn.name);
    final cb = userCallbacks[fn.tsName];
    final params = fn.params;

    // The WASM module calls each import with the *flattened* ABI arity (strings
    // expand to a (ptr,len) pair). The closure passed to `.toJS` must therefore
    // accept that exact number of positional args; the dart2js interop
    // trampoline matches arity strictly. We build a wrapper of the right arity
    // by making every slot an optional positional parameter and ignoring the
    // unused tail.
    JSAny? handle(List<JSAny?> raw) {
      final jsArgs = <dynamic>[];
      var i = 0;
      for (final p in params) {
        if (p.type == 'string') {
          final bytes = memoryBytes(memRef.current!);
          final ptr = (raw[i++] as JSNumber).toDartInt;
          final len = (raw[i++] as JSNumber).toDartInt;
          jsArgs.add(dec.convert(bytes.sublist(ptr, ptr + len)));
        } else if (p.type == 'bool') {
          jsArgs.add((raw[i++] as JSNumber).toDartInt != 0);
        } else {
          jsArgs.add(_asDartNum(raw[i++]));
        }
      }
      return _applyCallback(cb, jsArgs, fn.result);
    }

    JSAny? wrapper([
      JSAny? a0,
      JSAny? a1,
      JSAny? a2,
      JSAny? a3,
      JSAny? a4,
      JSAny? a5,
      JSAny? a6,
      JSAny? a7,
    ]) =>
        handle([a0, a1, a2, a3, a4, a5, a6, a7]);

    jsSet(env, wasmKey.toJS, wrapper.toJS);
  }

  return ImportEnv(env, memRef);
}

JSAny? _applyCallback(Function? cb, List<dynamic> jsArgs, String? result) {
  if (cb == null) return result != null ? 0.toJS : null;
  final ret = Function.apply(cb, jsArgs);
  if (result == 'bool') return ((ret == true) ? 1 : 0).toJS;
  if (ret == null) return result != null ? 0.toJS : null;
  return _toJsArg(ret);
}

/// A typed handle over raw WASM exports — a map from camelCase export name to a
/// Dart callable applying the Canonical ABI. Also usable as a namespace via
/// [call] (e.g. `mod('greet', ['World'])`) or [function].
class ModuleExports {
  final Map<String, Function> _fns;

  /// The raw `WebAssembly.Instance.exports` object (escape hatch).
  final JSObject rawExports;

  ModuleExports._(this._fns, this.rawExports);

  /// The camelCase export names this handle exposes.
  Iterable<String> get names => _fns.keys;

  /// Whether an export named [name] exists.
  bool has(String name) => _fns.containsKey(name);

  /// Returns the wrapped callable for [name], or `null` if absent.
  Function? function(String name) => _fns[name];

  /// Invokes export [name] with positional [args], applying ABI translation.
  dynamic call(String name, [List<dynamic> args = const []]) {
    final fn = _fns[name];
    if (fn == null) {
      throw ArgumentError('export "$name" not found');
    }
    return Function.apply(fn, args);
  }
}

/// Builds a [ModuleExports] handle over [rawExports] using the Canonical ABI.
///
/// Requires the WASM module to export `cabi_realloc` and `memory` when string
/// types are used.
ModuleExports buildComponentExportProxy(
  List<WitFunc> exportFuncs,
  JSObject rawExports,
) {
  final enc = const Utf8Encoder();
  final dec = const Utf8Decoder();

  final memJs = getExport(rawExports, 'memory');
  final memory = memJs == null ? null : memJs as WasmMemory;
  final reallocJs = getExport(rawExports, 'cabi_realloc');
  final cabiRealloc = reallocJs == null ? null : reallocJs as JSFunction;

  final fns = <String, Function>{};

  for (final fn in exportFuncs) {
    final wasmFnJs = getExport(rawExports, fn.tsName);
    if (wasmFnJs == null) continue;
    final wasmFn = wasmFnJs as JSFunction;
    final postJs = getExport(rawExports, 'cabi_post_${fn.tsName}');
    final post = postJs == null ? null : postJs as JSFunction;

    fns[fn.tsName] = ([
      dynamic a0,
      dynamic a1,
      dynamic a2,
      dynamic a3,
      dynamic a4,
      dynamic a5,
    ]) {
      final jsArgs = <dynamic>[a0, a1, a2, a3, a4, a5];
      final wasmArgs = <JSAny?>[];

      for (var i = 0; i < fn.params.length; i++) {
        final p = fn.params[i];
        final v = jsArgs[i];
        if (p.type == 'string') {
          final bytes = enc.convert(v.toString());
          final ptr = (cabiRealloc!.callAsFunction(
                  null, 0.toJS, 0.toJS, 1.toJS, bytes.length.toJS) as JSNumber)
              .toDartInt;
          memoryBytes(memory!).setRange(ptr, ptr + bytes.length, bytes);
          wasmArgs.add(ptr.toJS);
          wasmArgs.add(bytes.length.toJS);
        } else if (p.type == 'bool') {
          wasmArgs.add((v == true ? 1 : 0).toJS);
        } else {
          wasmArgs.add(_toJsArg(v));
        }
      }

      if (fn.result == 'string') {
        // Canonical ABI callee-allocated return: the export returns an i32
        // pointer to a callee-allocated [ptr, len] pair. Read it, decode (which
        // copies the bytes), then call cabi_post_<name> to release the buffer.
        final retArea = (_invoke(wasmFn, wasmArgs) as JSNumber).toDartInt;
        final retPtr = readI32(memory!, retArea);
        final retLen = readI32(memory, retArea + 4);
        final bytes = memoryBytes(memory);
        final str = dec.convert(
            Uint8List.fromList(bytes.sublist(retPtr, retPtr + retLen)));
        if (post != null) {
          post.callAsFunction(null, retArea.toJS);
        }
        return str;
      }

      final raw = _invoke(wasmFn, wasmArgs);
      if (fn.result == null) return null;
      if (fn.result == 'bool') return (raw as JSNumber).toDartInt != 0;
      return _asDartNum(raw);
    };
  }

  return ModuleExports._(fns, rawExports);
}

/// Calls [fn] with an arbitrary number of positional arguments via
/// `Function.prototype.apply` (`callAsFunction` is fixed-arity at 4).
@JS('Function.prototype.apply.call')
external JSAny? _applyJs(JSFunction fn, JSAny? thisArg, JSArray<JSAny?> args);

JSAny? _invoke(JSFunction fn, List<JSAny?> args) =>
    _applyJs(fn, null, args.toJS);
