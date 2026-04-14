#!/usr/bin/env bash
set -euo pipefail

OUTROOT=""
SERIAL=""
NO_HOST_PROBES="0"

usage() {
  cat <<'EOF'
Usage:
  box-hotspot-compare.sh [options]

Options:
  --outdir-root DIR    Store both captures under DIR.
  --serial SERIAL      Use a specific adb device serial.
  --no-host-probes     Skip host ping/curl probes.
  -h, --help           Show this help.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
  --outdir-root)
    OUTROOT=${2:-}
    shift 2
    ;;
  --serial)
    SERIAL=${2:-}
    shift 2
    ;;
  --no-host-probes)
    NO_HOST_PROBES="1"
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown arg: $1" >&2
    usage
    exit 1
    ;;
  esac
done

SELF_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CAPTURE_SCRIPT="${SELF_DIR}/box-hotspot-capture.sh"

[ -x "$CAPTURE_SCRIPT" ] || {
  echo "Missing executable script: $CAPTURE_SCRIPT" >&2
  exit 1
}

if [ -z "$OUTROOT" ]; then
  OUTROOT="/tmp/box-hotspot-compare-$(date +%Y%m%d-%H%M%S)"
fi

mkdir -p "$OUTROOT"

run_capture() {
  local state=$1
  local outdir="$OUTROOT/$state"
  local args=(--state "$state" --outdir "$outdir" --no-prompt)
  if [ "$NO_HOST_PROBES" = "1" ]; then
    args+=(--no-host-probes)
  fi
  if [ -n "$SERIAL" ]; then
    args+=(--serial "$SERIAL")
  fi

  printf '\n=== %s ===\n' "$state"
  printf '请把手机切到 Box %s 状态，然后按 Enter 开始采集。\n' "$state"
  read -r _
  "$CAPTURE_SCRIPT" "${args[@]}"
}

run_capture off
run_capture on

diff -ru "$OUTROOT/off" "$OUTROOT/on" >"$OUTROOT/diff.txt" 2>&1 || true

printf '\nDone. Results are in %s\n' "$OUTROOT"
printf 'Compare diff: %s\n' "$OUTROOT/diff.txt"
