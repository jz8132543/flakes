#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: deploy-live-kexec.sh --host NAME --target-host user@host --device /dev/sdX [options]

Options:
  --port PORT                  SSH port for the initial host (default: 22)
  --identity-file PATH         SSH private key for the initial connection
  --device PATH                Target block device to overwrite
  --swap-size-mb N             Create a temporary swapfile before kexec (default: 1024)
  --no-swap                    Skip temporary swapfile creation
  --alpine-release NAME        Alpine release path (default: latest-stable)
  --alpine-mirror URL          Alpine mirror root (default: https://dl-cdn.alpinelinux.org/alpine)
  --alpine-flavor NAME         Alpine netboot flavor (default: virt)
  --trampoline-port PORT       SSH port exposed by the in-memory trampoline (default: same as --port)

Behavior:
1. Build or reuse the target raw image locally.
2. Download Alpine netboot kernel/initramfs locally.
3. Build a tiny SSH trampoline initramfs and kexec into it on the target.
4. Reconnect automatically to the in-memory trampoline.
5. Reuse deploy-raw-image.sh --only-stream to write the image safely from RAM.
EOF
  exit 1
}

log() {
  printf '[deploy-live-kexec] %s\n' "$*"
}

die() {
  printf '[deploy-live-kexec] %s\n' "$*" >&2
  exit 1
}

HOST=""
TARGET_HOST=""
PORT=22
DEVICE=""
IDENTITY_FILE=""
SWAP_SIZE_MB=1024
USE_SWAP="yes"
ALPINE_RELEASE="latest-stable"
ALPINE_MIRROR="https://dl-cdn.alpinelinux.org/alpine"
ALPINE_FLAVOR="virt"
TRAMPOLINE_PORT=""

TARGET_SYSTEM=""
ALPINE_ARCH=""
TEMP_DIR=""
INITIAL_AUTH_MODE=""
REMOTE_ROOT="/run/nixos-kexec"
REMOTE_BUSYBOX="${REMOTE_ROOT}/busybox"
REMOTE_KEXEC="${REMOTE_ROOT}/kexec"
REMOTE_KERNEL="${REMOTE_ROOT}/vmlinuz"
REMOTE_INITRAMFS="${REMOTE_ROOT}/initramfs"
TRAMPOLINE_IDENTITY_FILE=""
INITIAL_AUTHORIZED_KEYS_FILE=""
LOCAL_BUSYBOX=""
LOCAL_DROPBEAR=""
LOCAL_DROPBEARKEY=""
LOCAL_KEXEC=""
LOCAL_KERNEL=""
LOCAL_INITRAMFS=""
LOCAL_OVERLAY=""

SSH_CMD=()
SSH_BASE_OPTS=()
INITIAL_AUTH_OPTS=()
TRAMPOLINE_AUTH_OPTS=()

cleanup() {
  if [ -n "${TEMP_DIR}" ] && [ -d "${TEMP_DIR}" ]; then
    rm -rf "${TEMP_DIR}"
  fi
}

cleanup_remote() {
  log "Cleaning up stale remote state from previous runs"
  initial_ssh '
    # Kill leftover kexec / dropbear from a previous trampoline attempt.
    # We deliberately do NOT kill sshd (the current session carrier).
    for proc in kexec dropbear; do
      pids=$(pgrep -x "$proc" 2>/dev/null || true)
      [ -n "$pids" ] && kill -9 $pids 2>/dev/null || true
    done
    # Remove stale work directory (under /run so always a plain tmpfs dir).
    rm -rf /run/nixos-kexec
    # Also clean up the old /tmp location in case it is accessible.
    rm -rf /tmp/nixos-kexec 2>/dev/null || true
    # Remove an old swapfile left by a previous run.
    swapoff /swapfile.nixos-kexec 2>/dev/null || true
    rm -f /swapfile.nixos-kexec 2>/dev/null || true
  ' || log "Warning: remote cleanup encountered errors (continuing)"
}

