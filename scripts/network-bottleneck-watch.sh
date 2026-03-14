#!/usr/bin/env bash
set -uo pipefail

# Realtime network bottleneck probe for high-throughput relay hosts.
# Default interval is 0.5s to catch short spikes during startup ramp.

INTERVAL="0.5"
INTERVAL_SET="0"
SAMPLES="0"
IFACE=""
TARGET_IP="1.1.1.1"
PROC_PATTERN="xray"
PROC_REQUIRED="1"
MODE="default"

usage() {
  cat <<'EOF'
Usage:
  network-bottleneck-watch.sh [--mode MODE] [--interval SEC] [--samples N] [--iface IFACE] [--target IP] [--proc-pattern REGEX] [--proc-optional]

Options:
  --mode MODE      Sampling profile: default | tyo1-tune (default: default)
  --interval SEC   Sampling interval in seconds (default: 0.5)
  --samples N      Number of samples, 0 means infinite (default: 0)
  --iface IFACE    Interface to watch (default: auto-detect via route get)
  --target IP      Route probe target for interface auto-detect (default: 1.1.1.1)
  --proc-pattern   Process regex for app metrics (default: xray). Use '' to disable app probe.
  --proc-optional  Do not emit *_PROC_NOT_FOUND hint when process is absent.
  -h, --help       Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --mode)
    MODE="${2:-}"
    shift 2
    ;;
  --interval)
    INTERVAL="${2:-}"
    INTERVAL_SET="1"
    shift 2
    ;;
  --samples)
    SAMPLES="${2:-}"
    shift 2
    ;;
  --iface)
    IFACE="${2:-}"
    shift 2
    ;;
  --target)
    TARGET_IP="${2:-}"
    shift 2
    ;;
  --proc-pattern)
    PROC_PATTERN="${2:-}"
    shift 2
    ;;
  --proc-optional)
    PROC_REQUIRED="0"
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

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing command: $1" >&2
    exit 1
  }
}

need_cmd awk
need_cmd ip
need_cmd date
need_cmd sed
need_cmd ps

case "$MODE" in
default) ;;
tyo1-tune)
  if [[ $INTERVAL_SET == "0" ]]; then
    INTERVAL="1"
  fi
  if [[ ${PROC_PATTERN} == "xray" ]]; then
    PROC_PATTERN="(xray|xray-wrapped|/xray( |$))"
  fi
  ;;
*)
  echo "Unknown mode: $MODE" >&2
  usage
  exit 1
  ;;
esac

if [[ -z $IFACE ]]; then
  IFACE="$(ip -4 route get "$TARGET_IP" 2>/dev/null | awk '{for(i=1;i<NF;i++) if($i=="dev"){print $(i+1); exit}}' || true)"
fi

if [[ -z $IFACE ]]; then
  echo "Failed to auto-detect interface. Pass --iface." >&2
  exit 1
fi

read_tcpext() {
  local key="$1"
  local v
  v="$(awk -v key="$key" '
    /^TcpExt:/{
      if (!header_done) {
        for (i=1; i<=NF; i++) hdr[i]=$i
        header_done=1
      } else {
        for (i=1; i<=NF; i++) if (hdr[i]==key) { print $i; exit }
      }
    }
  ' /proc/net/netstat)"
  if [[ -z $v ]]; then
    echo 0
  else
    echo "$v"
  fi
}

read_cpu_fields() {
  # total idle iowait softirq
  awk '/^cpu /{
    total=0
    for(i=2;i<=NF;i++) total+=$i
    idle=$5
    iowait=$6
    softirq=$8
    print total, idle, iowait, softirq
    exit
  }' /proc/stat
}

read_softnet_drops() {
  awk '{sum += strtonum("0x"$2)} END{print sum+0}' /proc/net/softnet_stat
}

read_qdisc_drops() {
  if command -v tc >/dev/null 2>&1; then
    tc -s qdisc show dev "$IFACE" 2>/dev/null | awk '/dropped/{
      for(i=1;i<=NF;i++) if($i=="dropped"){gsub(",","",$(i+1)); sum+=$(i+1)}
    } END{print sum+0}'
  else
    echo 0
  fi
}

