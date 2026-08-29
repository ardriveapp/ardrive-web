#!/usr/bin/env bash
#
# Runs the D12 ATTACH prototype on both platforms.
#
#   tool/drive_state_prototype.sh
#
# The browser half needs `sqlite3.wasm` served with CORS, because
# `flutter test --platform chrome` serves only the compiled test bundle and not
# the package's own files. This script fetches the build that matches the
# resolved `sqlite3` package, serves it on 127.0.0.1:8099, runs both test
# files, and stops the server again.
#
# It writes nothing outside .dart_tool/ and changes no application code.
# See docs/drive-state/ATTACH_VFS_PROTOTYPE.md for what it proves.

set -euo pipefail
cd "$(dirname "$0")/.."

PORT=8099
CACHE=".dart_tool/drive_state_prototype"
WASM="$CACHE/sqlite3.wasm"

version="$(awk '/^  sqlite3:$/{f=1} f&&/version:/{gsub(/"/,"",$2); print $2; exit}' pubspec.lock)"
if [ -z "$version" ]; then
  echo "could not read the sqlite3 version from pubspec.lock" >&2
  exit 1
fi

mkdir -p "$CACHE"
if [ ! -s "$WASM" ]; then
  url="https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-$version/sqlite3.wasm"
  echo "fetching sqlite3.wasm for sqlite3 $version"
  echo "  $url"
  if ! curl -fsSL -o "$WASM" "$url"; then
    echo >&2
    echo "Could not download sqlite3.wasm for sqlite3 $version." >&2
    echo "The copy vendored at web/sqlite3.wasm will NOT work: it is built" >&2
    echo "against a different ABI and fails with" >&2
    echo '  LinkError: Import #0 "dart" "fs_delete"' >&2
    exit 1
  fi
fi
echo "using $WASM ($(wc -c < "$WASM" | tr -d ' ') bytes)"

python3 - "$PWD/$CACHE" "$PORT" <<'PY' &
import functools, http.server, sys
class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        super().end_headers()
    def log_message(self, *a):
        pass
http.server.HTTPServer(
    ('127.0.0.1', int(sys.argv[2])),
    functools.partial(Handler, directory=sys.argv[1]),
).serve_forever()
PY
server=$!
trap 'kill $server 2>/dev/null || true' EXIT

for _ in $(seq 1 25); do
  curl -sf -o /dev/null "http://127.0.0.1:$PORT/sqlite3.wasm" && break
  sleep 0.2
done

echo
echo "=== vm/ffi ==="
flutter test test/drive_state_prototype/attach_vm_test.dart

echo
echo "=== web/wasm (chrome) ==="
flutter test test/drive_state_prototype/attach_web_test.dart --platform chrome
