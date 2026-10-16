#!/usr/bin/env bash
#
# web/sqlite3.wasm must match the resolved `sqlite3` package, or the web build
# dies at startup with a LinkError naming a missing import and nothing useful
# about why.
#
# Not hypothetical. The copy this repository carried before was built against a
# different ABI and failed with
#
#   LinkError: Import #0 "dart" "fs_delete": function import requires a callable
#
# It went unnoticed because nothing referenced it. Now something does, so a
# `flutter pub upgrade` that moves `sqlite3` would break the web build silently
# until somebody opened it in a browser.

set -euo pipefail
cd "$(dirname "$0")/.."

wasm="web/sqlite3.wasm"
version="$(awk '/^  sqlite3:$/{f=1} f&&/version:/{gsub(/"/,"",$2); print $2; exit}' pubspec.lock)"

if [ -z "$version" ]; then
  echo "could not read the sqlite3 version from pubspec.lock" >&2
  exit 1
fi
if [ ! -s "$wasm" ]; then
  echo "$wasm is missing" >&2
  exit 1
fi

expected="$(mktemp)"
trap 'rm -f "$expected"' EXIT
url="https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-$version/sqlite3.wasm"

if ! curl -fsSL -o "$expected" "$url"; then
  echo "could not fetch $url to compare against $wasm" >&2
  echo "(offline? re-run with network, or update the asset by hand)" >&2
  exit 1
fi

if cmp -s "$wasm" "$expected"; then
  echo "ok: $wasm matches sqlite3 $version"
else
  echo >&2
  echo "$wasm does not match sqlite3 $version." >&2
  echo "The web build will fail at startup. Update it with:" >&2
  echo "  curl -fsSL -o $wasm $url" >&2
  exit 1
fi
