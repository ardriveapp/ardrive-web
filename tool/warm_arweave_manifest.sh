#!/usr/bin/env bash
#
# Reads every path of an Arweave path manifest once through each gateway, so
# the first visitor after a deploy is not the one who makes the gateway fetch
# and index 466 files. Also checks what a browser would get: every path must
# answer 200, and no gateway may send gzip bytes without
# `Content-Encoding: gzip`, because the deploy uploads them gzipped and a
# browser handed them bare cannot run them. A gateway may instead decompress
# an item itself (ar-io.dev does for some); that works, at a larger transfer,
# so the summary counts the JavaScript and wasm paths served that way.
#
#   tool/warm_arweave_manifest.sh <manifest-id>
#
# GATEWAYS (default "turbo-gateway.com ardrive.net", Turbo's and ArDrive's)
# and JOBS (default 4) override the gateways and the number of parallel
# requests. ar-io.dev is left out on purpose: it charges for data past a free
# allowance (HTTP 402, x402), and reading 466 files from each CI run would
# spend it. Requests go through the sandboxed route
# (`https://<gateway>/<id>/<path>`, which redirects to the manifest's own
# subdomain), the route a library page is served on.
#
# Exits 1 if any path failed on any gateway; prints one line per failure, with
# curl's error when there was no response, and a summary per gateway.

set -euo pipefail

id="${1:-}"
if [[ ! "$id" =~ ^[A-Za-z0-9_-]{43}$ ]]; then
  echo "usage: $0 <manifest-id>" >&2
  exit 2
fi

GATEWAYS="${GATEWAYS:-turbo-gateway.com ardrive.net}"
JOBS="${JOBS:-4}"

# Turbo serves a new upload before it is mined, so read the manifest there.
manifest="$(curl -fsSL --retry 5 --retry-all-errors --retry-delay 5 \
  "https://turbo-gateway.com/raw/$id")"

# Each path segment URL-encoded, so no path holds whitespace, with a leading
# slash so the index route ("/") is not empty.
paths="$(printf '%s' "$manifest" |
  jq -r '"/", (.paths | keys[] | "/" + (split("/") | map(@uri) | join("/")))')"

warm() {
  local gateway="$1" path="$2" out err body code encoding size verdict=ok note=
  err="$(mktemp)"
  body="$(mktemp)"
  # Asks for gzip as a browser does. Gateways drop the odd connection under
  # parallel load, and fetch an item they have not indexed yet on first
  # request, so retry with a pause.
  out="$(curl -sS -L -o "$body" -H 'Accept-Encoding: gzip, deflate, br' \
    --retry 5 --retry-all-errors --retry-delay 3 --max-time 180 \
    -w '%{http_code} %header{content-encoding} %{size_download}' \
    "https://$gateway/$id$path" 2>"$err" || true)"
  read -r code encoding size <<<"$out"
  # An absent header leaves `encoding` holding the size.
  if [[ -z "${size:-}" ]]; then size="${encoding:-0}"; encoding=-; fi
  if [[ "${code:-000}" != 200 ]]; then
    verdict=FAIL
    [[ -s "$err" ]] && note="$(tail -1 "$err")"
  elif [[ "$encoding" == - && "$(head -c 2 "$body" | od -An -tx1 | tr -d ' ')" == 1f8b ]]; then
    verdict=FAIL
    note='gzip bytes without Content-Encoding'
  elif [[ "$encoding" == - && "$path" =~ \.(js|mjs|wasm)$ ]]; then
    verdict=plain
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$verdict" "$gateway" "${code:-000}" \
    "$encoding" "$size" "$path" "$note"
  rm -f "$err" "$body"
}
export -f warm
export id

results="$(for gateway in $GATEWAYS; do
  printf '%s\n' "$paths" | sed "s|^|$gateway |"
done | xargs -n 2 -P "$JOBS" bash -c 'warm "$1" "$2"' _)"

failures="$(printf '%s\n' "$results" | awk -F'\t' '$1 == "FAIL"')"
if [[ -n "$failures" ]]; then
  echo "verdict	gateway	status	encoding	bytes	path	note"
  printf '%s\n' "$failures"
fi

printf '%s\n' "$results" | awk -F'\t' '
  { n[$2]++; bytes[$2] += $5; if ($1 == "FAIL") bad[$2]++; if ($1 == "plain") plain[$2]++ }
  END {
    for (g in n)
      printf "%s: %d paths, %d failed, %d JavaScript/wasm sent uncompressed, %.1f MB transferred\n",
        g, n[g], bad[g] + 0, plain[g] + 0, bytes[g] / 1e6
  }'

[[ -z "$failures" ]]
