{
  lib,
  config,
  pkgs,
  ...
}:
let
  tune = config.environment.networkTune;
  enabled = tune.enable && tune.cpuBerserk.enable && tune.profile == "berserk";
in
{
  config = lib.mkIf enabled {
    powerManagement.cpuFreqGovernor = lib.mkForce "performance";
    boot.kernelParams = lib.mkAfter [
      "intel_idle.max_cstate=0"
      "processor.max_cstate=1"
    ];

    systemd.services.cpu-dma-latency = lib.mkIf tune.cpuBerserk.holdDmaLatency {
      description = "Hold /dev/cpu_dma_latency at 0 for lowest wake latency";
      after = [ "multi-user.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "1s";
      };
      script = ''
        set -euo pipefail
        if [ ! -e /dev/cpu_dma_latency ]; then
          echo "/dev/cpu_dma_latency not present, sleeping"
          exec sleep infinity
        fi

        exec 3>/dev/cpu_dma_latency
        printf '\x00\x00\x00\x00' >&3
        exec sleep infinity
      '';
    };

    systemd.services.cpu-berserk = {
      description = "Aggressive CPU frequency boost tuning for lowest ramp-up latency";
      after = [ "multi-user.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = with pkgs; [
        coreutils
        gawk
        procps
        util-linux
      ];
      script = ''
        set -euo pipefail

        write_if_writable() {
          local path="$1"
          local value="$2"
          if [ -w "$path" ]; then
            echo "$value" > "$path" || true
          fi
        }

        set_irq_affinity_round_robin() {
          local ncpu idx cpu
          ncpu=$(nproc 2>/dev/null || echo 1)
          idx=0
          for irq in /proc/irq/[0-9]*; do
            [ -d "$irq" ] || continue
            if [ -w "$irq/smp_affinity_list" ]; then
              cpu=$((idx % ncpu))
              echo "$cpu" > "$irq/smp_affinity_list" 2>/dev/null || true
              idx=$((idx + 1))
            fi
          done
        }

        boost_kernel_net_threads() {
          # Push packet-processing threads to higher scheduler priority.
          while read -r pid; do
            [ -n "$pid" ] || continue
            chrt -r -p 90 "$pid" 2>/dev/null || true
            renice -n -20 -p "$pid" 2>/dev/null || true
          done < <(ps -eLo pid,comm | awk '$2 ~ /^ksoftirqd\// {print $1}')

          while read -r pid; do
            [ -n "$pid" ] || continue
            chrt -r -p 85 "$pid" 2>/dev/null || true
            renice -n -20 -p "$pid" 2>/dev/null || true
          done < <(ps -eLo pid,comm | awk '$2 ~ /^irq\// {print $1}')
        }

        cpu_vendor=$(awk -F: '/vendor_id/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo 2>/dev/null || true)
        [ -z "$cpu_vendor" ] && cpu_vendor="unknown"

        # Kernel scheduler knobs: push toward low-latency/high-reactivity behavior.
        if [ "${if tune.cpuBerserk.disableSchedulerAutogroup then "1" else "0"}" = "1" ]; then
          write_if_writable /proc/sys/kernel/sched_autogroup_enabled 0
        fi
        if [ "${if tune.cpuBerserk.disableTimerMigration then "1" else "0"}" = "1" ]; then
          write_if_writable /proc/sys/kernel/timer_migration 0
        fi
        write_if_writable /proc/sys/kernel/sched_cfs_bandwidth_slice_us 1000
        write_if_writable /proc/sys/kernel/sched_rr_timeslice_ms 25
        write_if_writable /proc/sys/kernel/sched_util_clamp_min 1024
        write_if_writable /proc/sys/kernel/sched_util_clamp_max 1024
        write_if_writable /proc/sys/kernel/sched_util_clamp_min_rt_default 1024

        # Global knobs, safe on both vendors (non-existing paths are skipped).
        write_if_writable /sys/devices/system/cpu/cpufreq/boost 1
        write_if_writable /sys/devices/system/cpu/intel_pstate/no_turbo 0
        write_if_writable /sys/devices/system/cpu/intel_pstate/min_perf_pct 100
        write_if_writable /sys/devices/system/cpu/intel_pstate/max_perf_pct 100
        write_if_writable /sys/devices/system/cpu/amd_pstate/max_perf 255
        write_if_writable /sys/devices/system/cpu/amd_pstate/min_perf 255
        write_if_writable /sys/devices/system/cpu/amd_pstate/lowest_nonlinear_freq 0

        # Aggressive cpuidle trimming for lower ramp latency.
        for d in /sys/devices/system/cpu/cpu*/cpuidle/state*; do
          [ -d "$d" ] || continue
          latency=$(cat "$d/latency" 2>/dev/null || echo 0)
          if [ "$latency" -ge "${toString tune.cpuBerserk.cpuidleDisableLatencyUs}" ] 2>/dev/null; then
            write_if_writable "$d/disable" 1
          fi
        done

        # Prefer performance bias where available.
        for e in /sys/devices/system/cpu/cpu*/power/energy_perf_bias; do
          write_if_writable "$e" 0
        done

        for p in /sys/devices/system/cpu/cpufreq/policy*; do
          [ -d "$p" ] || continue
          write_if_writable "$p/scaling_governor" performance
          write_if_writable "$p/schedutil/up_rate_limit_us" 0
          write_if_writable "$p/schedutil/down_rate_limit_us" 0

          if [ "$cpu_vendor" = "GenuineIntel" ]; then
            write_if_writable "$p/energy_performance_preference" performance
            write_if_writable "$p/energy_performance_available_preferences" performance
          fi

          if [ "$cpu_vendor" = "AuthenticAMD" ]; then
            write_if_writable "$p/energy_performance_preference" performance
            write_if_writable "$p/amd_pstate_epp" performance
            write_if_writable "$p/amd_pstate_min_freq" "$(cat "$p/cpuinfo_max_freq" 2>/dev/null || echo 0)"
          fi

          if [ "${if tune.cpuBerserk.pinMaxFreq then "1" else "0"}" = "1" ] &&
             [ -r "$p/scaling_max_freq" ] &&
             [ -w "$p/scaling_min_freq" ]; then
            cat "$p/scaling_max_freq" > "$p/scaling_min_freq" || true
          fi
        done

        if [ "${if tune.cpuBerserk.rebalanceIRQs then "1" else "0"}" = "1" ]; then
          set_irq_affinity_round_robin
        fi
        if [ "${if tune.cpuBerserk.boostKernelNetThreads then "1" else "0"}" = "1" ]; then
          boost_kernel_net_threads
        fi

        echo "[cpu-berserk] vendor=$cpu_vendor governor=performance boost=on min_freq_pinned=${
          if tune.cpuBerserk.pinMaxFreq then "1" else "0"
        } irq_rebalance=${if tune.cpuBerserk.rebalanceIRQs then "1" else "0"} kthreads_boost=${
          if tune.cpuBerserk.boostKernelNetThreads then "1" else "0"
        } cpuidle_cutoff_us=${toString tune.cpuBerserk.cpuidleDisableLatencyUs}"
      '';
    };
  };
}
