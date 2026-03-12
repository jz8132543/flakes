#!/usr/bin/env bash
# test-kexec-qemu.sh – spin up a QEMU "victim" VM and run deploy-live-kexec.sh
# against it so we can debug kexec + trampoline without touching real hardware.
#
# Usage:
#   bash scripts/test-kexec-qemu.sh [--host HOST] [--device /dev/vda]
#
# Requires:
#   - qemu-system-x86_64 (from nixpkgs#qemu, already in PATH via devshell or nix shell)
#   - result/main.raw   (existing NixOS disk image built by diskoImages)
#   - The SSH key that the NixOS image accepts (ssh-ed25519 ...i@dora.im) in the agent
#
# How it works:
#   1. Creates a QCOW2 overlay over result/main.raw (instant, no 6 GB copy).
#   2. Boots the NixOS image in QEMU (KVM, 2 GB RAM) with:
#        - Serial console → /tmp/trampoline-serial.log  (watch with: tail -f)
#        - virtio-net with port-forwards:
#            host:2222 → guest:1022  (real NixOS SSH / later trampoline SSH)
#   3. Waits for SSH to be ready.
#   4. Runs deploy-live-kexec.sh targeting localhost:2222.
#   5. After kexec fires, the serial log shows exactly what the /init script does.
#
# Tip: open a second terminal and run:
#   tail -f /tmp/trampoline-serial.log
# to watch serial output while the deploy runs.

set -euo pipefail
cd "$(dirname "$0")/.."

# ── configuration ────────────────────────────────────────────────────────────
QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
# If not in PATH, try to find from nix store
if ! command -v "$QEMU_BIN" >/dev/null 2>&1; then
  _found="$(which qemu-system-x86_64 2>/dev/null || true)"
  [ -n "$_found" ] && QEMU_BIN="$_found"
fi
RAW_IMAGE="$(pwd)/result/main.raw"
OVERLAY="${TMPDIR:-/tmp}/kexec-test-victim.qcow2"
SERIAL_LOG="${TMPDIR:-/tmp}/trampoline-serial.log"
QEMU_PID_FILE="${TMPDIR:-/tmp}/kexec-test-qemu.pid"
HOST_SSH_PORT=2222 # QEMU forwards this → guest:1022
QEMU_MEM=2048      # MiB; keep ≥ 1500 so initramfs + swap fit in RAM
DEPLOY_HOST="${DEPLOY_HOST:-can0}"
DEPLOY_DEVICE="${DEPLOY_DEVICE:-/dev/vda}"

# ── helpers ──────────────────────────────────────────────────────────────────
log() { printf '\e[1;36m[test-qemu]\e[0m %s\n' "$*"; }
die() {
  printf '\e[1;31m[test-qemu]\e[0m %s\n' "$*" >&2
  exit 1
}

resolve_qemu_bins() {
  local qemu_dir
  # qemu-img lives in the same nix-store bin/ as qemu-system-x86_64.
  # The devshell may not put qemu-img in PATH even if qemu-system is there.
  if qemu-img --version >/dev/null 2>&1; then
    QEMU_IMG_BIN="qemu-img"
  else
    qemu_dir="$(dirname "$(which "$QEMU_BIN")")"
    QEMU_IMG_BIN="${qemu_dir}/qemu-img"
    [ -x "$QEMU_IMG_BIN" ] || die "qemu-img not found alongside $QEMU_BIN"
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --host)
      DEPLOY_HOST="$2"
      shift 2
      ;;
    --device)
      DEPLOY_DEVICE="$2"
      shift 2
      ;;
    --mem)
      QEMU_MEM="$2"
      shift 2
      ;;
    --port)
      HOST_SSH_PORT="$2"
      shift 2
      ;;
    -h | --help)
      grep '^#' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) die "Unknown argument: $1" ;;
    esac
  done
}

# ── cleanup ──────────────────────────────────────────────────────────────────
cleanup_qemu() {
  if [ -f "$QEMU_PID_FILE" ]; then
    local pid
    pid="$(cat "$QEMU_PID_FILE")"
    if kill -0 "$pid" 2>/dev/null; then
      log "Stopping QEMU (pid $pid)"
      kill "$pid" 2>/dev/null || true
    fi
    rm -f "$QEMU_PID_FILE"
  fi
}
trap cleanup_qemu EXIT

