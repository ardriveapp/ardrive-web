#!/bin/bash

# Runs the app's tests, then every package's analyze + tests.
#
# The packages are independent of each other, so they run in a bounded pool
# rather than one after another. Serially, that step spent a large share of its
# wall clock on work that does not use the CPU it was given - analyzer start-up
# and test runner start-up, twelve times over, in sequence.
#
# The app's own suite deliberately stays outside the pool. `flutter test`
# already runs its suites concurrently, so it uses the cores it is given;
# putting it in the pool adds contention without adding parallelism.
#
# Note that the app suite has at least one pre-existing flaky test that does not
# depend on this script: prompt_to_snapshot_bloc_test.dart waits 250ms for a
# 200ms debounce, and loses the race under load. Keeping the suite out of the
# pool does not fix it.
#
# `TEST_JOBS` sets the width of the pool. `TEST_JOBS=1` restores the old
# strictly-sequential behaviour.

set -euo pipefail

JOBS="${TEST_JOBS:-3}"

# `xargs -P 0` means "as many processes as possible", which is the opposite of a
# bounded pool, so a bad value must not reach it.
case "$JOBS" in
  '' | *[!0-9]*) echo "TEST_JOBS must be a positive integer, got '$JOBS'" >&2; exit 1 ;;
esac
if [ "$JOBS" -lt 1 ]; then
  echo "TEST_JOBS must be at least 1, got '$JOBS'" >&2
  exit 1
fi

packages=()
for dir in packages/*; do
  if [ -d "$dir/test" ]; then
    packages+=("$dir")
  else
    echo "No test directory in $dir, skipping"
  fi
done

# Dependencies are resolved up front and in sequence: concurrent `pub get` runs
# contend for one lock on the shared pub cache, which costs back what the pool
# wins.
echo "Resolving dependencies for the app and ${#packages[@]} packages"
flutter pub get >/dev/null
for dir in "${packages[@]}"; do
  (cd "$dir" && flutter pub get >/dev/null)
done

echo "===== app ====="
flutter test

LOG_DIR="$(mktemp -d)"
trap 'rm -rf "$LOG_DIR"' EXIT
export LOG_DIR

# A worker writes only to its own files. Nothing goes to the shared stdout while
# the pool is running: `cat` of a multi-kilobyte log is many writes, not one, so
# two workers printing at once would interleave mid-suite whatever order they
# started in. The logs are replayed below instead, in a fixed order.
run_package() {
  local dir="$1"
  local name status=0
  name="$(basename "$dir")"

  (cd "$dir" && flutter analyze && flutter test) >"$LOG_DIR/$name.log" 2>&1 || status=$?

  echo "$status" >"$LOG_DIR/$name.status"
  return $status
}
export -f run_package

echo "Running ${#packages[@]} packages, $JOBS at a time"

# xargs exits non-zero when any invocation does. The failure is held rather than
# thrown, so that every package's log still gets printed before the script ends.
pool_status=0
printf '%s\n' "${packages[@]}" | xargs -P "$JOBS" -I{} bash -c 'run_package "$@"' _ {} || pool_status=$?

for dir in "${packages[@]}"; do
  name="$(basename "$dir")"
  echo "===== $name (exit $(cat "$LOG_DIR/$name.status" 2>/dev/null || echo '?')) ====="
  cat "$LOG_DIR/$name.log" 2>/dev/null || echo '(no output - the package did not run)'
done

if [ "$pool_status" -ne 0 ]; then
  echo "At least one package failed. Look for a non-zero exit in the headers above."
  exit "$pool_status"
fi

echo "The app and all ${#packages[@]} packages passed"
