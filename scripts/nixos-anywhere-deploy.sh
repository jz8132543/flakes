#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: nixos-anywhere-deploy.sh --host NAME --target-host user@host [--port PORT] [--no-substitute-on-destination=0|1]

This script performs an offline-first nixos-anywhere deployment by:
1. Building nixos-anywhere, the target toplevel, and the disko script on the build host.
2. Passing those store paths to nixos-anywhere via --store-paths.
3. Letting nixos-anywhere copy the required closures at the correct install phase.
EOF
  exit 1
}

log() {
  printf '[nixos-anywhere-deploy] %s\n' "$*"
}

die() {
  printf '[nixos-anywhere-deploy] %s\n' "$*" >&2
  exit 1
}

HOST=""
TARGET_HOST=""
PORT=22
NO_SUBSTITUTE="1"
BUILD_SYSTEM=""
NIXOS_ANYWHERE_BIN=""
TOPLEVEL_PATH=""
DISKO_SCRIPT_PATH=""

is_true() {
  case "${1:-}" in
  1 | true | TRUE | yes | YES | on | ON) return 0 ;;
  *) return 1 ;;
  esac
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
    --host | --hostname)
      HOST="$2"
      shift 2
      ;;
    --target-host | --target)
      TARGET_HOST="$2"
      shift 2
      ;;
    --port)
      PORT="$2"
      shift 2
      ;;
    --no-substitute-on-destination=*)
      NO_SUBSTITUTE="${1#*=}"
      shift 1
      ;;
    --no-substitute-on-destination)
      NO_SUBSTITUTE="1"
      shift 1
      ;;
    -h | --help)
      usage
      ;;
    *)
      die "Unknown arg: $1"
      ;;
    esac
  done

  if [ -z "$HOST" ] || [ -z "$TARGET_HOST" ]; then
    usage
  fi
}

build_attr_path() {
  local attr="$1"
  nix build \
    --no-link \
    --print-out-paths \
    --experimental-features 'nix-command flakes' \
    "$attr"
}

prepare_local_nixos_anywhere() {
  local package_attr
  local package_path

  BUILD_SYSTEM="$(nix eval --impure --raw --expr builtins.currentSystem)"
  package_attr=".#packages.${BUILD_SYSTEM}.nixos-anywhere"

  log "Building local nixos-anywhere package (${package_attr})"
  package_path="$(build_attr_path "$package_attr")"
  NIXOS_ANYWHERE_BIN="${package_path}/bin/nixos-anywhere"

  if [ ! -x "$NIXOS_ANYWHERE_BIN" ]; then
    die "Expected nixos-anywhere binary at ${NIXOS_ANYWHERE_BIN}"
  fi
}

prepare_target_artifacts() {
  log "Building target toplevel for ${HOST}"
  TOPLEVEL_PATH="$(build_attr_path ".#nixosConfigurations.${HOST}.config.system.build.toplevel")"

  log "Building disko script for ${HOST}"
  DISKO_SCRIPT_PATH="$(build_attr_path ".#nixosConfigurations.${HOST}.config.system.build.diskoScriptNoDeps")"

  if [ ! -e "$TOPLEVEL_PATH" ]; then
    die "Missing toplevel store path: ${TOPLEVEL_PATH}"
  fi

  if [ ! -e "$DISKO_SCRIPT_PATH" ]; then
    die "Missing disko script store path: ${DISKO_SCRIPT_PATH}"
  fi
}

run_nixos_anywhere() {
  local cmd=(
    "$NIXOS_ANYWHERE_BIN"
  )

  if is_true "$NO_SUBSTITUTE"; then
    cmd+=("--no-substitute-on-destination")
  fi

  cmd+=(
    "--store-paths"
    "$DISKO_SCRIPT_PATH"
    "$TOPLEVEL_PATH"
    "$TARGET_HOST"
    "-p"
    "$PORT"
  )

  log "Running nixos-anywhere with prebuilt store paths"
  "${cmd[@]}"
}

main() {
  parse_args "$@"
  prepare_local_nixos_anywhere
  prepare_target_artifacts
  run_nixos_anywhere
  log "Done."
}

main "$@"
