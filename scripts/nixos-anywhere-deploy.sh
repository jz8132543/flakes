#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: nixos-anywhere-deploy.sh --hostname NAME --target user@host [--port PORT] [--extras "attr1 attr2"] [--no-substitute-on-destination=0|1]

This script performs an offline-first nixos-anywhere deployment:
1. Build all required deployment artifacts on the build host.
2. Compute and push the combined /nix/store closure to the target host.
3. Run a locally built nixos-anywhere binary so the target host does not need GitHub access.
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

HOSTNAME=""
TARGET=""
PORT=22
EXTRAS=""
NO_SUBSTITUTE="1"
TMPDIR="$(mktemp -d /tmp/nixos-anywhere-deploy.XXXXXX)"
CLOSURE_FILE="${TMPDIR}/closure.txt"
BUILD_SYSTEM=""
NIXOS_ANYWHERE_BIN=""

cleanup() {
  rm -rf "$TMPDIR"
}

trap cleanup EXIT

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
    --hostname)
      HOSTNAME="$2"
      shift 2
      ;;
    --target)
      TARGET="$2"
      shift 2
      ;;
    --port)
      PORT="$2"
      shift 2
      ;;
    --extras)
      EXTRAS="$2"
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

  if [ -z "$HOSTNAME" ] || [ -z "$TARGET" ]; then
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

append_closure_for_path() {
  local store_path="$1"
  nix-store --query --requisites "$store_path" >>"$CLOSURE_FILE"
}

append_closure_for_attr() {
  local attr="$1"
  local store_path
  log "Building ${attr}"
  store_path="$(build_attr_path "$attr")"
  append_closure_for_path "$store_path"
}

collect_target_artifacts() {
  local artifact_attrs=(
    ".#nixosConfigurations.${HOSTNAME}.config.system.build.toplevel"
    ".#nixosConfigurations.${HOSTNAME}.config.system.build.nixos-install"
    ".#nixosConfigurations.${HOSTNAME}.config.system.build.installBootLoader"
    ".#nixosConfigurations.${HOSTNAME}.config.system.build.diskoNoDeps"
    ".#nixosConfigurations.${HOSTNAME}.config.system.build.diskoScriptNoDeps"
  )
  local attr

  for attr in "${artifact_attrs[@]}"; do
    append_closure_for_attr "$attr"
  done
}

collect_extra_artifacts() {
  local extra

  if [ -z "$EXTRAS" ]; then
    return
  fi

  log "Building extras: $EXTRAS"
  for extra in $EXTRAS; do
    append_closure_for_attr "$extra"
  done
}

prepare_local_nixos_anywhere() {
  BUILD_SYSTEM="$(nix eval --impure --raw --expr builtins.currentSystem)"
  local package_attr=".#packages.${BUILD_SYSTEM}.nixos-anywhere"
  local package_path

  log "Building local nixos-anywhere package (${package_attr})"
  package_path="$(build_attr_path "$package_attr")"
  NIXOS_ANYWHERE_BIN="${package_path}/bin/nixos-anywhere"

  if [ ! -x "$NIXOS_ANYWHERE_BIN" ]; then
    die "Expected nixos-anywhere binary at ${NIXOS_ANYWHERE_BIN}"
  fi
}

finalize_closure_manifest() {
  sort -u "$CLOSURE_FILE" -o "$CLOSURE_FILE"
  log "Prepared $(wc -l <"$CLOSURE_FILE") store paths for offline push"
}

push_closure() {
  log "Checking whether the target has rsync"
  if ssh -p "$PORT" "$TARGET" 'command -v rsync >/dev/null 2>&1'; then
    log "Target has rsync; pushing closure with rsync"
    rsync -aHAXz --numeric-ids -e "ssh -p ${PORT}" --files-from="$CLOSURE_FILE" / "${TARGET}":/
  else
    log "Target lacks rsync; streaming closure with tar over ssh"
    tar -czf - -T "$CLOSURE_FILE" -P -C / | ssh -p "$PORT" "$TARGET" 'tar xzpf - -P -C /'
  fi
}

run_nixos_anywhere() {
  local cmd=(
    "$NIXOS_ANYWHERE_BIN"
    "--no-disko-deps"
  )

  if [ "$NO_SUBSTITUTE" = "1" ] || [ "$NO_SUBSTITUTE" = "true" ]; then
    cmd+=("--no-substitute-on-destination")
  fi

  cmd+=(
    "--flake"
    ".#${HOSTNAME}"
    "$TARGET"
    "-p"
    "$PORT"
  )

  log "Running locally built nixos-anywhere in offline-first mode"
  "${cmd[@]}"
}

main() {
  : >"$CLOSURE_FILE"
  parse_args "$@"
  prepare_local_nixos_anywhere
  collect_target_artifacts
  collect_extra_artifacts
  finalize_closure_manifest
  push_closure
  run_nixos_anywhere
  log "Done."
}

main "$@"
