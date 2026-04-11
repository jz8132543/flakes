{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.environment.minimal;
  mkTop = lib.mkOverride 0;
  minimalBtrfsBaseMountOptions = [
    "noatime"
    "space_cache=v2"
    "commit=30"
    "flushoncommit"
    "ssd_spread"
    "thread_pool=1"
  ];
  rootfsBtrfsMountOptions = minimalBtrfsBaseMountOptions ++ [ "compress=no" ];
  minimalBtrfsMountOptions = minimalBtrfsBaseMountOptions ++ [ "compress=zstd:1" ];
in
{
  imports = [
    # ./cpu.nix
    ./disk-reliability.nix
  ];

  config = lib.mkMerge [
    { environment.minimal = lib.mkDefault true; }
    (lib.mkIf cfg {
      # 1. 核心系统特性精简
      documentation = {
        enable = lib.mkForce false;
        man.enable = lib.mkForce false;
        doc.enable = lib.mkForce false;
        info.enable = lib.mkForce false;
        nixos.enable = lib.mkForce false;
      };
      # `nixos-install` (used by disko image builds) enters the target via
      # `/nix/var/nix/profiles/system/sw/bin/bash`. If we force all packages away,
      # that path is missing and the install fails.
      # environment.systemPackages = lib.mkForce [ pkgs.bashInteractive ];
      # environment.defaultPackages = lib.mkForce [ ];
      system.disableInstallerTools = lib.mkForce true;

      # 2. Btrfs 额外优化
      # 在弱机上保留较短提交周期，并对 /rootfs 使用更轻的 zstd:1 压缩。
      services.btrfs.autoScrub.enable = lib.mkForce false;
      systemd.timers.btrfsBalance.enable = lib.mkForce false;
      systemd.services.btrfsBalance.enable = lib.mkForce false;
      services.easytierMesh.lowResource = true;
      disko.devices.disk.main.content.partitions.NIXOS.content.extraArgs = lib.mkAfter [ "-M" ];
      disko.devices.disk.main.content.partitions.NIXOS.content.subvolumes = {
        "/rootfs".mountOptions = mkTop rootfsBtrfsMountOptions;
        "/nix".mountOptions = mkTop minimalBtrfsMountOptions;
        "/persist".mountOptions = mkTop minimalBtrfsMountOptions;
        "/boot".mountOptions = mkTop minimalBtrfsMountOptions;
      };

      # 3. 移除 Nix 注册表中的源码副本，减少磁盘占用
      nix.registry = lib.mkForce { };
      nix.nixPath = lib.mkForce [ ];
      nix.settings.nix-path = lib.mkForce [ ];

      # 4. Nix 运行环境优化
      nix.settings = {
        keep-outputs = lib.mkForce false;
        keep-derivations = lib.mkForce false;
      };

      # 5. 禁用不必要的硬件固件 (针对虚拟机优化)
      hardware.enableRedistributableFirmware = lib.mkForce false;

      # 6. 禁用 GUI 相关依赖与服务
      fonts.fontconfig.enable = lib.mkForce false;
      services.xserver.enable = lib.mkForce false;
      xdg.icons.enable = lib.mkForce false;
      xdg.sounds.enable = lib.mkForce false;

      # 7. 强制替换重型工具为最小化版本
      # programs.git.package = lib.mkForce pkgs.gitMinimal;
      # programs.nix-index.enable = lib.mkForce false;
      # programs.tmux.enable = lib.mkForce false;
      # programs.mtr.enable = lib.mkForce false;
      # programs.traceroute.enable = lib.mkForce false;
      # programs.nh.enable = lib.mkForce false;
      # programs.nix-ld.enable = lib.mkForce false;
      # programs.bash.vteIntegration = lib.mkForce false;

      # 8. 移除非必要服务
      services.fail2ban.enable = lib.mkForce false;
      security.polkit.enable = lib.mkForce false;
      services.eternal-terminal.enable = lib.mkForce false;
      services.restic.backups = lib.mkForce { };

      # 9. 精简 Shell 与核心工具，移除 Python/Perl 依赖
      # programs.fish.enable = lib.mkForce false;
      # programs.zsh.enable = lib.mkForce false;
      # programs.mosh.enable = lib.mkForce false;
      # programs.command-not-found.enable = lib.mkForce false;

      boot.enableContainers = lib.mkForce false;
      security.rtkit.enable = lib.mkForce false;
      zramSwap.enable = lib.mkForce false;
      # services.tailscale.enable = false;
      # systemd.services.tailscale-setup.enable = false;

      # 限制 Journald 内存占用
      services.journald.extraConfig = lib.mkForce ''
        SystemMaxUse=10M
        RuntimeMaxUse=10M
      '';
      services.earlyoom.enable = true;

      # 登出时杀死用户所有的后台进程 (释放 systemd --user 及残留程序大约 26MB 的内存)
      services.logind.settings.Login.KillUserProcesses = lib.mkForce true;

      # 允许在使用 minimal 模式时禁用用户的默认 Shell
      # users.users.tippy.shell = lib.mkForce pkgs.bashInteractive;
      # users.users.tippy.ignoreShellProgramCheck = true;

      home-manager.users.tippy = {
        #   home.packages = lib.mkForce [ ];
        #   home.file = lib.mkForce { };
        #   xdg.configFile = lib.mkForce { };
        #   home.sessionVariables = lib.mkForce { };
        programs = {
          #     git.enable = lib.mkforce false;
          #     delta.enable = lib.mkforce false;
          #     fish.enable = lib.mkforce false;
          #     zsh.enable = lib.mkforce false;
          #     tmux.enable = lib.mkforce false;
          #     neovim.enable = lib.mkforce false;
          #     gpg.enable = lib.mkforce false;
          #     direnv.enable = lib.mkforce false;
          #     fzf.enable = lib.mkforce false;
          #     zoxide.enable = lib.mkforce false;
          #     eza.enable = lib.mkforce false;
          #     bat.enable = lib.mkforce false;
          atuin.enable = lib.mkForce false;
          #     starship.enable = lib.mkforce false;
          #     skim.enable = lib.mkforce false;
        };
        services.gpg-agent.enable = lib.mkForce false;
      };

      services.bpftune.enable = lib.mkForce false;
      services.irqbalance.enable = lib.mkForce false;

      boot.kernel.sysctl = {
        # 尽早回写，减少突然一大波刷盘
        "vm.dirty_background_bytes" = mkTop (16 * 1024 * 1024); # 16 MiB
        "vm.dirty_bytes" = mkTop (64 * 1024 * 1024); # 64 MiB

        # 尽早回写，减少突然一大波刷盘
        "vm.dirty_writeback_centisecs" = mkTop 1500; # 15 秒
        "vm.dirty_expire_centisecs" = mkTop 3000; # 30 秒
        # "vm.overcommit_memory" = 0;
        "vm.overcommit_ratio" = mkTop 100; # 允许使用 100% 内存
        "vm.swappiness" = mkTop 60; # 统一采用偏积极的 swap 策略，尽早回收冷页
        "vm.min_free_kbytes" = mkTop 16384; # 保留 16MB 作为内核处理网卡中断的绝对底线
        "vm.watermark_scale_factor" = mkTop 200; # 保持高灵敏度，让系统在可用内存跌到 20MB 左右时就悄悄启动 kswapd 进行后台平滑回收，避免撞到 16MB 的死线。
      };
      # 限制 VM 内部 I/O 抢占，并禁用透明大页提升稳定性
      boot.kernelParams = [
        "elevator=mq-deadline"
        "transparent_hugepage=never"
      ];

      # 针对虚拟化磁盘使用 mq-deadline 调度器并增加预读
      services.udev.extraRules = ''
        ACTION=="add|change", KERNEL=="vd[a-z]*", ATTR{queue/scheduler}="mq-deadline"
        ACTION=="add|change", KERNEL=="vd[a-z]*", ATTR{queue/read_ahead_kb}="2048"
      '';

      # ── 虚拟化增强 ────────────────────────────────────────────────
      # 1. 启用 virtio-rng 解决加密握手熵值瓶颈
      # 2. 移除 virtio-balloon 驱动 (防止宿主机回收内存导致 Guest 突然卡顿)
      boot.kernelModules = [ "virtio_rng" ];
      services.haveged.enable = true;

      #       # --- 激进资源优化 (针对极低资源服务器如 tyo0) ---
      #
      #       # 1. 内存回收优化 (基于脚本以防内核不支持)
      #       boot.kernel.sysctl = {
      #         "vm.vfs_cache_pressure" = lib.mkForce 200;
      #         "vm.swappiness" = lib.mkForce 100;
      #         "vm.dirty_ratio" = lib.mkForce 10;
      #         "vm.dirty_background_ratio" = lib.mkForce 5;
      #       };
      #
      #       systemd.services.tune-mglru = {
      #         description = "Enable MGLRU if supported by kernel";
      #         after = [ "systemd-sysctl.service" ];
      #         wantedBy = [ "multi-user.target" ];
      #         serviceConfig = {
      #           Type = "oneshot";
      #           TimeoutStartSec = "60s";
      #         };
      #         script = ''
      #           if [ -f /sys/kernel/mm/lru_gen/enabled ]; then
      #             echo 5 > /sys/kernel/mm/lru_gen/enabled
      #           elif [ -f /proc/sys/vm/lru_gen_enabled ]; then
      #             echo 5 > /proc/sys/vm/lru_gen_enabled
      #           fi
      #           exit 0
      #         '';
      #       };
      # 2. 禁用透明大页 (THP)
      # 在超售严重的 VPS 上，THP 往往会导致严重的内存碎片和 Guest 停顿。

      # 3. CPU 转发加速 (Flow Offload)
      # 利用 nftables 将已建立的连接从 Linux 网络栈卸载，极大降低加密代理转发时的 CPU 负载。
      systemd.services.apply-flow-offload = {
        description = "Apply nftables flow offload at runtime";
        after = [
          "network-online.target"
          "nftables.service"
        ];
        wants = [
          "network-online.target"
          "nftables.service"
        ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          TimeoutStartSec = "60s";
        };
        path = [
          pkgs.nftables
          pkgs.iproute2
          pkgs.gawk
          pkgs.gnugrep
        ];
        script = ''
          # 尝试获取外网网卡
          IFACE=$(ip -4 route get 1.1.1.1 2>/dev/null | grep -oP 'dev \K\S+' || true)
          [ -z "$IFACE" ] && IFACE=$(ip link show | grep -v "lo" | awk -F': ' '/^[0-9]+: / {print $2; exit}' | tr -d ' ')

          if [ -n "$IFACE" ]; then
            echo "Applying flow offload on $IFACE"
            nft -f - <<EOF || true
            table inet minimal-optimize {
              flowtable f {
                hook ingress priority 0
                devices = { $IFACE }
              }
              chain forward {
                type filter hook forward priority 0; policy accept;
                ct state established flow add @f
              }
            }
          EOF
          else
            echo "No suitable interface found for flow offload."
          fi
          exit 0
        '';
      };
    })
  ];
}