trap cleanup EXIT

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
    --identity-file)
      IDENTITY_FILE="$2"
      shift 2
      ;;
    --device)
      DEVICE="$2"
      shift 2
      ;;
    --swap-size-mb)
      SWAP_SIZE_MB="$2"
      shift 2
      ;;
    --no-swap)
      USE_SWAP="no"
      shift 1
      ;;
    --alpine-release)
      ALPINE_RELEASE="$2"
      shift 2
      ;;
    --alpine-mirror)
      ALPINE_MIRROR="$2"
      shift 2
      ;;
    --alpine-flavor)
      ALPINE_FLAVOR="$2"
      shift 2
      ;;
    --trampoline-port)
      TRAMPOLINE_PORT="$2"
      shift 2
      ;;
    -h | --help)
      usage
      ;;
    *)
      die "Unknown arg: $1"
      ;;
    esac
  done

  [ -n "$HOST" ] || die "--host is required"
  [ -n "$TARGET_HOST" ] || die "--target-host is required"
  [ -n "$DEVICE" ] || die "--device is required"

  if [ -z "$TRAMPOLINE_PORT" ]; then
    TRAMPOLINE_PORT="$PORT"
  fi
}

prepare_temp_dir() {
  if [ -z "${TEMP_DIR}" ]; then
    TEMP_DIR="$(mktemp -d)"
  fi
}

resolve_identity_file() {
  local candidate

  if [ -n "$IDENTITY_FILE" ]; then
    [ -f "$IDENTITY_FILE" ] || die "Identity file not found: $IDENTITY_FILE"
    return
  fi

  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    if [ -f "$candidate" ]; then
      IDENTITY_FILE="$candidate"
      return
    fi
  done < <(ssh -G -p "$PORT" "$TARGET_HOST" 2>/dev/null | awk '/^identityfile / { print $2 }')

  if [ -f "${HOME}/.ssh/id_ed25519" ]; then
    IDENTITY_FILE="${HOME}/.ssh/id_ed25519"
  fi
}

setup_initial_ssh() {
  SSH_BASE_OPTS=(
    -o StrictHostKeyChecking=accept-new
    -o ServerAliveInterval=15
    -o ServerAliveCountMax=4
    -o ControlMaster=no
    -o ControlPath=none
    -p "$PORT"
  )

  # Always attempt key auth first.
  INITIAL_AUTH_MODE="key"
  INITIAL_AUTH_OPTS=()
  [ -n "$IDENTITY_FILE" ] && INITIAL_AUTH_OPTS=(-i "$IDENTITY_FILE")
  SSH_CMD=(ssh)
}

install_pubkey_via_password() {
  # Use ssh-copy-id which prompts for password interactively – no sshpass needed.
  local key_opt=()
  [ -n "$IDENTITY_FILE" ] && key_opt=(-i "${IDENTITY_FILE}.pub")

  log "Key auth failed – running ssh-copy-id to install public key (password prompt follows)"
  ssh-copy-id "${SSH_BASE_OPTS[@]}" "${key_opt[@]}" "$TARGET_HOST" ||
    die "ssh-copy-id failed for ${TARGET_HOST}"
  log "Public key installed via ssh-copy-id"
}

initial_ssh() {
  "${SSH_CMD[@]}" "${SSH_BASE_OPTS[@]}" "${INITIAL_AUTH_OPTS[@]}" "$TARGET_HOST" "$@"
}

upload_initial_file() {
  local local_path="$1"
  local remote_path="$2"

  cat "$local_path" | initial_ssh "cat > $(printf '%q' "$remote_path")"
}

