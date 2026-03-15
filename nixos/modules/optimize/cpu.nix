{
  lib,
  config,
  pkgs,
  ...
}:
let
  tune = config.environment.networkTune;
  enabled = tune.enable && tune.cpuBerserk.enable;
  isVM = tune.cpuBerserk.isVirtualMachine;
in
{
  config = lib.mkIf enabled {
    # 物理机：强制使用 performance 调速器；VPS 上 cpufreq sysfs 通常不存在，跳过。
    powerManagement.cpuFreqGovernor = lib.mkIf (!isVM) (lib.mkForce "performance");
    # 物理机：禁用 C-state 以消除升频延迟；VPS 上这些参数由 hypervisor 控制，无需设置。
    boot.kernelParams = lib.mkIf (!isVM) (lib.mkAfter [
      "intel_idle.max_cstate=0"
      "processor.max_cstate=1"
    ]);

    # VPS 专属：声明式内核参数，在 cpu-berserk 脚本运行前已生效。
    boot.kernel.sysctl = lib.mkIf isVM {
      # VPS 通常为单 NUMA 节点，NUMA 自动均衡只会在后台反复扫描内存页、
      # 触发 TLB 刷新和页面迁移，纯粹是额外开销，对延迟无益。
      "kernel.numa_balancing" = 0;
    };

    # 物理机：锁定 /dev/cpu_dma_latency=0；VPS 无硬件 DMA，跳过。
    systemd.services.cpu-dma-latency = lib.mkIf (tune.cpuBerserk.holdDmaLatency && !isVM) {
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

        # ── 内核调度器旋钮：对物理机和 VPS 均有效 ─────────────────────────────
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

        ${lib.optionalString isVM ''
        # ── VPS 专属：虚拟化环境运行时调优 ────────────────────────────────
        # 禁用 NUMA 自动均衡（boot.kernel.sysctl 已在早期设置，此处为兜底保障）。
        # VPS 通常为单 NUMA 节点，持续的内存扫描与页迁移只产生噪声。
        write_if_writable /proc/sys/kernel/numa_balancing 0
        ''}

        ${lib.optionalString (!isVM) ''
        # ── 物理机专属：cpufreq Boost / Turbo ──────────────────────────────
        # 在 VPS 中 hypervisor 管控实际主频，这些路径通常不存在，跳过。
        write_if_writable /sys/devices/system/cpu/cpufreq/boost 1
        write_if_writable /sys/devices/system/cpu/intel_pstate/no_turbo 0
        write_if_writable /sys/devices/system/cpu/intel_pstate/min_perf_pct 100
        write_if_writable /sys/devices/system/cpu/intel_pstate/max_perf_pct 100
        write_if_writable /sys/devices/system/cpu/amd_pstate/max_perf 255
        write_if_writable /sys/devices/system/cpu/amd_pstate/min_perf 255
        write_if_writable /sys/devices/system/cpu/amd_pstate/lowest_nonlinear_freq 0

        # ── 物理机专属：C-state 裁剪 ──────────────────────────────────────
        # VPS 上 cpuidle state 由 hypervisor 管理，guest 无法（也无需）干预。
        for d in /sys/devices/system/cpu/cpu*/cpuidle/state*; do
          [ -d "$d" ] || continue
          latency=$(cat "$d/latency" 2>/dev/null || echo 0)
          if [ "$latency" -ge "${toString tune.cpuBerserk.cpuidleDisableLatencyUs}" ] 2>/dev/null; then
            write_if_writable "$d/disable" 1
          fi
        done

        # ── 物理机专属：energy_perf_bias ──────────────────────────────────
        for e in /sys/devices/system/cpu/cpu*/power/energy_perf_bias; do
          write_if_writable "$e" 0
        done

        # ── 物理机专属：per-policy cpufreq 设置 ──────────────────────────
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
        ''}

        if [ "${if tune.cpuBerserk.rebalanceIRQs then "1" else "0"}" = "1" ]; then
          set_irq_affinity_round_robin
        fi
        if [ "${if tune.cpuBerserk.boostKernelNetThreads then "1" else "0"}" = "1" ]; then
          boost_kernel_net_threads
        fi

        echo "[cpu-berserk] vendor=$cpu_vendor is_vm=${
          if isVM then "1" else "0"
        } irq_rebalance=${if tune.cpuBerserk.rebalanceIRQs then "1" else "0"} kthreads_boost=${
          if tune.cpuBerserk.boostKernelNetThreads then "1" else "0"
        }${lib.optionalString isVM " numa_balancing=off"}${lib.optionalString (!isVM) " governor=performance boost=on min_freq_pinned=${
          if tune.cpuBerserk.pinMaxFreq then "1" else "0"
        } cpuidle_cutoff_us=${toString tune.cpuBerserk.cpuidleDisableLatencyUs}"}"
      '';
    };
  };
}
