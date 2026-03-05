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

        cpu_vendor=$(awk -F: '/vendor_id/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo 2>/dev/null || true)
        [ -z "$cpu_vendor" ] && cpu_vendor="unknown"

        # Global knobs, safe on both vendors (non-existing paths are skipped).
        write_if_writable /sys/devices/system/cpu/cpufreq/boost 1
        write_if_writable /sys/devices/system/cpu/intel_pstate/no_turbo 0
        write_if_writable /sys/devices/system/cpu/intel_pstate/min_perf_pct 100
        write_if_writable /sys/devices/system/cpu/intel_pstate/max_perf_pct 100
        write_if_writable /sys/devices/system/cpu/amd_pstate/max_perf 255
        write_if_writable /sys/devices/system/cpu/amd_pstate/min_perf 255
        write_if_writable /sys/devices/system/cpu/amd_pstate/lowest_nonlinear_freq 0

        # Optional cpuidle trimming for lower ramp latency.
        for d in /sys/devices/system/cpu/cpu*/cpuidle/state*; do
          [ -d "$d" ] || continue
          latency=$(cat "$d/latency" 2>/dev/null || echo 0)
          if [ "$latency" -ge 100 ] 2>/dev/null; then
            write_if_writable "$d/disable" 1
          fi
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

        echo "[cpu-berserk] vendor=$cpu_vendor governor=performance boost=on min_freq_pinned=${
          if tune.cpuBerserk.pinMaxFreq then "1" else "0"
        }"
      '';
    };
  };
}
