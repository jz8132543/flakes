#!/usr/bin/env bash
set -euo pipefail

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

OUTDIR=${1:-/tmp/mihomo-capture-$(date +%Y%m%d-%H%M%S)}
mkdir -p "$OUTDIR"

exec > >(tee -a "$OUTDIR/run.log") 2>&1

DEFAULT_IFACE=$(ip route show default | awk '/default/ {print $5; exit}')
META_IFACE=$(ip -o link show | awk -F': ' '$2 ~ /(^|@)Meta([:@]|$)/ {print $2; exit}')

if [ -z "$DEFAULT_IFACE" ]; then
  echo "Unable to detect default interface" >&2
  exit 1
fi

if [ -z "$META_IFACE" ]; then
  META_IFACE=Meta
fi

CAPTURE_PIDS=()

cleanup() {
  set +e
  if [ ${#CAPTURE_PIDS[@]} -gt 0 ]; then
    for pid in "${CAPTURE_PIDS[@]}"; do
      kill -- "-$pid" 2>/dev/null || true
      kill "$pid" 2>/dev/null || true
    done
    wait "${CAPTURE_PIDS[@]}" 2>/dev/null || true
  fi
  systemctl stop mihomo >/dev/null 2>&1 || true
}

trap cleanup EXIT

log_section() {
  printf '\n=== %s ===\n' "$1"
}

wait_for_service() {
  local service=$1
  local tries=20
  while [ "$tries" -gt 0 ]; do
    if systemctl is-active --quiet "$service"; then
      return 0
    fi
    tries=$((tries - 1))
    sleep 1
  done
  return 1
}

wait_for_iface() {
  local iface=$1
  local tries=10
  while [ "$tries" -gt 0 ]; do
    if ip link show "$iface" >/dev/null 2>&1; then
      return 0
    fi
    tries=$((tries - 1))
    sleep 1
  done
  return 1
}

collect_snapshot() {
  local prefix=$1
  log_section "$prefix"
  {
    date -Is
    uname -a
    echo '--- ip addr show ---'
    ip addr show
    echo '--- ip route show ---'
    ip route show
    echo '--- ip route show table main ---'
    ip route show table main
    echo '--- ip route show table default ---'
    ip route show table default 2>/dev/null || true
    echo '--- ip route show table 52 ---'
    ip route show table 52 || true
    echo '--- ip rule show ---'
    ip rule show
    echo '--- nft ruleset ---'
    nft list ruleset 2>/dev/null || true
    echo '--- service states ---'
    systemctl is-active mihomo tailscaled easytier dnsmasq 2>/dev/null || true
    echo '--- service status mihomo ---'
    systemctl status mihomo --no-pager -l 2>/dev/null || true
    echo '--- service status tailscaled ---'
    systemctl status tailscaled --no-pager -l 2>/dev/null || true
    echo '--- service status easytier ---'
    systemctl status easytier --no-pager -l 2>/dev/null || true
    echo '--- resolvectl status ---'
    resolvectl status 2>/dev/null || true
  } >"$OUTDIR/${prefix}.txt"
}

start_capture() {
  local iface=$1
  local pcap="$OUTDIR/${iface}.pcap"
  local log="$OUTDIR/${iface}.tcpdump.log"
  setsid tcpdump -i "$iface" -nn -tttt -vvv -s 0 -w "$pcap" >"$log" 2>&1 &
  CAPTURE_PIDS+=("$!")
  echo "Started capture on $iface -> $pcap"
}

stop_captures() {
  if [ ${#CAPTURE_PIDS[@]} -eq 0 ]; then
    return 0
  fi

  for pid in "${CAPTURE_PIDS[@]}"; do
    kill -- "-$pid" 2>/dev/null || true
    kill "$pid" 2>/dev/null || true
  done

  for pid in "${CAPTURE_PIDS[@]}"; do
    wait "$pid" 2>/dev/null || true
  done
}

probe_direct() {
  local stage=$1
  {
    echo "=== direct probe: $stage ==="
    echo '--- curl cloudflare ---'
    timeout 12 curl -4 -I -m 10 https://www.cloudflare.com
    echo '--- ip route get baidu ---'
    ip route get 39.156.70.46
    ip route get 39.156.70.239
    echo '--- tcp 80/443 ---'
    timeout 6 nc -vz 39.156.70.46 80
    timeout 6 nc -vz 39.156.70.46 443
    timeout 6 nc -vz 39.156.70.239 80
    timeout 6 nc -vz 39.156.70.239 443
    echo '--- curl baidu ---'
    timeout 12 curl -4 -I -m 10 https://www.baidu.com
  } >"$OUTDIR/${stage}.txt" 2>&1 || true
}

probe_via_mihomo() {
  {
    echo '=== mihomo probe: cloudflare ==='
    timeout 12 curl -4 -v -m 10 https://www.cloudflare.com -o /dev/null
    echo '=== mihomo probe: baidu ==='
    timeout 12 curl -4 -v -m 10 https://www.baidu.com -o /dev/null
    echo '=== mihomo probe: google ==='
    timeout 12 curl -4 -v -m 10 https://www.google.com -o /dev/null
  } >"$OUTDIR/proxy-curl.txt" 2>&1 || true
}

echo "Output dir: $OUTDIR"
echo "Default interface: $DEFAULT_IFACE"
echo "Meta interface: $META_IFACE"

log_section "ensure mihomo stopped before baseline"
systemctl stop mihomo >/dev/null 2>&1 || true

collect_snapshot "baseline"
probe_direct "direct-before-mihomo"

log_section "starting mihomo"
systemctl start mihomo
wait_for_service mihomo || true
wait_for_iface "$META_IFACE" || true

collect_snapshot "after-start"

if ip link show "$DEFAULT_IFACE" >/dev/null 2>&1; then
  start_capture "$DEFAULT_IFACE"
else
  echo "Skipping missing interface: $DEFAULT_IFACE"
fi

if ip link show lo >/dev/null 2>&1; then
  start_capture lo
fi

if ip link show "$META_IFACE" >/dev/null 2>&1; then
  start_capture "$META_IFACE"
else
  echo "Skipping missing interface: $META_IFACE"
fi

sleep 2
probe_via_mihomo

log_section "stopping mihomo"
log_section "stopping packet captures"
stop_captures
systemctl stop mihomo || true

collect_snapshot "after-stop"

log_section "decoding pcaps"
for iface in "$DEFAULT_IFACE" "$META_IFACE"; do
  pcap="$OUTDIR/${iface}.pcap"
  text="$OUTDIR/${iface}.txt"
  if [ -f "$pcap" ]; then
    tcpdump -nn -tttt -vvv -r "$pcap" >"$text" 2>&1 || true
    echo "Wrote $text"
  fi
done

log_section "journal"
journalctl -b -u mihomo --no-pager -n 200 >"$OUTDIR/mihomo-journal.txt" 2>&1 || true

echo "Done. Artifacts are in $OUTDIR"
echo "$OUTDIR"