read_qdisc_backlog_bytes() {
  if command -v tc >/dev/null 2>&1; then
    tc -s qdisc show dev "$IFACE" 2>/dev/null | awk '/backlog/{
      for(i=1;i<=NF;i++) if($i=="backlog"){v=$(i+1); sub(/b$/,"",v); sum+=v}
    } END{print sum+0}'
  else
    echo 0
  fi
}

read_softirq_net() {
  # print: net_rx_sum net_tx_sum
  awk '
    /^[[:space:]]*NET_RX:/{
      s=0; for(i=2;i<=NF;i++) s+=$i; rx=s
    }
    /^[[:space:]]*NET_TX:/{
      s=0; for(i=2;i<=NF;i++) s+=$i; tx=s
    }
    END{print rx+0, tx+0}
  ' /proc/softirqs
}

read_vmstat_sum() {
  local pat="$1"
  awk -v pat="$pat" '$1 ~ pat {s+=$2} END{print s+0}' /proc/vmstat
}

read_mem_breakdown() {
  # MemTotal MemAvailable SwapTotal SwapFree SReclaimable SUnreclaim (kB)
  awk '
    /MemTotal:/ {mt=$2}
    /MemAvailable:/ {ma=$2}
    /SwapTotal:/ {st=$2}
    /SwapFree:/ {sf=$2}
    /SReclaimable:/ {sr=$2}
    /SUnreclaim:/ {su=$2}
    END{print mt+0, ma+0, st+0, sf+0, sr+0, su+0}
  ' /proc/meminfo
}

read_psi_avg10() {
  local res="$1"
  local mode="$2"
  local f="/proc/pressure/$res"
  if [[ ! -r $f ]]; then
    echo "0.00"
    return
  fi
  awk -v m="$mode" '
    $1==m {
      for (i=1;i<=NF;i++) {
        if ($i ~ /^avg10=/) {
          split($i,a,"=")
          printf "%.2f", a[2]+0
          exit
        }
      }
    }
    END{ if (NR==0) printf "0.00" }
  ' "$f"
}

read_nic_drop_err() {
  local base="/sys/class/net/$IFACE/statistics"
  local rxd txd rxe txe
  rxd="$(cat "$base/rx_dropped" 2>/dev/null || echo 0)"
  txd="$(cat "$base/tx_dropped" 2>/dev/null || echo 0)"
  rxe="$(cat "$base/rx_errors" 2>/dev/null || echo 0)"
  txe="$(cat "$base/tx_errors" 2>/dev/null || echo 0)"
  echo "$rxd $txd $rxe $txe"
}

read_ss_summary() {
  if ! command -v ss >/dev/null 2>&1; then
    echo "0 0"
    return
  fi
  ss -tinH state established 2>/dev/null | awk '
    {
      c++
      for (i=1;i<=NF;i++) {
        if ($i ~ /^retrans:/) {
          split($i,a,/[\/:]/)
          r += (a[2]+0)
        }
      }
    }
    END{print c+0, r+0}
  '
}

sysctl_get() {
  local key="$1"
  local path="/proc/sys/${key//./\/}"
  if [[ -r $path ]]; then
    cat "$path"
  else
    echo "NA"
  fi
}

read_default_route_params() {
  local line
  line="$(ip -4 route show default dev "$IFACE" | head -n 1 || true)"
  if [[ -z $line ]]; then
    echo "NA NA NA"
    return
  fi
  local icw irw mss
  icw="$(awk '{for(i=1;i<=NF;i++) if($i=="initcwnd"){print $(i+1); exit}}' <<<"$line")"
  irw="$(awk '{for(i=1;i<=NF;i++) if($i=="initrwnd"){print $(i+1); exit}}' <<<"$line")"
  mss="$(awk '{for(i=1;i<=NF;i++) if($i=="advmss"){print $(i+1); exit}}' <<<"$line")"
  [[ -z $icw ]] && icw="NA"
  [[ -z $irw ]] && irw="NA"
  [[ -z $mss ]] && mss="NA"
  echo "$icw $irw $mss"
}

