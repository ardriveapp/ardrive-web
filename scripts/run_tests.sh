#!/bin/bash

# Runs the app's tests, then every package's analyze + tests.
#
# The packages are independent of each other, so they run in a bounded pool
# rather than one after another. Serially, that step spent a large share of its
# wall clock on work that does not use the CPU it was given - analyzer start-up
# and test runner start-up, twelve times over, in sequence.
#
# The app's own suite deliberately stays outside the pool. `flutter test`
# already spreads it across cores, and some of its bloc tests wait on real
# debounce timers, so they start failing when other test processes compete for
# the CPU. Running it alone costs a little wall clock and buys a stable signal.
#
# `TEST_JOBS` sets the width of the pool. `TEST_JOBS=1` restores the old
# strictly-sequential behaviour, which is worth reaching for when interleaved
# output makes a failure hard to read.

set -euo pipefail

JOBS="${TEST_JOBS:-3}"

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

# Each package's output is buffered and printed in one piece, so that packages
# running side by side cannot interleave halfway through a suite and leave the
# log unreadable.
run_package() {
  local dir="$1"
  local name status=0
  name="$(basename "$dir")"

  (cd "$dir" && flutter analyze && flutter test) >"$LOG_DIR/$name.log" 2>&1 || status=$?

  echo "===== $name (exit $status) ====="
  cat "$LOG_DIR/$name.log"
  return $status
}
export -f run_package

echo "Running ${#packages[@]} packages, $JOBS at a time"

# xargs exits non-zero when any invocation does, and `set -e` turns that into a
# failed step - so one broken package still fails the build.
printf '%s\n' "${packages[@]}" | xargs -P "$JOBS" -I{} bash -c 'run_package "$@"' _ {}

echo "The app and all ${#packages[@]} packages passed"
