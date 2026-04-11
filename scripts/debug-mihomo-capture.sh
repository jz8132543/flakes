#!/usr/bin/env bash
set -euo pipefail

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

ts="$(date +%Y%m%d-%H%M%S)"
workdir="/tmp/mihomo-capture-${ts}"
mkdir -p "${workdir}"

log() {
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"
}

run_bg() {
  local name="$1"
  shift
  local pidfile="${workdir}/${name}.pid"
  "$@" >"${workdir}/${name}.log" 2>&1 &
  echo $! >"${pidfile}"
}

wait_bg() {
  local name="$1"
  local pid
  pid="$(cat "${workdir}/${name}.pid")"
  wait "${pid}" || true
}

stop_mihomo() {
  if systemctl is-active --quiet mihomo; then
    log "Stopping mihomo"
    systemctl stop mihomo
  fi
}

cleanup() {
  stop_mihomo
}

trap cleanup EXIT

meta_if="$(ip -o link show | awk -F': ' '/(^|[[:space:]])Meta(@|:|$)/ {print $2; exit}')"
underlay_if="$(ip route show default | awk 'NR==1 {print $5}')"

if [ -z "${underlay_if}" ]; then
  echo "Could not determine the default-route interface." >&2
  exit 1
fi

log "Workdir: ${workdir}"
log "Underlay interface: ${underlay_if}"
log "Meta interface: ${meta_if:-<none>}"

log "Saving baseline routing state"
{
  ip route show
  echo '---'
  ip rule show
  echo '---'
  systemctl is-active mihomo tailscaled easytier 2>/dev/null || true
} >"${workdir}/baseline.txt"

log "Starting mihomo"
systemctl restart mihomo
sleep 3
systemctl is-active --quiet mihomo

for _ in $(seq 1 10); do
  meta_if="$(ip -o link show | awk -F': ' '/(^|[[:space:]])Meta(@|:|$)/ {print $2; exit}')"
  if [ -n "${meta_if}" ]; then
    break
  fi
  sleep 1
done

log "Meta interface after start: ${meta_if:-<none>}"

log "Capturing traffic and running test requests"
run_bg "underlay-tcpdump" timeout 20 tcpdump -i "${underlay_if}" -nn -s0 -vvv -w "${workdir}/underlay.pcap" 'tcp port 443 or udp port 53'
if [ -n "${meta_if}" ]; then
  run_bg "meta-tcpdump" timeout 20 tcpdump -i "${meta_if}" -nn -s0 -vvv -w "${workdir}/meta.pcap" 'tcp port 443 or udp port 53'
fi

{
  echo '=== BAIDU ==='
  curl -4 -I -m 10 https://www.baidu.com
  echo '=== GOOGLE ==='
  curl -4 -I -m 10 https://www.google.com
} >"${workdir}/curl.log" 2>&1 || true

wait_bg "underlay-tcpdump"
if [ -n "${meta_if}" ]; then
  wait_bg "meta-tcpdump"
fi

log "Decoding packet captures"
tcpdump -nn -tttt -vvv -r "${workdir}/underlay.pcap" >"${workdir}/underlay.txt" 2>&1 || true
if [ -n "${meta_if}" ]; then
  tcpdump -nn -tttt -vvv -r "${workdir}/meta.pcap" >"${workdir}/meta.txt" 2>&1 || true
fi

log "Writing summary"
{
  echo "workdir=${workdir}"
  echo '--- baseline.txt'
  cat "${workdir}/baseline.txt"
  echo '--- curl.log'
  cat "${workdir}/curl.log"
  echo '--- underlay packets'
  sed -n '1,200p' "${workdir}/underlay.txt"
  if [ -n "${meta_if}" ]; then
    echo '--- meta packets'
    sed -n '1,200p' "${workdir}/meta.txt"
  fi
} >"${workdir}/summary.txt"

log "Done. Results are in ${workdir}"
echo "${workdir}"
