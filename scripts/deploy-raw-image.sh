#!/usr/bin/env sh
set -eu

SCRIPTDIR=$(dirname "$0")
# shellcheck disable=SC1091
. "$SCRIPTDIR/_img_deploy_common.sh"

PORT=22
ONLY_BUILD=no
ONLY_STREAM=no

ONLY_BUILD=no
ONLY_STREAM=no
LIVE_OVERWRITE=no

while [ $# -gt 0 ]; do
  case "$1" in
  --target)
    TARGET="$2"
    shift 2
    ;;
  --host)
    HOST="$2"
    shift 2
    ;;
  --user)
    USER="$2"
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
  *) die "Unknown arg: $1" ;;
  esac
done

[ -n "${TARGET:-}" ] || die "--target is required (nix flake build target)"

if [ "$ONLY_STREAM" = "no" ]; then
  log "Phase 1: Building image..."
  IMG=$(get_nix_image_path "$TARGET")
  log "Build result: $IMG"
  # Save the path to a temporary file for the streaming phase if needed
  printf "%s" "$IMG" >.last_built_image
fi

if [ "$ONLY_BUILD" = "yes" ]; then
  log "Build complete. Run with --only-stream to deploy."
  exit 0
fi

if [ "$ONLY_STREAM" = "yes" ]; then
  if [ -f .last_built_image ] && [ -e "$(cat .last_built_image)" ]; then
    IMG=$(cat .last_built_image)
    log "Using cached image path: $IMG"
  else
    log "Cached image not found or invalid. Retrieving path from Nix..."
    # If diskoImages is a directory, find the image inside it
    OUT_PATH=$(nix build "$TARGET" --no-link --print-out-paths --experimental-features 'nix-command flakes')
    IMG=$(find "$OUT_PATH" -maxdepth 2 -type f \( -name '*.img' -o -name '*.raw' \) | head -n1 || echo "$OUT_PATH")
    [ -n "$IMG" ] || die "Cannot find image in Nix output: $OUT_PATH"
    printf "%s" "$IMG" >.last_built_image
  fi
fi

[ -n "${HOST:-}" ] || die "--host is required"
[ -n "${USER:-}" ] || die "--user is required"
[ -n "${DEVICE:-}" ] || die "--device is required"

USER_AT_HOST="${USER}@${HOST}"

log "Phase 2: Streaming image to $USER_AT_HOST:$DEVICE ..."

# --- SSH Multiplexing (ControlMaster) Setup ---
# This allows us to authenticate once and reuse the connection for all subsequent commands.
CONTROL_PATH="/tmp/ssh-control-$(echo "$USER_AT_HOST" | tr '@' '-')"
log "Establishing master SSH connection (session multiplexing)..."
ssh -p "$PORT" -M -f -N -o ControlPath="$CONTROL_PATH" -o ControlPersist=600 "$USER_AT_HOST" || die "Failed to establish master SSH connection"

# Traps to ensure the master connection is closed on exit or error
cleanup() {
  log "Closing master SSH connection..."
  ssh -p "$PORT" -o ControlPath="$CONTROL_PATH" -O exit "$USER_AT_HOST" >/dev/null 2>&1 || true
  rm -f "$CONTROL_PATH"
}
trap cleanup EXIT INT TERM

# Export SSH_OPTS to simplify subsequent calls
SSH_CMD="ssh -o ControlPath=$CONTROL_PATH -p $PORT"

log "Ensuring SSH access..."
ensure_ssh_key "$USER_AT_HOST" "$PORT" "yes"

SIZE_BYTES=$(stat -c%s "$IMG")
BS=4M

PV_BIN=$(nix-build '<nixpkgs>' -A pv --no-out-link 2>/dev/null)/bin/pv || PV_BIN=$(nix build --no-link --print-out-paths nixpkgs#pv 2>/dev/null)/bin/pv || PV_BIN="pv"
ZSTD_BIN=$(nix-build '<nixpkgs>' -A zstd --no-out-link 2>/dev/null)/bin/zstd || ZSTD_BIN=$(nix build --no-link --print-out-paths nixpkgs#zstd 2>/dev/null)/bin/zstd || ZSTD_BIN="zstd"

log "Detecting remote decompressor..."
REMOTE_COMP=$($SSH_CMD "$USER_AT_HOST" "
  if command -v zstd >/dev/null; then echo zstd;
  elif command -v gzip >/dev/null; then echo gzip;
  else echo none; fi
")
log "Remote decompressor: $REMOTE_COMP"

case "$REMOTE_COMP" in
zstd)
  COMP_CMD="$ZSTD_BIN -1 -c -T0"
  DECOMP_CMD="zstd -dc"
  ;;
gzip)
  COMP_CMD="gzip -1 -c"
  DECOMP_CMD="gzip -dc"
  ;;
*)
  COMP_CMD="cat"
  DECOMP_CMD="cat"
  ;;
esac

if echo "$IMG" | grep -q '\.zst$'; then
  READ_CMD="$ZSTD_BIN -dc"
else
  READ_CMD="cat"
fi

log "Starting deployment pipeline..."

if [ "$LIVE_OVERWRITE" = "yes" ]; then
  log "LIVE OVERWRITE MODE: Preparing remote system..."
  # Pre-cache vital binaries to RAM - crucial for being able to reboot after DD
  $SSH_CMD "$USER_AT_HOST" "
    echo 'Caching vitals to RAM...'
    cat /bin/sync /sbin/reboot /bin/sh /bin/cat /usr/bin/sudo > /dev/null 2>&1
    echo 'Remote system prepared.'
  "
fi

$READ_CMD "$IMG" |
  "$PV_BIN" -N "Read" -s "$SIZE_BYTES" |
  $COMP_CMD |
  "$PV_BIN" -N "Transfer" |
  $SSH_CMD "$USER_AT_HOST" "$DECOMP_CMD | dd of=$DEVICE bs=$BS conv=fsync status=none" || die "Remote dd failed"

log "Syncing remote disk..."
if [ "$LIVE_OVERWRITE" = "yes" ]; then
  log "LIVE OVERWRITE: Sending forced reboot signal..."
  # Use -f because a normal shutdown will likely fail once disk is overwritten
  $SSH_CMD "$USER_AT_HOST" "sync && reboot -f" || log "Reboot signal sent (connection likely lost as expected)"
  log "Deployment finished. Target should be rebooting into NixOS now."
else
  $SSH_CMD "$USER_AT_HOST" "sync"
  log "Deployment finished successfully. You may now reboot the target manually."
fi
