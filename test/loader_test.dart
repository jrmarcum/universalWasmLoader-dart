@TestOn('browser')
library;

import 'package:test/test.dart';
import 'package:universal_wasm_loader/universal_wasm_loader.dart';

// Fixtures live in test/fixtures/ and are served relative to this test file by
// the `dart test -p chrome` http server.
const _math = 'fixtures/math_50.wasm';
const _booleans = 'fixtures/booleans_50.wasm';
const _strings = 'fixtures/strings_50.wasm';
const _imports = 'fixtures/imports_50.wasm';

void main() {
  group('math_50 — numeric round-trip', () {
    test('add / multiply / square', () async {
      final m = await wasmImport(_math);
      expect(m.call('add', [3, 4]), 7);
      expect(m.call('multiply', [2.5, 4.0]), 10.0);
      expect(m.call('square', [5]), 25);
    });
  });

  group('booleans_50 — bool normalization', () {
    test('isPositive / inRange / isEven', () async {
      final m = await wasmImport(_booleans);
      expect(m.call('isPositive', [1.0]), isTrue);
      expect(m.call('isPositive', [-1.0]), isFalse);
      expect(m.call('inRange', [5.0, 0.0, 10.0]), isTrue);
      expect(m.call('inRange', [11.0, 0.0, 10.0]), isFalse);
      expect(m.call('isEven', [4]), isTrue);
      expect(m.call('isEven', [3]), isFalse);
    });
  });

  group('strings_50 — string param + return (Canonical ABI)', () {
    test('greet / shout / strLen', () async {
      final m = await wasmImport(_strings);
      expect(m.call('greet', ['World']), 'Hello, World!');
      expect(m.call('shout', ['hi']), 'hihi');
      expect(m.call('strLen', ['hello']), 5);
    });
  });

  group('imports_50 — host import callbacks', () {
    test('scale / combine', () async {
      final m = await wasmImport(_imports, hostCallbacks: {
        'envMul': (num a, num b) => a * b,
        'envAdd': (num a, num b) => a + b,
      });
      expect(m.call('scale', [3.0, 4.0]), 12.0);
      expect(m.call('combine', [10, 7]), 17);
    });
  });

  group('instance lifecycle', () {
    test('createSingleton returns the same instance', () async {
      final getMod = createSingleton(_math);
      final a = await getMod();
      final b = await getMod();
      expect(identical(a, b), isTrue);
      expect(a.call('add', [1, 2]), 3);
    });

    test('InstancePool.run returns the correct result', () async {
      final pool = InstancePool(_math, size: 2);
      final result = await pool.run((mod) => mod.call('square', [6]));
      expect(result, 36);
    });

    test('InstancePool with size=2 handles 2 concurrent run() calls', () async {
      final pool = InstancePool(_math, size: 2);
      final results = await Future.wait([
        pool.run((mod) => mod.call('add', [10, 1]) as int),
        pool.run((mod) => mod.call('add', [20, 2]) as int),
      ]);
      expect(results, containsAll([11, 22]));
    });
  });
}