ensure_initial_access() {
  # Fast path: key auth works already (with retry for MaxStartups transients).
  local retries=10 delay=8 i
  local key_ok=no
  for ((i = 1; i <= retries; i++)); do
    if "${SSH_CMD[@]}" "${SSH_BASE_OPTS[@]}" "${INITIAL_AUTH_OPTS[@]}" -o BatchMode=yes "$TARGET_HOST" true >/dev/null 2>&1; then
      key_ok=yes
      break
    fi
    log "SSH attempt ${i}/${retries} to ${TARGET_HOST} failed; retrying in ${delay}s"
    sleep "$delay"
  done

  if [ "$key_ok" = "no" ]; then
    # Key auth failed – install the public key via ssh-copy-id (interactive password).
    install_pubkey_via_password
    # Retry key auth after key installation.
    for ((i = 1; i <= retries; i++)); do
      if "${SSH_CMD[@]}" "${SSH_BASE_OPTS[@]}" "${INITIAL_AUTH_OPTS[@]}" -o BatchMode=yes "$TARGET_HOST" true >/dev/null 2>&1; then
        key_ok=yes
        break
      fi
      log "Post-install SSH attempt ${i}/${retries} failed; retrying in ${delay}s"
      sleep "$delay"
    done
    [ "$key_ok" = "yes" ] ||
      die "SSH key auth still failing after ssh-copy-id for ${TARGET_HOST}"
  fi

  log "Key-based SSH to ${TARGET_HOST} succeeded"

  # Idempotently ensure our pubkey is present (defensive).
  local pub_key=""
  if [ -n "$IDENTITY_FILE" ] && [ -f "${IDENTITY_FILE}.pub" ]; then
    pub_key="$(cat "${IDENTITY_FILE}.pub")"
  elif command -v ssh-add >/dev/null 2>&1; then
    pub_key="$(ssh-add -L 2>/dev/null | head -1 || true)"
  fi
  if [ -n "$pub_key" ]; then
    initial_ssh "
      mkdir -p ~/.ssh && chmod 700 ~/.ssh
      touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
      grep -qxF $(printf '%q' "$pub_key") ~/.ssh/authorized_keys 2>/dev/null \
        || printf '%s\n' $(printf '%q' "$pub_key") >> ~/.ssh/authorized_keys
    " >/dev/null 2>&1 && log "Public key ensured on ${TARGET_HOST}" || true
  fi
}

