/// WIT (WebAssembly Interface Types) parsing for the loader.
///
/// Parses the small subset of WIT that `wasmtk` emits: a `package` line and a
/// single `world { ... }` block containing `import`/`export` `func` declarations.
library;

/// A single WIT function parameter.
class WitParam {
  /// The camelCase parameter name.
  final String name;

  /// The WIT type token (`s32`, `s64`, `f32`, `f64`, `bool`, `string`).
  final String type;

  const WitParam(this.name, this.type);
}

/// A single WIT function declaration (an `import` or an `export`).
class WitFunc {
  /// The raw kebab-case WIT name (e.g. `str-len`, `env-mul`).
  final String name;

  /// The camelCase name used at the call site / for export lookup (e.g. `strLen`).
  final String tsName;

  /// The function parameters in declaration order.
  final List<WitParam> params;

  /// The result WIT type, or `null` for a void function.
  final String? result;

  const WitFunc({
    required this.name,
    required this.tsName,
    required this.params,
    required this.result,
  });
}

/// The result of [parseWit].
class ParsedWit {
  /// The `package` name (e.g. `local:math-50`), or `''` if absent.
  final String packageName;

  /// The `world` name, or `''` if absent.
  final String worldName;

  /// Functions in the WIT `import` section.
  final List<WitFunc> imports;

  /// Functions in the WIT `export` section.
  final List<WitFunc> exports;

  const ParsedWit({
    required this.packageName,
    required this.worldName,
    required this.imports,
    required this.exports,
  });
}

/// Converts a kebab-case WIT name to camelCase (e.g. `str-len` -> `strLen`).
String kebabToCamel(String name) {
  return name.replaceAllMapped(
    RegExp(r'-([a-z0-9])'),
    (m) => m[1]!.toUpperCase(),
  );
}

/// Converts a kebab-case WIT import name to the underscore WASM import key
/// (e.g. `env-mul` -> `env_mul`).
String kebabToWasmImportKey(String name) => name.replaceAll('-', '_');

String _parseWitType(String raw) {
  switch (raw.trim()) {
    case 's32':
    case 's64':
    case 'f32':
    case 'f64':
    case 'bool':
    case 'string':
      return raw.trim();
    default:
      return 's32';
  }
}

List<WitParam> _parseWitParams(String raw) {
  if (raw.trim().isEmpty) return const [];
  final out = <WitParam>[];
  for (final part in raw.split(',')) {
    final colon = part.indexOf(':');
    if (colon < 0) continue;
    final rawName = part.substring(0, colon).trim();
    final type = _parseWitType(part.substring(colon + 1));
    out.add(WitParam(kebabToCamel(rawName), type));
  }
  return out;
}

List<WitFunc> _parseWitFuncs(String body, String keyword) {
  final funcs = <WitFunc>[];
  final re = RegExp(
    '\\b$keyword\\s+([\\w-]+)\\s*:\\s*func\\s*\\(([^)]*)\\)(?:\\s*->\\s*([\\w-]+))?\\s*;',
  );
  for (final m in re.allMatches(body)) {
    final name = m[1]!;
    final params = _parseWitParams(m[2] ?? '');
    final result = m[3] != null ? _parseWitType(m[3]!) : null;
    funcs.add(WitFunc(
      name: name,
      tsName: kebabToCamel(name),
      params: params,
      result: result,
    ));
  }
  return funcs;
}

/// Parses a WIT source string produced by `wasmtk`.
ParsedWit parseWit(String src) {
  final pkgMatch = RegExp(r'package\s+([\w:/-]+)\s*;').firstMatch(src);
  final packageName = pkgMatch?[1] ?? '';

  final worldMatch =
      RegExp(r'world\s+([\w-]+)\s*\{([\s\S]*)\}').firstMatch(src);
  final worldName = worldMatch?[1] ?? '';
  final worldBody = worldMatch?[2] ?? '';

  return ParsedWit(
    packageName: packageName,
    worldName: worldName,
    imports: _parseWitFuncs(worldBody, 'import'),
    exports: _parseWitFuncs(worldBody, 'export'),
  );
}
