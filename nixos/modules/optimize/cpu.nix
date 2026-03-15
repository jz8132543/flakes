{
  lib,
  config,
  pkgs,
  ...
}:
let
  tune = config.environment.networkTune;
  enabled = tune.enable && tune.cpuBerserk.enable;
in
{
  config = lib.mkIf enabled {
    powerManagement.cpuFreqGovernor = lib.mkForce "performance";
    boot.kernelParams = lib.mkAfter [
      "mitigations=off" # 极大加速加密流量计算性能（提升 10-30%）
      "clocksource=kvm-clock" # 强制使用 KVM 时钟源
    ];

    systemd.services.cpu-berserk = {
      description = "Aggressive CPU scheduler tuning for shared VPS resource competition";
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

        # Kernel scheduler knobs: push toward aggressive resource competition.
        if [ "${if tune.cpuBerserk.disableSchedulerAutogroup then "1" else "0"}" = "1" ]; then
          write_if_writable /proc/sys/kernel/sched_autogroup_enabled 0
        fi
        if [ "${if tune.cpuBerserk.disableTimerMigration then "1" else "0"}" = "1" ]; then
          write_if_writable /proc/sys/kernel/timer_migration 0
        fi

        # VPS 资源抢占：通过极短的时间片和极高的唤醒抢占频率，确保在宿主机调度中占优。
        # 极短的最小调度粒度
        write_if_writable /proc/sys/kernel/sched_min_granularity_ns 100000
        write_if_writable /proc/sys/kernel/sched_wakeup_granularity_ns 50000
        write_if_writable /proc/sys/kernel/sched_migration_cost_ns 50000

        write_if_writable /proc/sys/kernel/sched_cfs_bandwidth_slice_us 1000
        write_if_writable /proc/sys/kernel/sched_rr_timeslice_ms 25
        write_if_writable /proc/sys/kernel/sched_util_clamp_min 1024
        write_if_writable /proc/sys/kernel/sched_util_clamp_max 1024
        write_if_writable /proc/sys/kernel/sched_util_clamp_min_rt_default 1024

        # Prefer performance bias where available.
        for e in /sys/devices/system/cpu/cpu*/power/energy_perf_bias; do
          write_if_writable "$e" 0
        done

        if [ "${if tune.cpuBerserk.boostKernelNetThreads then "1" else "0"}" = "1" ]; then
          boost_kernel_net_threads
        fi

        echo "[cpu-berserk] mode=vps-competition-aggressive governor=performance mitigations=off sched_min_granularity=100k"
      '';
    };
  };
}