find_xray_pid() {
  if [[ -z ${PROC_PATTERN:-} ]]; then
    return 0
  fi

  if [[ $PROC_PATTERN =~ xray ]]; then
    if command -v systemctl >/dev/null 2>&1; then
      local spid
      spid="$(systemctl show -p MainPID --value xray.service 2>/dev/null || true)"
      if [[ -n $spid && $spid =~ ^[0-9]+$ && $spid -gt 1 && -r "/proc/$spid/stat" ]]; then
        echo "$spid"
        return 0
      fi
      spid="$(systemctl show -p MainPID --value xray 2>/dev/null || true)"
      if [[ -n $spid && $spid =~ ^[0-9]+$ && $spid -gt 1 && -r "/proc/$spid/stat" ]]; then
        echo "$spid"
        return 0
      fi
    fi

    if command -v pgrep >/dev/null 2>&1; then
      local ppid
      ppid="$(pgrep -xo xray 2>/dev/null || true)"
      if [[ -n $ppid && -r "/proc/$ppid/stat" ]]; then
        echo "$ppid"
        return 0
      fi
      ppid="$(pgrep -fo '/nix/store/.*/bin/xray([[:space:]]|$)' 2>/dev/null || true)"
      if [[ -n $ppid && -r "/proc/$ppid/stat" ]]; then
        echo "$ppid"
        return 0
      fi
    fi
  fi

  # NixOS path example:
  # /nix/store/.../bin/xray -config ...
  # Also supports custom process regex via --proc-pattern.
  ps -eo pid=,args= 2>/dev/null | awk -v pat="${PROC_PATTERN}" '
    {
      line=$0
      if (line ~ pat) {
        print $1
        exit
      }
    }
  '
}

read_xray_fd() {
  local pid="${1:-}"
  if [[ -z $pid ]]; then
    pid="$(find_xray_pid || true)"
  fi
  if [[ -z $pid ]]; then
    echo "-1 -1 -1"
    return
  fi
  local fd_cnt fd_lim
  fd_cnt="$(find "/proc/$pid/fd" -mindepth 1 -maxdepth 1 -printf . 2>/dev/null | wc -c | awk '{print $1}')"
  fd_lim="$(awk '/Max open files/ {print $4; exit}' "/proc/$pid/limits" 2>/dev/null || echo 0)"
  echo "$pid $fd_cnt $fd_lim"
}

read_xray_proc_stats() {
  local pid="${1:-}"
  if [[ -z $pid ]]; then
    pid="$(find_xray_pid || true)"
  fi
  if [[ -z $pid ]]; then
    echo "-1 0.0 0 0"
    return
  fi

  if command -v ps >/dev/null 2>&1; then
    # %cpu rss(kb) nlwp
    local pcpu rss_kb nlwp
    pcpu="$(ps -p "$pid" -o %cpu= 2>/dev/null | awk '{print $1+0}')"
    rss_kb="$(ps -p "$pid" -o rss= 2>/dev/null | awk '{print $1+0}')"
    nlwp="$(ps -p "$pid" -o nlwp= 2>/dev/null | awk '{print $1+0}')"
    [[ -z $pcpu ]] && pcpu="0.0"
    [[ -z $rss_kb ]] && rss_kb="0"
    [[ -z $nlwp ]] && nlwp="0"
    echo "$pid $pcpu $rss_kb $nlwp"
  else
    echo "$pid 0.0 0 0"
  fi
}

