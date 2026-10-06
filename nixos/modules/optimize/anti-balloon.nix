{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.services.anti-balloon;

  # 超轻量 C 预分配程序：开机及定时分配可用物理内存，向每个 4KB 页面写入非零互异特征值，
  # 迫使宿主机 EPT 为所有物理页分配/刷新真实物理 RAM（更新 Accessed 访问位），
  # 同时彻底破坏全 0 页以瓦解宿主机 KSM 去重，防止冷内存被换出至宿主 Swap。
  # 触碰完毕后立即释放回 Guest 内核 Buddy Allocator，内部完全可用，宿主机无从缩回。
  memPreFault = pkgs.writeCBin "mem-pre-fault" ''
    #include <stdlib.h>
    #include <sys/sysinfo.h>

    int main(void) {
        struct sysinfo si;
        if (sysinfo(&si) != 0) return 1;

        unsigned long long free_bytes = (unsigned long long)si.freeram * si.mem_unit;
        unsigned long long total_bytes = (unsigned long long)si.totalram * si.mem_unit;

        // 保留安全余量：至少保留 256MB ~ 512MB，确保不触发 OOM 或系统卡顿
        unsigned long long safety_margin = total_bytes / 16;
        if (safety_margin < 256ULL * 1024 * 1024) {
            safety_margin = 256ULL * 1024 * 1024;
        }
        if (safety_margin > 512ULL * 1024 * 1024) {
            safety_margin = 512ULL * 1024 * 1024;
        }

        if (free_bytes <= safety_margin + 16ULL * 1024 * 1024) {
            return 0;
        }

        size_t alloc_sz = (size_t)(free_bytes - safety_margin);
        char *buf = (char *)malloc(alloc_sz);
        if (!buf) {
            alloc_sz = (size_t)(free_bytes * 3 / 4);
            buf = (char *)malloc(alloc_sz);
            if (!buf) return 0;
        }

        // 以 4096 字节（一个物理页）步进写入互不相同的特征值
        for (size_t i = 0; i < alloc_sz; i += 4096) {
            *(volatile unsigned long long *)(buf + i) = (unsigned long long)(i ^ 0xdeadbeefcafebabeULL);
        }

        // 立即归还给 Guest OS
        free(buf);
        return 0;
    }
  '';
in
{
  options.services.anti-balloon = {
    enable = lib.mkEnableOption "anti-balloon and memory protection" // {
      default = true;
    };

    interval = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "5min";
      description = ''
        防止宿主机将冷内存换出到宿主 Swap 的刷新间隔（定时触碰内存刷新 EPT Accessed 位）。
        默认为 5min。设为 null 或 "" 可禁用定时保温刷新。
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # 1. 禁用 QEMU Guest Agent 与相关探测
    services.qemuGuest.enable = lib.mkForce false;

    # 2. 彻底焊死各大虚拟化厂商的内存气球回收驱动（Fake install）
    boot.extraModprobeConfig = ''
      install virtio_balloon /bin/false
      install vmw_balloon /bin/false
      install hv_balloon /bin/false
      install xen_balloon /bin/false
    '';

    boot.blacklistedKernelModules = [
      "virtio_balloon"
      "vmw_balloon"
      "hv_balloon"
      "xen_balloon"
    ];

    # 3. 内存预热与防去重服务（开机启动）
    systemd.services.mem-pre-fault = {
      description = "Pre-fault memory to prevent host ballooning and KSM deduplication";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      before = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${memPreFault}/bin/mem-pre-fault";
        RemainAfterExit = false;
        # 严禁将内存换出到 Swap 分区（cgroup 级别限制）
        MemorySwapMax = "0";
        # 免受内核 OOM Killer 杀除（-1000 为完全豁免）
        OOMScoreAdjust = -1000;
      };
    };

    # 4. 定时触碰内存，刷新宿主机 EPT Accessed 访问位，防止宿主机将冷内存换出到宿主 Swap
    systemd.timers.mem-pre-fault = lib.mkIf (cfg.interval != null && cfg.interval != "") {
      description = "Periodic memory keep-warm timer to prevent host swap-out";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = cfg.interval;
        OnUnitActiveSec = cfg.interval;
        AccuracySec = "10s";
      };
    };
  };
}
