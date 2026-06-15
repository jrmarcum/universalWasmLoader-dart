#!/usr/bin/env bash
# Raises the `version:` field in pubspec.yaml (the single version source).
#
#   scripts/bump.sh          # patch:  0.1.0 → 0.1.1
#   scripts/bump.sh minor    # minor:  0.1.0 → 0.2.0
#   scripts/bump.sh major    # major:  0.1.0 → 1.0.0
#
# A pure-POSIX alternative to `dart run scripts/bump.dart` (no Dart VM startup).
# Does a targeted single-line edit so the rest of pubspec.yaml is untouched.
set -euo pipefail

kind="${1:-patch}"
case "$kind" in
  patch | minor | major) ;;
  *)
    echo "❌ bump: unknown release kind \"$kind\" — use patch | minor | major" >&2
    exit 1
    ;;
esac

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pubspec="$root/pubspec.yaml"
[ -f "$pubspec" ] || { echo "❌ bump: pubspec.yaml not found" >&2; exit 1; }

cur="$(grep -E '^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+' "$pubspec" \
  | head -n1 | sed -E 's/^version:[[:space:]]*//' | tr -d '[:space:]')"
[ -n "$cur" ] || { echo "❌ bump: could not find a 'version: X.Y.Z' line" >&2; exit 1; }

IFS='.' read -r major minor patch <<<"$cur"
case "$kind" in
  major) major=$((major + 1)); minor=0; patch=0 ;;
  minor) minor=$((minor + 1)); patch=0 ;;
  patch) patch=$((patch + 1)) ;;
esac
to="$major.$minor.$patch"

# Portable in-place edit (works on both GNU and BSD sed via a temp file).
tmp="$(mktemp)"
sed -E "s/^(version:[[:space:]]*)[0-9]+\.[0-9]+\.[0-9]+.*$/\1$to/" "$pubspec" >"$tmp"
mv "$tmp" "$pubspec"
echo "✅ pubspec.yaml  → $to  ($kind bump from $cur)"