collect_initial_authorized_keys() {
  local auth_keys_file
  local candidate

  prepare_temp_dir
  auth_keys_file="${TEMP_DIR}/initial-authorized_keys"
  : >"$auth_keys_file"

  if [ -n "$IDENTITY_FILE" ] && [ -f "${IDENTITY_FILE}.pub" ]; then
    cat "${IDENTITY_FILE}.pub" >>"$auth_keys_file"
    printf '\n' >>"$auth_keys_file"
  fi

  while IFS= read -r candidate; do
    case "$candidate" in
    "" | none)
      continue
      ;;
    \~/*)
      candidate="${HOME}/${candidate#~/}"
      ;;
    esac

    if [ -f "${candidate}.pub" ]; then
      cat "${candidate}.pub" >>"$auth_keys_file"
      printf '\n' >>"$auth_keys_file"
    fi
  done < <(ssh -G -p "$PORT" "$TARGET_HOST" 2>/dev/null | awk '/^identityfile / { print $2 }')

  while IFS= read -r candidate; do
    [ -f "$candidate" ] || continue
    cat "$candidate" >>"$auth_keys_file"
    printf '\n' >>"$auth_keys_file"
  done < <(find "${HOME}/.ssh" -maxdepth 1 -type f -name '*.pub' 2>/dev/null | LC_ALL=C sort)

  if command -v ssh-add >/dev/null 2>&1; then
    ssh-add -L 2>/dev/null >>"$auth_keys_file" || true
    printf '\n' >>"$auth_keys_file"
  fi

  awk 'NF && !seen[$0]++' "$auth_keys_file" >"${auth_keys_file}.dedup"
  mv "${auth_keys_file}.dedup" "$auth_keys_file"

  [ -s "$auth_keys_file" ] || die "No public keys available to seed ${TARGET_HOST}"
  INITIAL_AUTHORIZED_KEYS_FILE="$auth_keys_file"
}

determine_target_system() {
  TARGET_SYSTEM="$(nix eval --raw --experimental-features 'nix-command flakes' ".#nixosConfigurations.${HOST}.pkgs.stdenv.hostPlatform.system")"
  case "$TARGET_SYSTEM" in
  x86_64-linux)
    ALPINE_ARCH="x86_64"
    ;;
  *)
    die "Unsupported target system for Alpine trampoline: ${TARGET_SYSTEM}"
    ;;
  esac
}

prepare_local_artifacts() {
  local kernel_url
  local initramfs_url
  local overlay_root
  local hostkey_file
  local init_script_file
  local udhcpc_script_file
  local alpine_dir
  local symlink
  local dropbear_prefix

  prepare_temp_dir

  log "Building static trampoline tools"
  LOCAL_BUSYBOX="$(nix build --no-link --print-out-paths --experimental-features 'nix-command flakes' nixpkgs#pkgsStatic.busybox)/bin/busybox"
  dropbear_prefix="$(nix build --no-link --print-out-paths --experimental-features 'nix-command flakes' nixpkgs#pkgsStatic.dropbear)"
  LOCAL_DROPBEAR="${dropbear_prefix}/bin/dropbear"
  LOCAL_DROPBEARKEY="${dropbear_prefix}/bin/dropbearkey"
  LOCAL_KEXEC="$(nix build --no-link --print-out-paths --experimental-features 'nix-command flakes' nixpkgs#pkgsStatic.kexec-tools)/bin/kexec"

  kernel_url="${ALPINE_MIRROR}/${ALPINE_RELEASE}/releases/${ALPINE_ARCH}/netboot/vmlinuz-${ALPINE_FLAVOR}"
  initramfs_url="${ALPINE_MIRROR}/${ALPINE_RELEASE}/releases/${ALPINE_ARCH}/netboot/initramfs-${ALPINE_FLAVOR}"
  alpine_dir="${TEMP_DIR}/alpine"
  mkdir -p "$alpine_dir"

  log "Downloading Alpine netboot kernel"
  curl --fail --location --silent --show-error --output "${alpine_dir}/vmlinuz" "$kernel_url"
  log "Downloading Alpine netboot initramfs"
  curl --fail --location --silent --show-error --output "${alpine_dir}/initramfs" "$initramfs_url"

  LOCAL_KERNEL="${TEMP_DIR}/trampoline-kernel"
  LOCAL_INITRAMFS="${TEMP_DIR}/trampoline-initramfs"
  LOCAL_OVERLAY="${TEMP_DIR}/trampoline-overlay.cpio.gz"
  cp "${alpine_dir}/vmlinuz" "$LOCAL_KERNEL"

  TRAMPOLINE_IDENTITY_FILE="${TEMP_DIR}/trampoline_id_ed25519"
  ssh-keygen -q -t ed25519 -N '' -f "$TRAMPOLINE_IDENTITY_FILE" >/dev/null

  overlay_root="${TEMP_DIR}/overlay"
  mkdir -p \
    "${overlay_root}/bin" \
    "${overlay_root}/dev" \
    "${overlay_root}/etc/dropbear" \
    "${overlay_root}/root/.ssh" \
    "${overlay_root}/usr/share/udhcpc"

  cp "$LOCAL_BUSYBOX" "${overlay_root}/bin/busybox"
  cp "$LOCAL_DROPBEAR" "${overlay_root}/bin/dropbear"
  cp "$LOCAL_KEXEC" "${overlay_root}/bin/kexec"

  for symlink in sh mount mkdir mdev modprobe udhcpc ip sleep cat ls dd sync reboot poweroff ps kill setsid wget cp rm mv chmod ln mkswap swapon swapoff ifconfig route dmesg uname grep awk sed; do
    ln -s busybox "${overlay_root}/bin/${symlink}"
  done

  # Seed authorized_keys with:
  # 1. the ephemeral trampoline key (used by this script to drive the deployment)
  # 2. the operator's own public key (allows reconnect if the script is interrupted)
  {
    cat "${TRAMPOLINE_IDENTITY_FILE}.pub"
    printf '\n'
    if [ -n "$IDENTITY_FILE" ] && [ -f "${IDENTITY_FILE}.pub" ]; then
      cat "${IDENTITY_FILE}.pub"
      printf '\n'
    fi
    # Also pull in any keys from the SSH agent so the operator can reconnect manually.
    ssh-add -L 2>/dev/null || true
  } | awk 'NF && !seen[$0]++' >"${overlay_root}/root/.ssh/authorized_keys"
  chmod 0700 "${overlay_root}/root/.ssh"
  chmod 0600 "${overlay_root}/root/.ssh/authorized_keys"

  hostkey_file="${overlay_root}/etc/dropbear/dropbear_ed25519_host_key"
  "$LOCAL_DROPBEARKEY" -t ed25519 -f "$hostkey_file" >/dev/null 2>&1

  cat >"${overlay_root}/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/sh
EOF
  cat >"${overlay_root}/etc/group" <<'EOF'
root:x:0:
EOF
  cat >"${overlay_root}/etc/resolv.conf" <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

  udhcpc_script_file="${overlay_root}/usr/share/udhcpc/default.script"
  cat >"$udhcpc_script_file" <<'EOF'
#!/bin/sh
set -eu
PATH=/bin:/sbin

cidr_prefix() {
  case "$1" in
    255.255.255.255) echo 32 ;;
    255.255.255.254) echo 31 ;;
    255.255.255.252) echo 30 ;;
    255.255.255.248) echo 29 ;;
    255.255.255.240) echo 28 ;;
    255.255.255.224) echo 27 ;;
    255.255.255.192) echo 26 ;;
    255.255.255.128) echo 25 ;;
    255.255.255.0) echo 24 ;;
    255.255.254.0) echo 23 ;;
    255.255.252.0) echo 22 ;;
    255.255.248.0) echo 21 ;;
    255.255.240.0) echo 20 ;;
    255.255.224.0) echo 19 ;;
    255.255.192.0) echo 18 ;;
    255.255.128.0) echo 17 ;;
    255.255.0.0) echo 16 ;;
    255.254.0.0) echo 15 ;;
    255.252.0.0) echo 14 ;;
    255.248.0.0) echo 13 ;;
    255.240.0.0) echo 12 ;;
    255.224.0.0) echo 11 ;;
    255.192.0.0) echo 10 ;;
    255.128.0.0) echo 9 ;;
    255.0.0.0) echo 8 ;;
    *) echo 24 ;;
  esac
}

case "${1:-}" in
  deconfig)
    ip addr flush dev "$interface" || true
    ;;
  bound|renew)
    ip addr flush dev "$interface" || true
    ip addr add "${ip}/$(cidr_prefix "${subnet:-255.255.255.0}")" dev "$interface"
    if [ -n "${router:-}" ]; then
      ip route replace default via "${router%% *}" dev "$interface"
    fi
    : > /etc/resolv.conf
    for ns in ${dns:-}; do
      printf 'nameserver %s\n' "$ns" >> /etc/resolv.conf
    done
    ;;
esac

exit 0
EOF
  chmod 0755 "$udhcpc_script_file"

  init_script_file="${overlay_root}/init"
  cat >"$init_script_file" <<EOF
#!/bin/busybox sh
# PID 1 – must never exit.  No set -e here: a failed command must not kill init.
PATH=/bin:/sbin
export HOME=/root USER=root LOGNAME=root

# Redirect output as early as possible; use /dev/console if it exists (kernel
# guarantees at least the device node), or fall back to nothing.
[ -c /dev/console ] && exec >/dev/console 2>&1

say() { echo "[trampoline] \$*"; }

say "--- init started ---"

# ── 1. essential mounts ──────────────────────────────────────────────────────
say "mounting devtmpfs"
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
# Now /dev/console is definitely a real chardev; re-attach if needed.
[ -c /dev/console ] && exec >/dev/console 2>&1

mkdir -p /proc /sys /run /tmp /dev/pts /dev/shm /root

say "mounting proc"
mount -t proc    proc    /proc   2>/dev/null || true
say "mounting sysfs"
mount -t sysfs   sysfs   /sys    2>/dev/null || true
mount -t devpts  devpts  /dev/pts 2>/dev/null || true
mount -t tmpfs -o mode=0755,nosuid,nodev tmpfs /run  2>/dev/null || true
mount -t tmpfs -o mode=1777,nosuid,nodev tmpfs /tmp  2>/dev/null || true

# Static device nodes (fallback if devtmpfs didn't create them)
for n in "null c 1 3" "zero c 1 5" "full c 1 7" "random c 1 8" "urandom c 1 9" "tty c 5 0" "console c 5 1"; do
  set -- \$n
  [ -e "/dev/\$1" ] || mknod -m 666 "/dev/\$1" \$2 \$3 \$4 2>/dev/null || true
done

# ── 2. kernel hotplug / module loading ──────────────────────────────────────
say "setting up mdev"
echo /bin/mdev > /proc/sys/kernel/hotplug 2>/dev/null || true
mdev -s 2>/dev/null || true

say "loading drivers"
for mod in virtio_pci virtio_blk virtio_scsi virtio_net \
           e1000 e1000e ixgbe vmxnet3 xen_netfront \
           ahci libahci nvme nvme_core sd_mod; do
  modprobe "\$mod" 2>/dev/null || true
done
mdev -s 2>/dev/null || true

# ── 3. networking ─────────────────────────────────────────────────────────
say "configuring network"
ip link set lo up 2>/dev/null || true

net_ok=no
# Give udev/mdev a moment to finish renaming interfaces
sleep 1
for devpath in /sys/class/net/*; do
  [ -e "\$devpath" ] || continue
  iface="\${devpath##*/}"
  [ "\$iface" = lo ] && continue
  say "trying DHCP on \$iface"
  ip link set "\$iface" up 2>/dev/null || true
  # -t attempts, -T timeout per attempt, -A initial hold-off, -n exit on failure
  if udhcpc -n -q -t 15 -T 3 -A 1 -i "\$iface" 2>/dev/null; then
    say "DHCP OK on \$iface"
    net_ok=yes
    break
  fi
  say "DHCP failed on \$iface (continuing)"
