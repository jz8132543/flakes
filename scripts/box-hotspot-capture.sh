#!/usr/bin/env bash
set -euo pipefail

STATE="unknown"
LABEL=""
OUTDIR=""
SERIAL=""
PROMPT="1"
CAPTURE_HOST="1"
CAPTURE_PHONE="1"
RUN_HOST_PROBES="1"

usage() {
  cat <<'EOF'
Usage:
  box-hotspot-capture.sh [options]

Options:
  --state on|off|unknown   Label the capture with the current Box state.
  --label LABEL            Override the output label.
  --outdir DIR             Write artifacts to DIR.
  --serial SERIAL          Use a specific adb device serial.
  --no-prompt              Do not wait for Enter before starting.
  --no-host                Skip host-side snapshots and probes.
  --no-phone               Skip phone-side snapshots.
  --no-host-probes         Skip ping/curl probes on the host.
  -h, --help               Show this help.
EOF
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing command: $1" >&2
    exit 1
  }
}

sh_quote() {
  local text=${1-}
  printf "'%s'" "$(printf '%s' "$text" | sed "s/'/'\"'\"'/g")"
}

adb_cmd() {
  local command_text=$1
  if [ -n "$SERIAL" ]; then
    adb -s "$SERIAL" shell su -c "$(sh_quote "$command_text")"
  else
    adb shell su -c "$(sh_quote "$command_text")"
  fi
}

capture_remote() {
  local file_path=$1
  local title=$2
  local command_text=$3
  {
    printf '\n=== %s ===\n' "$title"
    adb_cmd "$command_text"
  } >>"$file_path" 2>&1 || true
}

main() {
  while [ $# -gt 0 ]; do
    case "$1" in
    --state)
      STATE=${2:-}
      shift 2
      ;;
    --label)
      LABEL=${2:-}
      shift 2
      ;;
    --outdir)
      OUTDIR=${2:-}
      shift 2
      ;;
    --serial)
      SERIAL=${2:-}
      shift 2
      ;;
    --no-prompt)
      PROMPT="0"
      shift
      ;;
    --no-host)
      CAPTURE_HOST="0"
      shift
      ;;
    --no-phone)
      CAPTURE_PHONE="0"
      shift
      ;;
    --no-host-probes)
      RUN_HOST_PROBES="0"
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      exit 1
      ;;
    esac
  done

  need_cmd adb
  need_cmd awk
  need_cmd date
  need_cmd ip
  need_cmd ping
  need_cmd curl
  need_cmd timeout
  need_cmd uname

  if [ -z "$LABEL" ]; then
    case "$STATE" in
    on) LABEL="box-on" ;;
    off) LABEL="box-off" ;;
    *) LABEL="box-unknown" ;;
    esac
  fi

  if [ -z "$OUTDIR" ]; then
    OUTDIR="/tmp/box-hotspot-${LABEL}-$(date +%Y%m%d-%H%M%S)"
  fi

  mkdir -p "$OUTDIR/host" "$OUTDIR/phone"

  if [ "$PROMPT" = "1" ]; then
    printf '准备采集：Box 状态=%s，输出目录=%s\n' "$LABEL" "$OUTDIR"
    printf '确认手机已切到对应状态后，按 Enter 继续。'
    read -r _
  fi

  {
    printf 'timestamp=%s\n' "$(date -Is)"
    printf 'label=%s\n' "$LABEL"
    printf 'state=%s\n' "$STATE"
    printf 'serial=%s\n' "${SERIAL:-auto}"
    printf 'host=%s\n' "$(uname -a)"
  } >"$OUTDIR/summary.txt"

  if [ "$CAPTURE_HOST" = "1" ]; then
    local_default_iface=$(ip route show default | awk '/default/ {print $5; exit}')
    {
      printf 'default_iface=%s\n' "${local_default_iface:-unknown}"
      printf '\n=== uname ===\n'
      uname -a
      printf '\n=== ip addr ===\n'
      ip addr show
      printf '\n=== ip route ===\n'
      ip route show
      printf '\n=== ip rule ===\n'
      ip rule show
      printf '\n=== nmcli dev show default iface ===\n'
      if [ -n "${local_default_iface:-}" ] && command -v nmcli >/dev/null 2>&1; then
        nmcli dev show "$local_default_iface" || true
      else
        echo 'nmcli not available or default iface missing'
      fi
      printf '\n=== resolvectl status ===\n'
      resolvectl status 2>/dev/null || true
    } >"$OUTDIR/host/summary.txt" 2>&1 || true

    if [ "$RUN_HOST_PROBES" = "1" ]; then
      {
        printf '\n=== ping gateway ===\n'
        timeout 8 ping -4 -c 3 -W 2 "$(ip route show default | awk '/default/ {print $3; exit}')"
        printf '\n=== ping 1.1.1.1 ===\n'
        timeout 8 ping -4 -c 3 -W 2 1.1.1.1
        printf '\n=== ping 223.5.5.5 ===\n'
        timeout 8 ping -4 -c 3 -W 2 223.5.5.5
        printf '\n=== curl cloudflare ===\n'
        timeout 12 curl -4 -I -m 10 https://www.cloudflare.com
        printf '\n=== curl baidu ===\n'
        timeout 12 curl -4 -I -m 10 https://www.baidu.com
      } >"$OUTDIR/host/probes.txt" 2>&1 || true
    fi
  fi

  if [ "$CAPTURE_PHONE" = "1" ]; then
    capture_remote "$OUTDIR/phone/summary.txt" "id" "id"
    capture_remote "$OUTDIR/phone/getprop.txt" "getprop" "getprop"
    capture_remote "$OUTDIR/phone/ip-addr.txt" "ip addr show" "ip addr show"
    capture_remote "$OUTDIR/phone/ip-route.txt" "ip route show" "ip route show"
    capture_remote "$OUTDIR/phone/ip-rule.txt" "ip rule show" "ip rule show"
    capture_remote "$OUTDIR/phone/dumpsys-connectivity.txt" "dumpsys connectivity" "dumpsys connectivity"
    capture_remote "$OUTDIR/phone/dumpsys-tethering.txt" "dumpsys tethering" "dumpsys tethering"
    capture_remote "$OUTDIR/phone/pm-list.txt" "pm list packages" "pm list packages | grep -Ei 'box|mihomo|easytier|tailscale' || true"
    capture_remote "$OUTDIR/phone/ps.txt" "ps" "ps -A -o USER,PID,PPID,NAME,ARGS | grep -Ei 'box|mihomo|easytier|tailscaled|dnsmasq' || true"
    capture_remote "$OUTDIR/phone/iptables.txt" "iptables-save" "command -v iptables-save >/dev/null 2>&1 && iptables-save || true"
    capture_remote "$OUTDIR/phone/ip6tables.txt" "ip6tables-save" "command -v ip6tables-save >/dev/null 2>&1 && ip6tables-save || true"
    capture_remote "$OUTDIR/phone/nft.txt" "nft list ruleset" "command -v nft >/dev/null 2>&1 && nft list ruleset || true"
    capture_remote "$OUTDIR/phone/logcat.txt" "logcat filtered" "logcat -d -b all -v threadtime | grep -Ei 'Tethering|ConnectivityService|netd|dnsmasq|mihomo|box|easytier|tailscale|vpn' | tail -n 400 || true"
    capture_remote "$OUTDIR/phone/network-policy.txt" "cmd connectivity / tethering" "cmd connectivity help 2>/dev/null || true; cmd tethering help 2>/dev/null || true"
  fi

  printf 'Done. Artifacts are in %s\n' "$OUTDIR"
}

main "$@"
