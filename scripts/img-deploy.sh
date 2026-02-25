#!/usr/bin/env sh
set -eu

SCRIPTDIR=$(dirname "$0")
# shellcheck disable=SC1091
. "$SCRIPTDIR/_img_deploy_common.sh"

# defaults
COMPRESSION=${COMPRESSION:-zstd}
PORT=22
FORCE=no
NO_KEY_INSTALL=no

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
  --compression)
    COMPRESSION="$2"
    shift 2
    ;;
  --force)
    # shellcheck disable=SC2034
    FORCE=yes
    shift 1
    ;;
  --no-key-install)
    NO_KEY_INSTALL=yes
    shift 1
    ;;
  --dry-run)
    DRY_RUN=yes
    shift 1
    ;;
  *) die "Unknown arg: $1" ;;
  esac
done

[ -n "${TARGET:-}" ] || die "--target is required (nix flake build target)"
[ -n "${HOST:-}" ] || die "--host is required"
[ -n "${USER:-}" ] || die "--user is required"
[ -n "${DEVICE:-}" ] || die "--device is required"

USER_AT_HOST="${USER}@${HOST}"

log "Ensuring SSH key / access..."
ensure_ssh_key "$USER_AT_HOST" "$PORT" "$NO_KEY_INSTALL"

log "Obtaining image path from nix..."
IMG=$(get_nix_image_path "$TARGET")
log "Image found: $IMG"

SIZE_BYTES=$(stat -c%s "$IMG")
log "Image size: $SIZE_BYTES bytes"

if [ "${DRY_RUN:-}" = "yes" ]; then
  log "DRY RUN: would stream $IMG to $USER_AT_HOST:$DEVICE using $COMPRESSION"
  exit 0
fi

confirm "About to overwrite $DEVICE on $USER_AT_HOST. Type 'y' to proceed." || die "Aborted by user"

# compute block count for remote verification (use 4M blocks)
BS=4M
COUNT=$(((SIZE_BYTES + 4 * 1024 * 1024 - 1) / (4 * 1024 * 1024)))

log "Starting streaming (compression: $COMPRESSION). This may take a while..."
case "$COMPRESSION" in
zstd) COMP_CMD="zstd -T0 -c" ;;
gzip) COMP_CMD="gzip -c" ;;
xz) COMP_CMD="xz -c" ;;
none) COMP_CMD="cat" ;;
*) die "Unsupported compression: $COMPRESSION" ;;
esac

# Stream compressed image and write remotely
$COMP_CMD "$IMG" | ssh -p "$PORT" "$USER_AT_HOST" "sudo dd of=$DEVICE bs=$BS conv=fsync status=progress" || die "Remote dd failed"

log "Syncing remote disk..."
ssh -p "$PORT" "$USER_AT_HOST" "sudo sync"

log "Computing local SHA256..."
LOCAL_HASH=$(sha256sum "$IMG" | cut -d' ' -f1)
log "Local hash: $LOCAL_HASH"

log "Computing remote SHA256 on written device (first $COUNT blocks)..."
REMOTE_HASH=$(ssh -p "$PORT" "$USER_AT_HOST" "sudo dd if=$DEVICE bs=$BS count=$COUNT status=none | sha256sum | cut -d' ' -f1")
log "Remote hash: $REMOTE_HASH"

if [ "$LOCAL_HASH" = "$REMOTE_HASH" ]; then
  log "SUCCESS: hashes match"
else
  die "HASH MISMATCH: local=$LOCAL_HASH remote=$REMOTE_HASH"
fi

log "Deployment finished. You may now reboot the target manually or via: ssh -p $PORT $USER_AT_HOST 'sudo reboot'"