done

say "network state:"
ip addr show 2>/dev/null || true
ip route show 2>/dev/null || true

if [ "\$net_ok" = no ]; then
  say "WARNING: no DHCP lease obtained – SSH will be unreachable"
fi

# ── 4. dropbear SSH ──────────────────────────────────────────────────────────
say "starting dropbear on port ${TRAMPOLINE_PORT}"
while true; do
  # -E log to stderr  -F foreground  -s no-password  -g allow-root-without-key
  dropbear -E -F -s -g -p ${TRAMPOLINE_PORT} \
    -r /etc/dropbear/dropbear_ed25519_host_key 2>&1 || true
  say "dropbear exited – restarting in 2s"
  sleep 2
done
EOF
  chmod 0755 "$init_script_file"

  (
    cd "$overlay_root"
    find . -print0 | LC_ALL=C sort -z | cpio --null -o -H newc | gzip -1 >"$LOCAL_OVERLAY"
  ) >/dev/null 2>&1

  cat "${alpine_dir}/initramfs" "$LOCAL_OVERLAY" >"$LOCAL_INITRAMFS"
}

prepare_remote_bootstrap() {
  log "Bootstrapping static tools to target"
  initial_ssh "mkdir -p $(printf '%q' "$REMOTE_ROOT")"
  upload_initial_file "$LOCAL_BUSYBOX" "$REMOTE_BUSYBOX"
  upload_initial_file "$LOCAL_KEXEC" "$REMOTE_KEXEC"
  initial_ssh "chmod 0755 $(printf '%q' "$REMOTE_BUSYBOX") $(printf '%q' "$REMOTE_KEXEC")"
}