# ── step 1: create overlay ───────────────────────────────────────────────────
create_overlay() {
  [ -f "$RAW_IMAGE" ] || die "result/main.raw not found. Build it first:
    nix build .#nixosConfigurations.${DEPLOY_HOST}.config.system.build.diskoImages"

  if [ -f "$OVERLAY" ]; then
    log "Reusing existing overlay: $OVERLAY"
    log "(delete $OVERLAY to start fresh)"
  else
    log "Creating QCOW2 overlay over $RAW_IMAGE"
    "$QEMU_BIN" -version >/dev/null 2>&1 ||
      die "qemu-system-x86_64 not found. Run: nix shell nixpkgs#qemu"
    # qemu-img is shipped alongside qemu-system-x86_64
    "$QEMU_IMG_BIN" create -f qcow2 -b "$RAW_IMAGE" -F raw "$OVERLAY"
    log "Overlay created: $OVERLAY"
  fi
}

# ── step 2: start QEMU ───────────────────────────────────────────────────────
start_qemu() {
  # Kill any leftover instance
  cleanup_qemu

  >"$SERIAL_LOG" # truncate log

  log "Starting QEMU with $QEMU_MEM MiB RAM"
  log "Serial log: $SERIAL_LOG"
  log "SSH port:   localhost:${HOST_SSH_PORT} → guest:1022"
  log ""
  log "TIP: in another terminal run:"
  log "     tail -f $SERIAL_LOG"
  log ""

  # We use -nographic + -serial file:... so the terminal isn't eaten by QEMU.
  # If you want an interactive console, replace:
  #   -serial file:"$SERIAL_LOG"
  # with:
  #   -serial stdio
  # and remove -nographic (use -display none instead).
  "$QEMU_BIN" \
    -name "kexec-test-victim" \
    -enable-kvm \
    -cpu host \
    -m "${QEMU_MEM}" \
    -nographic \
    -serial "file:${SERIAL_LOG}" \
    -device virtio-net-pci,netdev=net0 \
    -netdev "user,id=net0,hostfwd=tcp::${HOST_SSH_PORT}-:1022,hostfwd=tcp::2200-:22" \
    -drive "file=${OVERLAY},if=virtio,format=qcow2,cache=unsafe" \
    &
  echo $! >"$QEMU_PID_FILE"
  log "QEMU started (pid $!)"
}

# ── step 3: wait for SSH ─────────────────────────────────────────────────────
wait_for_ssh() {
  local i
  log "Waiting for guest SSH on localhost:${HOST_SSH_PORT} (up to 3 min)..."
  log "(serial log will be quiet during NixOS boot; trampoline output appears AFTER kexec)"
  for ((i = 1; i <= 90; i++)); do
    if timeout 4 ssh \
      -T \
      -o ConnectTimeout=3 \
      -o BatchMode=yes \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o ControlMaster=no \
      -o ControlPath=none \
      -p "$HOST_SSH_PORT" \
      root@localhost \
      'echo ok' >/dev/null 2>&1; then
      log "Guest SSH is up"
      return 0
    fi
    printf '.'
    sleep 2
  done
  echo
  die "Guest SSH did not come up in time. Check $SERIAL_LOG for boot errors."
}

# ── step 4: run deploy ───────────────────────────────────────────────────────
run_deploy() {
  log "Running deploy-live-kexec.sh against localhost:${HOST_SSH_PORT}"
  log "Serial output (trampoline /init) → $SERIAL_LOG"
  log "---"

  bash ./scripts/deploy-live-kexec.sh \
    --host "$DEPLOY_HOST" \
    --target-host "root@localhost" \
    --port "$HOST_SSH_PORT" \
    --trampoline-port "$HOST_SSH_PORT" \
    --device "$DEPLOY_DEVICE"
}

# ── main ─────────────────────────────────────────────────────────────────────
parse_args "$@"
resolve_qemu_bins
create_overlay
start_qemu

log ""
log "Waiting 10 seconds before checking SSH (BIOS POST + NixOS stage-1 boot)..."
sleep 10

wait_for_ssh
run_deploy
