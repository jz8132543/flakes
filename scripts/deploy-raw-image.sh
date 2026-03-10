#!/usr/bin/env bash
set -euo pipefail

SCRIPTDIR=$(dirname "$0")
# shellcheck disable=SC1091
. "$SCRIPTDIR/_img_deploy_common.sh"

FLAKE_TARGET=""
TARGET_HOST=""
PORT=22
DEVICE=""
ONLY_BUILD=no
ONLY_STREAM=no
LIVE_OVERWRITE=no
LAST_BUILT_IMAGE_FILE=".last_built_image"
CONTROL_PATH=""
IMG=""
REMOTE_BUSYBOX=""

usage() {
  cat <<'EOF'
Usage:
  deploy-raw-image.sh --target FLAKE_ATTR --only-build
  deploy-raw-image.sh --target FLAKE_ATTR --target-host user@host --device /dev/sdX [--port PORT] [--only-stream|--live-overwrite]

Arguments:
  --target       Nix flake build target, usually .#nixosConfigurations.<host>.config.system.build.diskoImages
  --target-host  Remote SSH target in user@host form
  --device       Remote block device to overwrite
  --port         Remote SSH port, defaults to 22
  --only-build   Build image locally and stop
  --only-stream  Skip the build step and stream the last built image
  --live-overwrite
                 Overwrite the currently running Linux system and force reboot after dd
EOF
  exit 1
}

is_true() {
  case "${1:-}" in
  yes | true | TRUE | 1 | on | ON) return 0 ;;
  *) return 1 ;;
  esac
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
    --target)
      FLAKE_TARGET="$2"
      shift 2
      ;;
    --target-host | --host)
      TARGET_HOST="$2"
      shift 2
      ;;
    --port)
      PORT="$2"
      shift 2
      ;;
    --device)
      DEVICE="$2"
      shift 2
      ;;
    --only-build)
      ONLY_BUILD=yes
      shift 1
      ;;
    --only-stream)
      ONLY_STREAM=yes
      shift 1
      ;;
    --live-overwrite)
      LIVE_OVERWRITE=yes
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

  [ -n "$FLAKE_TARGET" ] || die "--target is required"

  if is_true "$ONLY_BUILD"; then
    return
  fi

  [ -n "$TARGET_HOST" ] || die "--target-host is required unless --only-build is set"
  [ -n "$DEVICE" ] || die "--device is required unless --only-build is set"
}

build_image() {
  log "Phase 1: Building image..."
  IMG=$(get_nix_image_path "$FLAKE_TARGET")
  printf '%s' "$IMG" >"$LAST_BUILT_IMAGE_FILE"
  log "Build result: $IMG"
}

resolve_cached_image() {
  if [ -f "$LAST_BUILT_IMAGE_FILE" ]; then
    IMG=$(cat "$LAST_BUILT_IMAGE_FILE")
    if [ -e "$IMG" ]; then
      log "Using cached image path: $IMG"
      return
    fi
  fi

  log "Cached image not found or invalid. Rebuilding path from Nix..."
  build_image
}

cleanup() {
  if [ -n "$CONTROL_PATH" ] && [ -n "$TARGET_HOST" ]; then
    log "Closing master SSH connection..."
    ssh -p "$PORT" -o ControlPath="$CONTROL_PATH" -O exit "$TARGET_HOST" >/dev/null 2>&1 || true
    rm -f "$CONTROL_PATH"
  fi
}

setup_ssh_mux() {
  CONTROL_PATH="/tmp/ssh-control-$(printf '%s' "$TARGET_HOST" | tr '@:/' '---')"
  log "Establishing master SSH connection..."
  ssh -p "$PORT" -M -f -N -o ControlPath="$CONTROL_PATH" -o ControlPersist=600 "$TARGET_HOST" ||
    die "Failed to establish master SSH connection"
  trap cleanup EXIT INT TERM
}

remote_ssh() {
  ssh -o ControlPath="$CONTROL_PATH" -p "$PORT" "$TARGET_HOST" "$@"
}

