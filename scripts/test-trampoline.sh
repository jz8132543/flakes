#!/usr/bin/env bash
# test-trampoline.sh – Build the kexec trampoline and boot it DIRECTLY in QEMU.
#
# This tests the /init script WITHOUT needing a victim VM.  QEMU receives the
# trampoline kernel + initramfs as if kexec had already occurred.
#
# Usage:
#   bash scripts/test-trampoline.sh [--port PORT]
#
# What you will see:
#   - Real-time serial output from the trampoline /init script
#   - SSH prompt on localhost:PORT once dropbear starts
#
# Press Ctrl-A X to quit QEMU.

set -euo pipefail
cd "$(dirname "$0")/.."

SSH_PORT=2222
TRAMPOLINE_PORT=22
# Locate qemu-system-x86_64 – prefer PATH, fall back to nix run
if command -v qemu-system-x86_64 >/dev/null 2>&1; then
  QEMU_BIN="qemu-system-x86_64"
else
  QEMU_BIN="$(which qemu-system-x86_64 2>/dev/null ||
    nix build --no-link --print-out-paths nixpkgs#qemu 2>/dev/null | head -1)/bin/qemu-system-x86_64"
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
  --port)
    SSH_PORT="$2"
    TRAMPOLINE_PORT="$2"
    shift 2
    ;;
  *)
    echo "Usage: $0 [--port PORT]"
    exit 1
    ;;
  esac
done

log() { printf '\e[1;36m[test-trampoline]\e[0m %s\n' "$*"; }

# ── build trampoline artifacts (same logic as deploy-live-kexec.sh) ──────────
TEMP_DIR="$(mktemp -d /tmp/trampoline-test.XXXXXX)"
trap 'rm -rf "$TEMP_DIR"' EXIT

log "Building static busybox + dropbear + kexec..."
LOCAL_BUSYBOX="$(nix build --no-link --print-out-paths --experimental-features 'nix-command flakes' nixpkgs#pkgsStatic.busybox)/bin/busybox"
DROPBEAR_PREFIX="$(nix build --no-link --print-out-paths --experimental-features 'nix-command flakes' nixpkgs#pkgsStatic.dropbear)"
LOCAL_DROPBEAR="${DROPBEAR_PREFIX}/bin/dropbear"
LOCAL_DROPBEARKEY="${DROPBEAR_PREFIX}/bin/dropbearkey"

ALPINE_RELEASE="latest-stable"
ALPINE_MIRROR="https://dl-cdn.alpinelinux.org/alpine"
ALPINE_FLAVOR="virt"
ALPINE_ARCH="x86_64"

ALPINE_DIR="${TEMP_DIR}/alpine"
mkdir -p "$ALPINE_DIR"

log "Downloading Alpine netboot kernel + initramfs..."
curl --fail --location --silent --show-error \
  -o "${ALPINE_DIR}/vmlinuz" \
  "${ALPINE_MIRROR}/${ALPINE_RELEASE}/releases/${ALPINE_ARCH}/netboot/vmlinuz-${ALPINE_FLAVOR}"
curl --fail --location --silent --show-error \
  -o "${ALPINE_DIR}/initramfs" \
  "${ALPINE_MIRROR}/${ALPINE_RELEASE}/releases/${ALPINE_ARCH}/netboot/initramfs-${ALPINE_FLAVOR}"

# Generate ephemeral SSH key pair
TRAMPOLINE_KEY="${TEMP_DIR}/trampoline_id"
ssh-keygen -q -t ed25519 -N '' -f "$TRAMPOLINE_KEY" >/dev/null
log "Trampoline key: ${TRAMPOLINE_KEY}"
log "Connect with: ssh -i ${TRAMPOLINE_KEY} -p ${SSH_PORT} -o StrictHostKeyChecking=no root@localhost"

# Build overlay (same structure as in deploy-live-kexec.sh)
OVERLAY_ROOT="${TEMP_DIR}/overlay"
mkdir -p \
  "${OVERLAY_ROOT}/bin" \
  "${OVERLAY_ROOT}/dev" \
  "${OVERLAY_ROOT}/etc/dropbear" \
  "${OVERLAY_ROOT}/root/.ssh" \
  "${OVERLAY_ROOT}/usr/share/udhcpc"

cp "$LOCAL_BUSYBOX" "${OVERLAY_ROOT}/bin/busybox"
cp "$LOCAL_DROPBEAR" "${OVERLAY_ROOT}/bin/dropbear"

for sym in sh mount mkdir mdev modprobe udhcpc ip sleep cat ls dd sync reboot \
  poweroff ps kill setsid wget cp rm mv chmod ln mkswap swapon swapoff \
  ifconfig route dmesg uname grep awk sed; do
  ln -sf busybox "${OVERLAY_ROOT}/bin/${sym}"
done

# authorized_keys: ephemeral key + SSH agent keys + ~/.ssh/*.pub
{
  cat "${TRAMPOLINE_KEY}.pub"
  printf '\n'
  ssh-add -L 2>/dev/null || true
  find "${HOME}/.ssh" -maxdepth 1 -name '*.pub' -exec cat {} \; 2>/dev/null || true
} | awk 'NF && !seen[$0]++' >"${OVERLAY_ROOT}/root/.ssh/authorized_keys"
chmod 0700 "${OVERLAY_ROOT}/root/.ssh"
chmod 0600 "${OVERLAY_ROOT}/root/.ssh/authorized_keys"

"$LOCAL_DROPBEARKEY" -t ed25519 -f "${OVERLAY_ROOT}/etc/dropbear/dropbear_ed25519_host_key" >/dev/null 2>&1