seed_remote_authorized_keys() {
  local remote_key_seed

  [ "$INITIAL_AUTH_MODE" = "password" ] || return 0

  collect_initial_authorized_keys
  remote_key_seed="${REMOTE_ROOT}/authorized_keys.seed"

  log "Seeding remote authorized_keys so the rest of the deployment stays passwordless"
  upload_initial_file "$INITIAL_AUTHORIZED_KEYS_FILE" "$remote_key_seed"
  initial_ssh "
    set -eu
    BUSYBOX=$(printf '%q' "$REMOTE_BUSYBOX")
    AUTH_DIR=\$HOME/.ssh
    AUTH_FILE=\$AUTH_DIR/authorized_keys
    TMP_FILE=\$AUTH_FILE.tmp
    \$BUSYBOX mkdir -p \"\$AUTH_DIR\"
    \$BUSYBOX chmod 0700 \"\$AUTH_DIR\"
    if [ -f \"\$AUTH_FILE\" ]; then
      \$BUSYBOX cat \"\$AUTH_FILE\" $(printf '%q' "$remote_key_seed") > \"\$TMP_FILE\"
    else
      \$BUSYBOX cat $(printf '%q' "$remote_key_seed") > \"\$TMP_FILE\"
    fi
    \$BUSYBOX awk 'NF && !seen[\$0]++' \"\$TMP_FILE\" > \"\$AUTH_FILE\"
    \$BUSYBOX chmod 0600 \"\$AUTH_FILE\"
    \$BUSYBOX rm -f \"\$TMP_FILE\" $(printf '%q' "$remote_key_seed")
  "

  SSH_CMD=(ssh)
  if [ -n "$IDENTITY_FILE" ]; then
    INITIAL_AUTH_OPTS=(-i "$IDENTITY_FILE")
  else
    INITIAL_AUTH_OPTS=()
  fi
  INITIAL_AUTH_MODE="key"
  unset SSH_PASSWORD SSHPASS || true
  ensure_initial_access
}

prepare_remote_swap() {
  [ "$USE_SWAP" = "yes" ] || return 0

  log "Preparing temporary ${SWAP_SIZE_MB}MiB swapfile"
  initial_ssh "
    set -eu
    BUSYBOX=$(printf '%q' "$REMOTE_BUSYBOX")
    SWAPFILE=/swapfile.nixos-kexec
    \$BUSYBOX swapoff \"\$SWAPFILE\" >/dev/null 2>&1 || true
    \$BUSYBOX rm -f \"\$SWAPFILE\"
    \$BUSYBOX dd if=/dev/zero of=\"\$SWAPFILE\" bs=1M count=$(printf '%q' "$SWAP_SIZE_MB") status=none
    \$BUSYBOX chmod 0600 \"\$SWAPFILE\"
    \$BUSYBOX mkswap \"\$SWAPFILE\" >/dev/null
    \$BUSYBOX swapon \"\$SWAPFILE\"
  " || log "Warning: failed to enable temporary swap; continuing without it"
}

upload_kexec_payload() {
  log "Uploading Alpine trampoline kernel and initramfs"
  upload_initial_file "$LOCAL_KERNEL" "$REMOTE_KERNEL"
  upload_initial_file "$LOCAL_INITRAMFS" "$REMOTE_INITRAMFS"
  initial_ssh "chmod 0644 $(printf '%q' "$REMOTE_KERNEL") $(printf '%q' "$REMOTE_INITRAMFS")"
}

enter_trampoline() {
  local cmdline

  # nomodeset: avoids VGA mode-switch hang on some hypervisors (Alibaba Cloud KVM)
  # ip=dhcp removed: our custom /init handles DHCP; having both causes races/hangs
  cmdline="console=ttyS0 console=tty0 nomodeset panic=30 init=/init"

  log "Loading Alpine trampoline with kexec"
  initial_ssh "
    set -eu
    KEXEC=$(printf '%q' "$REMOTE_KEXEC")
    KERNEL=$(printf '%q' "$REMOTE_KERNEL")
    INITRD=$(printf '%q' "$REMOTE_INITRAMFS")
    \$KEXEC -l \"\$KERNEL\" --initrd=\"\$INITRD\" --command-line=$(printf '%q' "$cmdline")
    $(printf '%q' "$REMOTE_BUSYBOX") sync
    $(printf '%q' "$REMOTE_BUSYBOX") setsid $(printf '%q' "$REMOTE_BUSYBOX") sh -c $(printf '%q' "sleep 2; exec ${REMOTE_KEXEC} -e") >/dev/null 2>&1 &
  "

  log "Waiting for the current system to go down"
  sleep 5
}

wait_for_trampoline() {
  local i

  # Auth options for trampoline: try ephemeral key first, fall back to user identity
  TRAMPOLINE_AUTH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o GlobalKnownHostsFile=/dev/null)
  # Build list of identity files to try: ephemeral key + user's own key
  local trampoline_id_files=()
  [ -f "$TRAMPOLINE_IDENTITY_FILE" ] && trampoline_id_files+=("$TRAMPOLINE_IDENTITY_FILE")
  [ -n "$IDENTITY_FILE" ] && [ -f "$IDENTITY_FILE" ] && trampoline_id_files+=("$IDENTITY_FILE")

  log "Waiting for in-memory trampoline SSH on ${TARGET_HOST}:${TRAMPOLINE_PORT}"
  for ((i = 1; i <= 180; i++)); do
    local ok=no
    if [ ${#trampoline_id_files[@]} -gt 0 ]; then
      # Try each available identity file
      local id_file
      for id_file in "${trampoline_id_files[@]}"; do
        if timeout 6 ssh \
          -T \
          -o ConnectTimeout=3 \
          -o ConnectionAttempts=1 \
          -o ControlMaster=no \
          -o ControlPath=none \
          -o RequestTTY=no \
          "${TRAMPOLINE_AUTH_OPTS[@]}" \
          -i "$id_file" \
          -p "$TRAMPOLINE_PORT" \
          "$TARGET_HOST" \
          'echo trampoline-ok' >/dev/null 2>&1; then
          log "Trampoline SSH is ready (key: ${id_file})"
          # Update TRAMPOLINE_IDENTITY_FILE to whichever worked
          TRAMPOLINE_IDENTITY_FILE="$id_file"
          ok=yes
          break
        fi
      done
    else
      # Rely on ssh-agent when no explicit identity files available
      if timeout 6 ssh \
        -T \
        -o ConnectTimeout=3 \
        -o ConnectionAttempts=1 \
        -o ControlMaster=no \
        -o ControlPath=none \
        -o RequestTTY=no \
        "${TRAMPOLINE_AUTH_OPTS[@]}" \
        -p "$TRAMPOLINE_PORT" \
        "$TARGET_HOST" \
        'echo trampoline-ok' >/dev/null 2>&1; then
        log "Trampoline SSH is ready (via ssh-agent)"
        ok=yes
      fi
    fi
    [ "$ok" = yes ] && return 0
    sleep 2
  done

  die "Timed out waiting for Alpine trampoline SSH"
}

stream_image_from_trampoline() {
  log "Streaming raw image from the in-memory trampoline"
  local id_file_arg=()
  [ -n "$TRAMPOLINE_IDENTITY_FILE" ] && [ -f "$TRAMPOLINE_IDENTITY_FILE" ] && id_file_arg=(--identity-file "$TRAMPOLINE_IDENTITY_FILE")
  ./scripts/deploy-raw-image.sh \
    --target ".#nixosConfigurations.${HOST}.config.system.build.diskoImages" \
    --target-host "$TARGET_HOST" \
    --port "$TRAMPOLINE_PORT" \
    "${id_file_arg[@]+${id_file_arg[@]}}" \
    --device "$DEVICE" \
    --only-stream
}

reboot_final_system() {
  log "Rebooting the trampoline after disk sync"
  local id_opts=()
  [ -n "$TRAMPOLINE_IDENTITY_FILE" ] && [ -f "$TRAMPOLINE_IDENTITY_FILE" ] && id_opts=(-i "$TRAMPOLINE_IDENTITY_FILE")
  ssh \
    -T \
    -o CanonicalizeHostname=no \
    -o ControlMaster=no \
    -o ControlPath=none \
    "${TRAMPOLINE_AUTH_OPTS[@]}" \
    "${id_opts[@]+${id_opts[@]}}" \
    -p "$TRAMPOLINE_PORT" \
    "$TARGET_HOST" \
    '/bin/busybox sh -c "/bin/busybox sync; /bin/busybox sleep 15; exec /bin/busybox reboot -f"' || true
}

report_memory_footprint() {
  local kernel_bytes
  local initramfs_bytes
  local overlay_bytes
  local initramfs_unpacked_bytes

  kernel_bytes="$(wc -c <"$LOCAL_KERNEL")"
  initramfs_bytes="$(wc -c <"$LOCAL_INITRAMFS")"
  overlay_bytes="$(wc -c <"$LOCAL_OVERLAY")"
  initramfs_unpacked_bytes="$(gzip -l "$LOCAL_INITRAMFS" | awk 'NR==2 { print $2 }')"

  log "Trampoline artifact sizes: kernel=$((kernel_bytes / 1024 / 1024))MiB initramfs-compressed=$((initramfs_bytes / 1024 / 1024))MiB overlay=$((overlay_bytes / 1024 / 1024))MiB initramfs-unpacked~= $((initramfs_unpacked_bytes / 1024 / 1024))MiB"
}

main() {
  parse_args "$@"
  resolve_identity_file
  setup_initial_ssh
  ensure_initial_access
  cleanup_remote
  determine_target_system
  prepare_local_artifacts
  report_memory_footprint
  prepare_remote_bootstrap
  seed_remote_authorized_keys
  prepare_remote_swap
  upload_kexec_payload
  enter_trampoline
  wait_for_trampoline
  stream_image_from_trampoline
  reboot_final_system
  log "Deployment finished. The target should reboot into the new system after flushing writes."
}

main "$@"
