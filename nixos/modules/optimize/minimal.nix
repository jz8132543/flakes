{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.environment.minimal;
in
{
  imports = [ ./cpu.nix ];

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
      environment.systemPackages = lib.mkForce [ ];
      environment.defaultPackages = lib.mkForce [ ];
      system.disableInstallerTools = lib.mkForce true;

      # 2. Btrfs 额外优化 (联动 Disko 参数外的部分)
      services.btrfs.autoScrub.enable = lib.mkForce false;
      disko.devices.disk.main.content.partitions.NIXOS.content.extraArgs = lib.mkAfter [ "-M" ];

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
      programs.git.package = lib.mkForce pkgs.gitMinimal;
      programs.nix-index.enable = lib.mkForce false;
      programs.tmux.enable = lib.mkForce false;
      programs.mtr.enable = lib.mkForce false;
      programs.traceroute.enable = lib.mkForce false;
      programs.nh.enable = lib.mkForce false;
      programs.nix-ld.enable = lib.mkForce false;
      programs.bash.vteIntegration = lib.mkForce false;

      # 8. 移除非必要服务
      services.fail2ban.enable = lib.mkForce false;
      security.polkit.enable = lib.mkForce false;
      services.eternal-terminal.enable = lib.mkForce false;
      services.restic.backups = lib.mkForce { };

      # 9. 精简 Shell 与核心工具，移除 Python/Perl 依赖
      programs.fish.enable = lib.mkForce false;
      programs.zsh.enable = lib.mkForce false;
      programs.mosh.enable = lib.mkForce false;
      programs.command-not-found.enable = lib.mkForce false;

      boot.enableContainers = lib.mkForce false;
      security.rtkit.enable = lib.mkForce false;
      zramSwap.enable = lib.mkForce false;
      services.tailscale.enable = false;
      systemd.services.tailscale-setup.enable = false;

      # 限制 Journald 内存占用
      services.journald.extraConfig = lib.mkForce ''
        SystemMaxUse=10M
        RuntimeMaxUse=10M
      '';

      # 登出时杀死用户所有的后台进程 (释放 systemd --user 及残留程序大约 26MB 的内存)
      services.logind.settings.Login.KillUserProcesses = lib.mkForce true;

      # 允许在使用 minimal 模式时禁用用户的默认 Shell
      users.users.tippy.shell = lib.mkForce pkgs.bashInteractive;
      users.users.tippy.ignoreShellProgramCheck = true;

      home-manager.users.tippy = {
        home.packages = lib.mkForce [ ];
        home.file = lib.mkForce { };
        xdg.configFile = lib.mkForce { };
        home.sessionVariables = lib.mkForce { };
        programs = {
          git.enable = lib.mkForce false;
          delta.enable = lib.mkForce false;
          fish.enable = lib.mkForce false;
          zsh.enable = lib.mkForce false;
          tmux.enable = lib.mkForce false;
          neovim.enable = lib.mkForce false;
          gpg.enable = lib.mkForce false;
          direnv.enable = lib.mkForce false;
          fzf.enable = lib.mkForce false;
          zoxide.enable = lib.mkForce false;
          eza.enable = lib.mkForce false;
          bat.enable = lib.mkForce false;
          atuin.enable = lib.mkForce false;
          starship.enable = lib.mkForce false;
          skim.enable = lib.mkForce false;
        };
        services.gpg-agent.enable = lib.mkForce false;
      };

      services.bpftune.enable = lib.mkForce false;
      services.irqbalance.enable = lib.mkForce false;

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
      #
      #       # 2. 禁用透明大页 (THP)
      #       boot.kernelParams = [ "transparent_hugepage=never" ];
      #
      #       # 3. CPU 转发加速 (Flow Offload)
      #       systemd.services.apply-flow-offload = {
      #         description = "Apply nftables flow offload at runtime";
      #         after = [ "network-online.target" "nftables.service" ];
      #         wants = [ "network-online.target" "nftables.service" ];
      #         wantedBy = [ "multi-user.target" ];
      #         serviceConfig = {
      #           Type = "oneshot";
      #           RemainAfterExit = true;
      #           TimeoutStartSec = "60s";
      #         };
      #         path = [ pkgs.nftables pkgs.iproute2 pkgs.gawk pkgs.gnugrep ];
      #         script = ''
      #           # 尝试获取外网网卡
      #           IFACE=$(ip -4 route get 1.1.1.1 2>/dev/null | grep -oP 'dev \K\S+' || true)
      #           [ -z "$IFACE" ] && IFACE=$(ip link show | grep -v "lo" | awk -F': ' '/^[0-9]+: / {print $2; exit}' | tr -d ' ')
      #
      #           if [ -n "$IFACE" ]; then
      #             echo "Applying flow offload on $IFACE"
      #             nft -f - <<EOF || true
      #             table inet minimal-optimize {
      #               flowtable f {
      #                 hook ingress priority 0
      #                 devices = { $IFACE }
      #               }
      #               chain forward {
      #                 type filter hook forward priority 0; policy accept;
      #                 ct state established flow add @f
      #               }
      #             }
      # EOF
      #           else
      #             echo "No suitable interface found for flow offload."
      #           fi
      #           exit 0
      #         '';
      #       };
    })
  ];
}