print_header() {
  echo "iface=$IFACE interval=${INTERVAL}s mode=$MODE"
  read -r ricw rirw rmss <<<"$(read_default_route_params)"
  echo "route.v4 default: initcwnd=$ricw initrwnd=$rirw advmss=$rmss"
  echo "sysctl: cc=$(sysctl_get net.ipv4.tcp_congestion_control) ssr=$(sysctl_get net.ipv4.tcp_pacing_ss_ratio) car=$(sysctl_get net.ipv4.tcp_pacing_ca_ratio) lout=$(sysctl_get net.ipv4.tcp_limit_output_bytes) bp=$(sysctl_get net.core.busy_poll) ndb=$(sysctl_get net.core.netdev_budget) ndu=$(sysctl_get net.core.netdev_budget_usecs) ctmax=$(sysctl_get net.netfilter.nf_conntrack_max)"
  if [[ $MODE == "tyo1-tune" ]]; then
    printf "time\tcpu%%\tsoft%%\tiow%%\tmem%%\tswp%%\tslabM\ttxMb\trxMb\tretr_s\tqdrp_s\tsdrp_s\tconn%%\txfd%%\txcpu\txrssM\tthr\tnRx_s\tnTx_s\tqKB\tld1\tpsiC\tpsiM\tpsiI\tpmaj_s\tastl_s\testb\tsret\tlDr_s\tlOv_s\tto_s\trxdp_s\ttxdp_s\trxer_s\ttxer_s\n"
  else
    echo "time                cpu% soft% iow% mem% swp% slabM txMb rxMb retr/s qdrp/s sdrp/s conn% xfd% xcpu xrssM th nRx/s nTx/s qKB ld1 psiC psiM psiI pmaj/s astl/s estb sret lDr/s lOv/s to/s rxdp txdp rxer txer"
  fi
}

read -r prev_total prev_idle prev_iowait prev_softirq <<<"$(read_cpu_fields)"
prev_rx="$(cat "/sys/class/net/$IFACE/statistics/rx_bytes" 2>/dev/null || echo 0)"
prev_tx="$(cat "/sys/class/net/$IFACE/statistics/tx_bytes" 2>/dev/null || echo 0)"
prev_retr="$(read_tcpext TCPRetransSegs)"
prev_qdrop="$(read_qdisc_drops)"
prev_sdrop="$(read_softnet_drops)"
read -r prev_netrx prev_nettx <<<"$(read_softirq_net)"
prev_listen_drop="$(read_tcpext ListenDrops)"
prev_listen_ovf="$(read_tcpext ListenOverflows)"
prev_timeouts="$(read_tcpext TCPTimeouts)"
read -r prev_rxdp prev_txdp prev_rxer prev_txer <<<"$(read_nic_drop_err)"
prev_pgmaj="$(read_vmstat_sum '^pgmajfault$')"
prev_allocstall="$(read_vmstat_sum '^allocstall')"
prev_ns="$(date +%s%N)"

count=0
print_header

