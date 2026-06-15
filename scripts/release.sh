#!/usr/bin/env bash
# Tags vX.Y.Z from the current pubspec.yaml version and pushes the tag, which
# triggers .github/workflows/publish.yml to publish to pub.dev.
#
# Mirrors the `-js` reference's `scripts/publish.ts`: this NEVER runs
# `dart pub publish` locally — it only tags + pushes so CI does the publish.
#
#   scripts/release.sh        # commit any pending pubspec bump, tag, push
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

version="$(grep -E '^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+' pubspec.yaml \
  | head -n1 | sed -E 's/^version:[[:space:]]*//' | tr -d '[:space:]')"
[ -n "$version" ] || { echo "❌ release: no 'version:' in pubspec.yaml" >&2; exit 1; }
tag="v$version"

echo "Releasing $tag via GitHub Actions…"

# Commit a pending pubspec.yaml version change, if any.
if ! git diff --quiet -- pubspec.yaml; then
  git add pubspec.yaml
  git commit -m "bump version to $tag"
fi

git tag -f "$tag"
git push
git push -f origin "$tag"

echo ""
echo "Tag $tag pushed. GitHub Actions (publish.yml) will publish to pub.dev."