cat >"${OVERLAY_ROOT}/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/sh
EOF
cat >"${OVERLAY_ROOT}/etc/group" <<'EOF'
root:x:0:
EOF
cat >"${OVERLAY_ROOT}/etc/resolv.conf" <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

# udhcpc script (same as deploy-live-kexec.sh)
UDHCPC="${OVERLAY_ROOT}/usr/share/udhcpc/default.script"
cat >"$UDHCPC" <<'EOF'
#!/bin/sh
set -eu
PATH=/bin:/sbin
cidr_prefix() {
  case "$1" in
    255.255.255.0) echo 24 ;; 255.255.0.0) echo 16 ;; 255.0.0.0) echo 8 ;; *) echo 24 ;;
  esac
}
case "${1:-}" in
  deconfig) ip addr flush dev "$interface" 2>/dev/null || true ;;
  bound|renew)
    ip addr flush dev "$interface" 2>/dev/null || true
    ip addr add "${ip}/$(cidr_prefix "${subnet:-255.255.255.0}")" dev "$interface"
    [ -n "${router:-}" ] && ip route replace default via "${router%% *}" dev "$interface"
    : >/etc/resolv.conf
    for ns in ${dns:-}; do printf 'nameserver %s\n' "$ns" >>/etc/resolv.conf; done
    ;;
esac
exit 0
EOF
chmod 0755 "$UDHCPC"

# /init script (must match deploy-live-kexec.sh exactly – copy from there)
cat >"${OVERLAY_ROOT}/init" <<INIT_EOF
#!/bin/busybox sh
PATH=/bin:/sbin
export HOME=/root USER=root LOGNAME=root

[ -c /dev/console ] && exec >/dev/console 2>&1

say() { echo "[trampoline] \$*"; }
say "--- init started ---"

say "mounting devtmpfs"
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
[ -c /dev/console ] && exec >/dev/console 2>&1

mkdir -p /proc /sys /run /tmp /dev/pts /dev/shm /root

say "mounting proc"
mount -t proc    proc    /proc   2>/dev/null || true
say "mounting sysfs"
mount -t sysfs   sysfs   /sys    2>/dev/null || true
mount -t devpts  devpts  /dev/pts 2>/dev/null || true
mount -t tmpfs -o mode=0755,nosuid,nodev tmpfs /run  2>/dev/null || true
mount -t tmpfs -o mode=1777,nosuid,nodev tmpfs /tmp  2>/dev/null || true

for n in "null c 1 3" "zero c 1 5" "full c 1 7" "random c 1 8" "urandom c 1 9" "tty c 5 0" "console c 5 1"; do
  set -- \$n
  [ -e "/dev/\$1" ] || mknod -m 666 "/dev/\$1" \$2 \$3 \$4 2>/dev/null || true
done

say "setting up mdev"
echo /bin/mdev > /proc/sys/kernel/hotplug 2>/dev/null || true
mdev -s 2>/dev/null || true

say "loading drivers"
for mod in virtio_pci virtio_blk virtio_scsi virtio_net e1000 e1000e ixgbe vmxnet3 xen_netfront ahci libahci nvme nvme_core sd_mod; do
  modprobe "\$mod" 2>/dev/null || true
done
mdev -s 2>/dev/null || true

say "configuring network"
ip link set lo up 2>/dev/null || true
sleep 1
net_ok=no
for devpath in /sys/class/net/*; do
  [ -e "\$devpath" ] || continue
  iface="\${devpath##*/}"
  [ "\$iface" = lo ] && continue
  say "trying DHCP on \$iface"
  ip link set "\$iface" up 2>/dev/null || true
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
  say "WARNING: no DHCP lease -- SSH may be unreachable"
fi

say "starting dropbear on port ${TRAMPOLINE_PORT}"
while true; do
  dropbear -E -F -s -g -p ${TRAMPOLINE_PORT} -r /etc/dropbear/dropbear_ed25519_host_key 2>&1 || true
  say "dropbear exited -- restarting in 2s"
  sleep 2
done
INIT_EOF
chmod 0755 "${OVERLAY_ROOT}/init"

LOCAL_OVERLAY="${TEMP_DIR}/overlay.cpio.gz"
(
  cd "$OVERLAY_ROOT"
  find . -print0 | LC_ALL=C sort -z | cpio --null -o -H newc | gzip -1 >"$LOCAL_OVERLAY"
) 2>/dev/null

LOCAL_INITRAMFS="${TEMP_DIR}/initramfs"
cat "${ALPINE_DIR}/initramfs" "$LOCAL_OVERLAY" >"$LOCAL_INITRAMFS"

kernel_mb=$(($(wc -c <"${ALPINE_DIR}/vmlinuz") / 1024 / 1024))
initrd_mb=$(($(wc -c <"$LOCAL_INITRAMFS") / 1024 / 1024))
log "Kernel: ${kernel_mb}MiB  Initramfs: ${initrd_mb}MiB"
log "Starting QEMU (serial output below)..."
log "SSH: ssh -i ${TRAMPOLINE_KEY} -p ${SSH_PORT} -o StrictHostKeyChecking=no root@localhost"
log "Quit QEMU: press Ctrl-A then X"
log "─────────────────────────────────────────"
echo

# Boot QEMU directly with the trampoline.  Serial goes to stdio so we see
# every line from /init in real time.
"$QEMU_BIN" \
  -enable-kvm -cpu host -m 1024 \
  -kernel "${ALPINE_DIR}/vmlinuz" \
  -initrd "$LOCAL_INITRAMFS" \
  -append "console=ttyS0 console=tty0 nomodeset panic=30 init=/init" \
  -serial stdio \
  -display none \
  -device virtio-net-pci,netdev=net0 \
  -netdev "user,id=net0,hostfwd=tcp::${SSH_PORT}-:${TRAMPOLINE_PORT}" \
  -no-reboot