while true; do
  sleep "$INTERVAL"

  now_ns="$(date +%s%N)"
  elapsed="$(awk -v n="$now_ns" -v p="$prev_ns" 'BEGIN{d=(n-p)/1e9; if(d<=0)d=0.001; print d}')"

  read -r total idle iowait softirq <<<"$(read_cpu_fields)"
  rx="$(cat "/sys/class/net/$IFACE/statistics/rx_bytes" 2>/dev/null || echo 0)"
  tx="$(cat "/sys/class/net/$IFACE/statistics/tx_bytes" 2>/dev/null || echo 0)"
  retr="$(read_tcpext TCPRetransSegs)"
  qdrop="$(read_qdisc_drops)"
  sdrop="$(read_softnet_drops)"
  qback="$(read_qdisc_backlog_bytes)"
  read -r netrx nettx <<<"$(read_softirq_net)"
  list_drop="$(read_tcpext ListenDrops)"
  list_ovf="$(read_tcpext ListenOverflows)"
  timeouts="$(read_tcpext TCPTimeouts)"
  read -r rxdp txdp rxer txer <<<"$(read_nic_drop_err)"
  pgmaj="$(read_vmstat_sum '^pgmajfault$')"
  allocstall="$(read_vmstat_sum '^allocstall')"

  dt=$((total - prev_total))
  didle=$((idle - prev_idle))
  diow=$((iowait - prev_iowait))
  dsoft=$((softirq - prev_softirq))
  [[ $dt -le 0 ]] && dt=1

  cpu_pct="$(awk -v dt="$dt" -v di="$didle" 'BEGIN{printf "%.1f", (dt-di)*100.0/dt}')"
  iow_pct="$(awk -v dt="$dt" -v di="$diow" 'BEGIN{printf "%.1f", di*100.0/dt}')"
  soft_pct="$(awk -v dt="$dt" -v ds="$dsoft" 'BEGIN{printf "%.1f", ds*100.0/dt}')"

  tx_mbps="$(awk -v n="$tx" -v p="$prev_tx" -v e="$elapsed" 'BEGIN{d=n-p; if(d<0)d=0; printf "%.1f", d*8.0/e/1000000}')"
  rx_mbps="$(awk -v n="$rx" -v p="$prev_rx" -v e="$elapsed" 'BEGIN{d=n-p; if(d<0)d=0; printf "%.1f", d*8.0/e/1000000}')"
  retr_rate="$(awk -v n="$retr" -v p="$prev_retr" -v e="$elapsed" 'BEGIN{d=n-p; if(d<0)d=0; printf "%.0f", d/e}')"
  qdrop_rate="$(awk -v n="$qdrop" -v p="$prev_qdrop" -v e="$elapsed" 'BEGIN{d=n-p; if(d<0)d=0; printf "%.0f", d/e}')"
  sdrop_rate="$(awk -v n="$sdrop" -v p="$prev_sdrop" -v e="$elapsed" 'BEGIN{d=n-p; if(d<0)d=0; printf "%.0f", d/e}')"
  netrx_rate="$(awk -v n="$netrx" -v p="$prev_netrx" -v e="$elapsed" 'BEGIN{d=n-p; if(d<0)d=0; printf "%.0f", d/e}')"
  nettx_rate="$(awk -v n="$nettx" -v p="$prev_nettx" -v e="$elapsed" 'BEGIN{d=n-p; if(d<0)d=0; printf "%.0f", d/e}')"
  qback_kb="$(awk -v b="$qback" 'BEGIN{printf "%.1f", b/1024.0}')"
  load1="$(awk '{print $1}' /proc/loadavg)"
  psi_cpu="$(read_psi_avg10 cpu some)"
  psi_mem="$(read_psi_avg10 memory some)"
  psi_io="$(read_psi_avg10 io some)"
  read -r ss_estab ss_retr <<<"$(read_ss_summary)"

  read -r mt ma st sf sr su <<<"$(read_mem_breakdown)"
  mem_pct="$(awk -v t="$mt" -v a="$ma" 'BEGIN{if(t>0) printf "%.1f", (t-a)*100.0/t; else print "0.0"}')"
  swap_pct="$(awk -v t="$st" -v f="$sf" 'BEGIN{if(t>0) printf "%.1f", (t-f)*100.0/t; else print "0.0"}')"
  slab_mb="$(awk -v a="$sr" -v b="$su" 'BEGIN{printf "%.1f", (a+b)/1024.0}')"

  conn_count="$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo 0)"
  conn_max="$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo 1)"
  conn_pct="$(awk -v c="$conn_count" -v m="$conn_max" 'BEGIN{if(m<=0)m=1; printf "%.1f", c*100.0/m}')"
  ldrop_rate="$(awk -v n="$list_drop" -v p="$prev_listen_drop" -v e="$elapsed" 'BEGIN{d=n-p; if(d<0)d=0; printf "%.0f", d/e}')"
  lovf_rate="$(awk -v n="$list_ovf" -v p="$prev_listen_ovf" -v e="$elapsed" 'BEGIN{d=n-p; if(d<0)d=0; printf "%.0f", d/e}')"
  to_rate="$(awk -v n="$timeouts" -v p="$prev_timeouts" -v e="$elapsed" 'BEGIN{d=n-p; if(d<0)d=0; printf "%.0f", d/e}')"
  rxdp_rate="$(awk -v n="$rxdp" -v p="$prev_rxdp" -v e="$elapsed" 'BEGIN{d=n-p; if(d<0)d=0; printf "%.0f", d/e}')"
  txdp_rate="$(awk -v n="$txdp" -v p="$prev_txdp" -v e="$elapsed" 'BEGIN{d=n-p; if(d<0)d=0; printf "%.0f", d/e}')"
  rxer_rate="$(awk -v n="$rxer" -v p="$prev_rxer" -v e="$elapsed" 'BEGIN{d=n-p; if(d<0)d=0; printf "%.0f", d/e}')"
  txer_rate="$(awk -v n="$txer" -v p="$prev_txer" -v e="$elapsed" 'BEGIN{d=n-p; if(d<0)d=0; printf "%.0f", d/e}')"
  pmaj_rate="$(awk -v n="$pgmaj" -v p="$prev_pgmaj" -v e="$elapsed" 'BEGIN{d=n-p; if(d<0)d=0; printf "%.1f", d/e}')"
  astl_rate="$(awk -v n="$allocstall" -v p="$prev_allocstall" -v e="$elapsed" 'BEGIN{d=n-p; if(d<0)d=0; printf "%.1f", d/e}')"

  xpid="$(find_xray_pid || true)"
  read -r _ xfd xlim <<<"$(read_xray_fd "$xpid")"
  read -r _ xcpu rss_kb xthr <<<"$(read_xray_proc_stats "$xpid")"
  xrss_mb="$(awk -v r="$rss_kb" 'BEGIN{printf "%.1f", r/1024.0}')"
  if [[ -z ${xpid:-} || $xpid == "-1" || ${xlim:-0} -le 0 || ${xfd:-0} -lt 0 ]]; then
    xfd_pct="0.0"
  else
    xfd_pct="$(awk -v f="$xfd" -v l="$xlim" 'BEGIN{printf "%.1f", f*100.0/l}')"
  fi

  now_hms="$(date +%H:%M:%S)"
  if [[ $MODE == "tyo1-tune" ]]; then
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
      "$now_hms" "$cpu_pct" "$soft_pct" "$iow_pct" "$mem_pct" "$swap_pct" "$slab_mb" \
      "$tx_mbps" "$rx_mbps" "$retr_rate" "$qdrop_rate" "$sdrop_rate" "$conn_pct" \
      "$xfd_pct" "$xcpu" "$xrss_mb" "$xthr" "$netrx_rate" "$nettx_rate" "$qback_kb" "$load1" "$psi_cpu" "$psi_mem" \
      "$psi_io" "$pmaj_rate" "$astl_rate" "$ss_estab" "$ss_retr" "$ldrop_rate" "$lovf_rate" "$to_rate" "$rxdp_rate" "$txdp_rate" "$rxer_rate" "$txer_rate"
  else
    printf "%-19s %5s %5s %5s %5s %5s %6s %5s %5s %6s %6s %6s %5s %5s %5s %6s %3s %6s %6s %5s %5s %5s %5s %5s %6s %6s %5s %5s %5s %5s %5s %5s %5s %5s %5s\n" \
      "$now_hms" "$cpu_pct" "$soft_pct" "$iow_pct" "$mem_pct" "$swap_pct" "$slab_mb" \
      "$tx_mbps" "$rx_mbps" "$retr_rate" "$qdrop_rate" "$sdrop_rate" "$conn_pct" \
      "$xfd_pct" "$xcpu" "$xrss_mb" "$xthr" "$netrx_rate" "$nettx_rate" "$qback_kb" "$load1" "$psi_cpu" "$psi_mem" \
      "$psi_io" "$pmaj_rate" "$astl_rate" "$ss_estab" "$ss_retr" "$ldrop_rate" "$lovf_rate" "$to_rate" "$rxdp_rate" "$txdp_rate" "$rxer_rate" "$txer_rate"
  fi

  # Diagnosis hints
  hint=""
  if awk -v c="$cpu_pct" -v s="$soft_pct" 'BEGIN{exit !((c+0)>=85 && (s+0)>=35)}'; then
    hint+="[CPU_SOFTIRQ_SAT] "
  fi
  if awk -v c="$cpu_pct" -v s="$soft_pct" 'BEGIN{exit !((c+0)>=90 && (s+0)<=10)}'; then
    hint+="[CPU_USERLAND_SAT] "
  fi
  if awk -v m="$mem_pct" 'BEGIN{exit !((m+0)>=80)}'; then
    hint+="[MEM_PRESSURE] "
  fi
  if awk -v s="$swap_pct" 'BEGIN{exit !((s+0)>=10)}'; then
    hint+="[SWAP_USED] "
  fi
  if awk -v s="$astl_rate" 'BEGIN{exit !((s+0)>=5.0)}'; then
    hint+="[ALLOCSTALL] "
  fi
  if awk -v p="$pmaj_rate" 'BEGIN{exit !((p+0)>=5.0)}'; then
    hint+="[MAJFAULT_SPIKE] "
  fi
  if [[ $qdrop_rate -ge 50 || $sdrop_rate -ge 50 ]]; then
    hint+="[LOCAL_QUEUE_DROP] "
  fi
  if [[ $retr_rate -ge 1500 ]]; then
    hint+="[PATH_LOSS_OR_QOS] "
  fi
  if [[ $ldrop_rate -ge 20 || $lovf_rate -ge 20 ]]; then
    hint+="[LISTEN_QUEUE_PRESSURE] "
  fi
  if [[ $to_rate -ge 200 ]]; then
    hint+="[TCP_TIMEOUT_SPIKE] "
  fi
  if [[ $rxer_rate -ge 1 || $txer_rate -ge 1 ]]; then
    hint+="[NIC_ERROR] "
  fi
  if awk -v c="$psi_cpu" 'BEGIN{exit !((c+0)>=2.0)}'; then
    hint+="[CPU_PSI_HIGH] "
  fi
  if awk -v m="$psi_mem" 'BEGIN{exit !((m+0)>=1.0)}'; then
    hint+="[MEM_PSI_HIGH] "
  fi
  if awk -v i="$psi_io" 'BEGIN{exit !((i+0)>=1.0)}'; then
    hint+="[IO_PSI_HIGH] "
  fi
  if awk -v p="$conn_pct" 'BEGIN{exit !((p+0)>=90)}'; then
    hint+="[CONNTRACK_NEAR_LIMIT] "
  fi
  if [[ -n ${xpid:-} && $xpid != "-1" ]] && awk -v p="$xfd_pct" 'BEGIN{exit !((p+0)>=85)}'; then
    hint+="[APP_FD_NEAR_LIMIT] "
  fi
  if [[ $PROC_REQUIRED == "1" && (${xpid:-} == "" || $xpid == "-1") ]]; then
    hint+="[APP_PROC_NOT_FOUND] "
  fi
  if awk -v q="$qback_kb" 'BEGIN{exit !((q+0)>=1024)}'; then
    hint+="[QDISC_BACKLOG_HIGH] "
  fi
  if [[ -n $hint ]]; then
    echo "  hint: $hint"
  fi

  prev_total="$total"
  prev_idle="$idle"
  prev_iowait="$iowait"
  prev_softirq="$softirq"
  prev_rx="$rx"
  prev_tx="$tx"
  prev_retr="$retr"
  prev_qdrop="$qdrop"
  prev_sdrop="$sdrop"
  prev_netrx="$netrx"
  prev_nettx="$nettx"
  prev_listen_drop="$list_drop"
  prev_listen_ovf="$list_ovf"
  prev_timeouts="$timeouts"
  prev_rxdp="$rxdp"
  prev_txdp="$txdp"
  prev_rxer="$rxer"
  prev_txer="$txer"
  prev_pgmaj="$pgmaj"
  prev_allocstall="$allocstall"
  prev_ns="$now_ns"

  count=$((count + 1))
  if [[ $SAMPLES != "0" && $count -ge $SAMPLES ]]; then
    break
  fi
done
