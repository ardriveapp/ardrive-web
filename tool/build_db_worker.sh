#!/usr/bin/env bash
#
# Compiles the web database worker (web/db_worker.dart) to JavaScript.
#
#   tool/build_db_worker.sh [output]
#
# The output defaults to web/db_worker.js, which `flutter run -d chrome` and
# `flutter build web` both pick up from web/. Without it the app opens its
# database on IndexedDB instead. See docs/WEB_DATABASE.md.
#
# Set DART to use a Dart other than the one on PATH.

set -euo pipefail
cd "$(dirname "$0")/.."

DART="${DART:-dart}"
OUT="${1:-web/db_worker.js}"

"$DART" compile js -O4 --no-source-maps -o "$OUT" web/db_worker.dart
# dart2js also writes a .deps file nobody serves.
rm -f "$OUT.deps"
