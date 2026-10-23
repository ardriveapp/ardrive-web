#!/usr/bin/env bash
#
# Puts Flutter's fallback fonts in a web build, so a library page loads them
# from its own host instead of fonts.gstatic.com (see the fetch rewrite in
# web/index.html and docs/LIBRARY_PAGES.md, "Fallback fonts").
#
#   tool/fetch_fallback_fonts.sh [dest]        # default build/web/fonts/gstatic
#   tool/fetch_fallback_fonts.sh --pin <engine-dir>
#
# The first form downloads the 144 files listed in tool/fallback_fonts.sha256
# (Roboto and the engine's 143 Noto fonts, about 81 MB) to dest/<path>, the
# path each has under https://fonts.gstatic.com/s/, and checks every one
# against its pinned SHA-256. Exits 1 if any download fails or any file does
# not match. Run it for Arweave deploys only: Firebase serves the normal app,
# which fetches the fonts from Google as before.
#
# The second form rewrites tool/fallback_fonts.sha256 from a Flutter SDK's web
# engine, the directory holding font_fallback_data.dart (for 3.19.6,
# <flutter>/bin/cache/flutter_web_sdk/lib/_engine/engine). Run it on every
# Flutter upgrade: the engine names each font by a versioned path, and a font
# it asks for that the page lacks shows as empty boxes.

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
list="$root/tool/fallback_fonts.sha256"
base='https://fonts.gstatic.com/s/'

fetch() { # <path> <out>
  curl -sS -L --fail --retry 5 --retry-all-errors --retry-delay 3 \
    --max-time 300 -o "$2" "$base$1"
}

if [[ "${1:-}" == '--pin' ]]; then
  engine="${2:?usage: $0 --pin <engine-dir>}"
  paths="$({
    grep -o "'[a-z0-9]*/v[0-9]*/[A-Za-z0-9_-]*\.ttf'" \
      "$engine/font_fallback_data.dart"
    grep -o "fonts.gstatic.com/s/[^']*\.ttf" "$engine/canvaskit/fonts.dart" |
      sed 's|fonts.gstatic.com/s/||'
  } | tr -d "'" | sort -u)"
  count="$(wc -l <<<"$paths")"
  if (( count < 100 )); then
    echo "found only $count font paths in $engine; has the engine moved them?" >&2
    exit 1
  fi
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  : >"$tmp/list"
  while read -r path; do
    fetch "$path" "$tmp/font"
    echo "$(sha256sum "$tmp/font" | cut -d' ' -f1)  $path" >>"$tmp/list"
  done <<<"$paths"
  mv "$tmp/list" "$list"
  echo "pinned $count fonts in ${list#"$root/"}"
  exit 0
fi

dest="${1:-$root/build/web/fonts/gstatic}"
mkdir -p "$dest"
failed=0
while read -r sum path; do
  mkdir -p "$dest/$(dirname "$path")"
  if ! fetch "$path" "$dest/$path"; then
    echo "FAIL $path: download failed" >&2
    failed=1
    continue
  fi
  if [[ "$(sha256sum "$dest/$path" | cut -d' ' -f1)" != "$sum" ]]; then
    echo "FAIL $path: checksum does not match" >&2
    rm -f "$dest/$path"
    failed=1
  fi
done <"$list"

if (( failed )); then
  exit 1
fi
echo "fetched $(wc -l <"$list") fonts into $dest"
