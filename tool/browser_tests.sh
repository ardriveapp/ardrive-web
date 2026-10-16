#!/usr/bin/env bash
#
# Runs every browser-only test (`@TestOn('browser')`) in headless Chrome.
#
#   tool/browser_tests.sh
#
# They need `sqlite3.wasm` served with CORS on 127.0.0.1:8099, because
# `flutter test --platform chrome` serves only the compiled test bundle and not
# the package's own files. This checks that web/sqlite3.wasm matches the
# resolved `sqlite3` package, serves web/ on that port, runs the tests, and
# stops the server again, whatever the tests did.
#
# Set FLUTTER to use a Flutter other than the one on PATH, and DART for the
# Dart that compiles the database worker.

set -euo pipefail
cd "$(dirname "$0")/.."

FLUTTER="${FLUTTER:-flutter}"
PORT=8099

tool/check_wasm_version.sh
tool/build_db_worker.sh

mapfile -t tests < <(grep -rl --include='*_test.dart' "@TestOn('browser')" test | sort)
if [ "${#tests[@]}" -eq 0 ]; then
  echo "no browser tests found" >&2
  exit 1
fi

python3 -I - "$PORT" web <<'PY' &
import http.server, socketserver, sys, os
port, root = int(sys.argv[1]), sys.argv[2]
os.chdir(root)
class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        '.wasm': 'application/wasm',
    }
    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        super().end_headers()
    def log_message(self, *args):
        pass
socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(('127.0.0.1', port), Handler) as server:
    server.serve_forever()
PY
server=$!
trap 'kill "$server" 2>/dev/null || true' EXIT

for _ in $(seq 1 50); do
  if curl -fsS -o /dev/null "http://127.0.0.1:$PORT/sqlite3.wasm"; then
    break
  fi
  sleep 0.2
done
curl -fsS -o /dev/null "http://127.0.0.1:$PORT/sqlite3.wasm" || {
  echo "could not serve sqlite3.wasm on port $PORT" >&2
  exit 1
}

echo "browser tests:"
printf '  %s\n' "${tests[@]}"
"$FLUTTER" test --platform chrome "${tests[@]}"
