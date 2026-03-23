#!/usr/bin/env bash
set -euo pipefail

if ! command -v colmena-bin >/dev/null 2>&1; then
  echo "colmena-bin is not available in PATH" >&2
  exit 127
fi

if (($# > 0)); then
  case "$1" in
  -f | --config)
    exec colmena-bin "$@"
    ;;
  esac
fi

exec colmena-bin -f "${PRJ_ROOT:-$(pwd)}/hive.nix" "$@"