detect_local_tool() {
  local nix_attr="$1"
  local fallback="$2"
  local tool_path

  tool_path="$(nix build --no-link --print-out-paths "nixpkgs#${nix_attr}" 2>/dev/null || true)"
  if [ -n "$tool_path" ] && [ -x "${tool_path}/bin/${nix_attr}" ]; then
    printf '%s\n' "${tool_path}/bin/${nix_attr}"
    return
  fi

  printf '%s\n' "$fallback"
}

prepare_pipeline_tools() {
  PV_BIN="$(detect_local_tool pv pv)"
  ZSTD_BIN="$(detect_local_tool zstd zstd)"
  SIZE_BYTES=$(stat -c%s "$IMG")

  log "Detecting remote decompressor..."
  REMOTE_COMP="$(remote_ssh '
    if command -v zstd >/dev/null 2>&1; then
      echo zstd
    elif command -v gzip >/dev/null 2>&1; then
      echo gzip
    else
      echo none
    fi
  ')"
  log "Remote decompressor: $REMOTE_COMP"

  case "$REMOTE_COMP" in
  zstd)
    COMPRESS_CMD=("$ZSTD_BIN" -1 -c -T0)
    DECOMPRESS_CMD='zstd -dc'
    ;;
  gzip)
    COMPRESS_CMD=(gzip -1 -c)
    DECOMPRESS_CMD='gzip -dc'
    ;;
  *)
    COMPRESS_CMD=(cat)
    DECOMPRESS_CMD='cat'
    ;;
  esac

  if [[ $IMG == *.zst ]]; then
    READ_CMD=("$ZSTD_BIN" -dc "$IMG")
  else
    READ_CMD=(cat "$IMG")
  fi
}

prepare_live_overwrite() {
  log "LIVE OVERWRITE MODE: Preparing remote system..."
  REMOTE_BUSYBOX="$(
    remote_ssh '
      set -eu
      dst_dir=/run
      if [ -d /dev/shm ] && [ -w /dev/shm ]; then
        dst_dir=/dev/shm
      fi

      if ! command -v busybox >/dev/null 2>&1; then
        exit 0
      fi

      src=$(command -v busybox)
      dst="${dst_dir}/nixos-live-busybox"
      rm -f "$dst"
      cp "$src" "$dst" 2>/dev/null || cat "$src" >"$dst"
      chmod 0755 "$dst"
      printf "%s" "$dst"
    '
  )"

  if [ -n "$REMOTE_BUSYBOX" ]; then
    log "Prepared in-memory busybox at ${REMOTE_BUSYBOX}"
    return
  fi

  log "Remote busybox not found; will fall back to sysrq reboot"
}

stream_image() {
  local bs="4M"

  log "Phase 2: Streaming image to ${TARGET_HOST}:${DEVICE} ..."
  "${READ_CMD[@]}" |
    "$PV_BIN" -N Read -s "$SIZE_BYTES" |
    "${COMPRESS_CMD[@]}" |
    "$PV_BIN" -N Transfer |
    remote_ssh "$DECOMPRESS_CMD | dd of=$DEVICE bs=$bs conv=fsync status=none" ||
    die "Remote dd failed"
}

finish_deployment() {
  log "Syncing remote disk..."
  if is_true "$LIVE_OVERWRITE"; then
    log "LIVE OVERWRITE: Sending forced reboot signal..."
    if [ -n "$REMOTE_BUSYBOX" ]; then
      remote_ssh "$REMOTE_BUSYBOX sync && $REMOTE_BUSYBOX reboot -f" ||
        log "Busybox reboot dispatched (connection loss is expected)"
    else
      remote_ssh "echo b >/proc/sysrq-trigger" ||
        log "Sysrq reboot dispatched (connection loss is expected)"
    fi
    log "Deployment finished. Target should be rebooting into NixOS now."
    return
  fi

  remote_ssh "sync"
  log "Deployment finished successfully. You may now reboot the target manually."
}

main() {
  parse_args "$@"

  if ! is_true "$ONLY_STREAM"; then
    build_image
  fi

  if is_true "$ONLY_BUILD"; then
    log "Build complete. Run with --only-stream to deploy."
    exit 0
  fi

  if is_true "$ONLY_STREAM"; then
    resolve_cached_image
  fi

  setup_ssh_mux
  prepare_pipeline_tools

  if is_true "$LIVE_OVERWRITE"; then
    prepare_live_overwrite
  fi

  stream_image
  finish_deployment
}

main "$@"
