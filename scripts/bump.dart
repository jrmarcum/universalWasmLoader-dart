// Raises the `version:` field in pubspec.yaml (the single version source).
//
// Run via:  dart run scripts/bump.dart           # patch:  0.1.0 → 0.1.1
//           dart run scripts/bump.dart minor      # minor:  0.1.0 → 0.2.0
//           dart run scripts/bump.dart major      # major:  0.1.0 → 1.0.0
//
// Mirrors the `-js` reference's `scripts/bump.ts`: a targeted single-line edit
// so the rest of pubspec.yaml's formatting is untouched. Must be run from the
// project root.

import 'dart:io';

void main(List<String> args) {
  final kind = (args.isEmpty ? 'patch' : args[0]).toLowerCase();
  if (kind != 'patch' && kind != 'minor' && kind != 'major') {
    stderr.writeln(
      '❌ bump: unknown release kind "$kind" — use patch | minor | major',
    );
    exit(1);
  }

  final file = File('pubspec.yaml');
  if (!file.existsSync()) {
    stderr.writeln(
      '❌ bump: pubspec.yaml not found — run from the project root.',
    );
    exit(1);
  }

  final text = file.readAsStringSync();
  // Match a top-level `version: X.Y.Z` line (no quotes, YAML style).
  final re = RegExp(r'^(version:\s*)(\d+)\.(\d+)\.(\d+)\s*$', multiLine: true);
  final m = re.firstMatch(text);
  if (m == null) {
    stderr.writeln(
      '❌ bump: could not find a `version: X.Y.Z` line in pubspec.yaml',
    );
    exit(1);
  }

  var major = int.parse(m.group(2)!);
  var minor = int.parse(m.group(3)!);
  var patch = int.parse(m.group(4)!);
  final from = '$major.$minor.$patch';

  switch (kind) {
    case 'major':
      major += 1;
      minor = 0;
      patch = 0;
    case 'minor':
      minor += 1;
      patch = 0;
    default:
      patch += 1;
  }
  final to = '$major.$minor.$patch';

  final updated = text.replaceFirst(re, '${m.group(1)}$to');
  file.writeAsStringSync(updated);
  print('✅ pubspec.yaml  → $to  ($kind bump from $from)');
}
