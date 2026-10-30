#!/usr/bin/env bash
#
# Runs one CI shard of the app's VM tests: every test file whose position in
# the sorted list, modulo TOTAL, is INDEX.
#
#   tool/ci_test_shard.sh INDEX TOTAL
#
# Files are split rather than tests (`flutter test --total-shards` splits the
# tests inside each file, so every shard would still compile every file, which
# is most of the suite's time). Browser-only files are left out: they are
# skipped on the VM anyway, and tool/browser_tests.sh runs them.

set -euo pipefail
cd "$(dirname "$0")/.."

INDEX="${1:?shard index}"
TOTAL="${2:?shard count}"

mapfile -t files < <(
  find test -name '*_test.dart' | sort |
    while read -r f; do grep -q "@TestOn('browser')" "$f" || echo "$f"; done |
    awk -v i="$INDEX" -v n="$TOTAL" '(NR - 1) % n == i'
)

if [ "${#files[@]}" -eq 0 ]; then
  echo "shard $INDEX of $TOTAL has no test files" >&2
  exit 1
fi

echo "shard $INDEX of $TOTAL: ${#files[@]} test files"
flutter test "${files[@]}"
