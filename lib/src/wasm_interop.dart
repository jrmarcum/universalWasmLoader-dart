/// Minimal `dart:js_interop` bindings over the browser's native `WebAssembly`
/// API and `fetch`. Web platform only.
library;

import 'dart:js_interop';
import 'dart:typed_data';

/// The global `WebAssembly` namespace.
@JS('WebAssembly')
extension type WebAssembly._(JSObject _) implements JSObject {
  /// `WebAssembly.instantiate(bytes, imports)` — returns a `Promise` resolving
  /// to a `WebAssemblyInstantiatedSource`.
  @JS('instantiate')
  external static JSPromise<WebAssemblyInstantiatedSource> instantiate(
    JSAny bytes,
    JSObject imports,
  );
}

/// The resolved value of `WebAssembly.instantiate(bytes, imports)`.
extension type WebAssemblyInstantiatedSource._(JSObject _) implements JSObject {
  /// The instantiated module instance.
  external WasmInstance get instance;
}

/// A `WebAssembly.Instance`.
extension type WasmInstance._(JSObject _) implements JSObject {
  /// The instance's exports object (functions, memory, globals).
  external JSObject get exports;
}

/// A `WebAssembly.Memory`.
extension type WasmMemory._(JSObject _) implements JSObject {
  /// The backing `ArrayBuffer` of this memory.
  external JSArrayBuffer get buffer;
}

/// A `WebAssembly.Global` (used for the version-pin `version` global).
extension type WasmGlobal._(JSObject _) implements JSObject {
  /// The current value of the global.
  external JSAny? get value;
}

/// The browser `fetch` function.
@JS('fetch')
external JSPromise<FetchResponse> fetch(JSString url);

/// A `Response` from `fetch`.
extension type FetchResponse._(JSObject _) implements JSObject {
  /// Whether the response status is in the 2xx range.
  external bool get ok;

  /// HTTP status code.
  external int get status;

  /// Resolves to the response body as an `ArrayBuffer`.
  external JSPromise<JSArrayBuffer> arrayBuffer();

  /// Resolves to the response body as text.
  external JSPromise<JSString> text();
}

/// Reads a property off a JS object by name, returning `null` if absent.
@JS('Reflect.get')
external JSAny? _reflectGet(JSObject target, JSString key);

/// Returns export [key] from a WASM exports object, or `null` if not present.
JSAny? getExport(JSObject exports, String key) =>
    _reflectGet(exports, key.toJS);

/// Sets [key] = [value] on a JS object.
@JS('Reflect.set')
external bool jsSet(JSObject target, JSString key, JSAny? value);

/// Reads the current `Uint8List` view over a memory's buffer.
///
/// The buffer must be re-fetched after any `cabi_realloc`, since memory growth
/// can detach the previous `ArrayBuffer`.
Uint8List memoryBytes(WasmMemory memory) => memory.buffer.toDart.asUint8List();

/// Reads a little-endian i32 from [memory] at byte [offset].
int readI32(WasmMemory memory, int offset) =>
    memory.buffer.toDart.asByteData().getInt32(offset, Endian.little);
