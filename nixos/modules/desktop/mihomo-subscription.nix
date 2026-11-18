{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.mihomo;
  inherit (cfg) subscription;
  python = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
  policy = pkgs.writeText "mihomo-subscription-policy.json" (
    builtins.toJSON {
      ports = lib.unique (
        [
          22
          (config.ports.ssh or 1022)
        ]
        ++ lib.filter (p: p != 80 && p != 443) (
          lib.mapAttrsToList (_: h: h.port) (config.programs.ssh.customHosts or { })
        )
      );
      domain = config.networking.domain;
      dn42Domain = config.services.dn42.domain or "dn42";
    }
  );
  updater = pkgs.writeShellApplication {
    name = "mihomo-subscription-update";
    runtimeInputs = [
      pkgs.curl
      pkgs.coreutils
      cfg.package
      pkgs.systemd
    ];
    text = builtins.readFile ./mihomo-subscription.sh;
  };
in
{
  options.services.mihomo.subscription = {
    enable = lib.mkEnableOption "automatic full Mihomo subscription updates";
    urlFile = lib.mkOption {
      type = lib.types.path;
      description = "Runtime file containing the HTTPS subscription URL, including any secret token.";
    };
    interval = lib.mkOption {
      type = lib.types.str;
      default = "hourly";
      description = "Subscription update schedule in systemd OnCalendar syntax.";
    };
  };

  config = lib.mkIf (cfg.enable && subscription.enable) {
    system.build.mihomoSubscriptionUpdater = updater;
    assertions = [
      {
        assertion = !(lib.hasPrefix "/nix/store/" (toString cfg.configFile));
        message = "Mihomo subscription updates require a writable runtime configFile outside the Nix Store.";
      }
      {
        assertion = !(lib.hasPrefix "/nix/store/" (toString subscription.urlFile));
        message = "Mihomo subscription URLs must be supplied through a runtime secret file, not the Nix Store.";
      }
    ];

    # 配置目录同时是 mihomo-smart 的工作目录（-d /etc/mihomo），
    # 需要 mihomo 用户可写以保存 cache.db / Model.bin / ASN.mmdb / CSV。
    # 0700 + mihomo:mihomo：root 仍可管理，其他用户不可读。
    systemd.tmpfiles.rules = [ "d ${builtins.dirOf cfg.configFile} 0700 mihomo mihomo -" ];
    systemd.services.mihomo-subscription-update = {
      description = "Update and validate the full Mihomo subscription";
      after = [
        "network-online.target"
        "sops-install-secrets.service"
        "mihomo-loop-prevention.service"
      ];
      wants = [
        "network-online.target"
        "mihomo-loop-prevention.service"
      ];
      environment = {
        MIHOMO_GEOIP = "${pkgs.v2ray-geoip}/share/v2ray/geoip.dat";
        MIHOMO_GEOSITE = "${pkgs.v2ray-domain-list-community}/share/v2ray/geosite.dat";
        MIHOMO_MMDB = pkgs.dbip-country-lite.mmdb;
        MIHOMO_POLICY_FILE = lib.optionalString cfg.routing.proxyPublicSsh policy;
        MIHOMO_POLICY_SCRIPT = "${./mihomo-runtime-policy.py}";
        MIHOMO_PYTHON = "${python}/bin/python3";
      };
      serviceConfig = {
        Type = "oneshot";
        User = "mihomo";
        Group = "mihomo";
        LoadCredential = "url:${subscription.urlFile}";
        RuntimeDirectory = "mihomo-subscription";
        RuntimeDirectoryMode = "0700";
        UMask = "0077";
        TimeoutStartSec = "10min";
        ExecStart = "${updater}/bin/mihomo-subscription-update fetch";
        # Only the atomic install and service restart need root privileges.
        ExecStartPost = "+${updater}/bin/mihomo-subscription-update install ${lib.escapeShellArg (toString cfg.configFile)}";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadWritePaths = [ (builtins.dirOf cfg.configFile) ];
      };
    };
    systemd.timers.mihomo-subscription-update = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnCalendar = subscription.interval;
        RandomizedDelaySec = "1min";
        Persistent = true;
      };
    };
  };
}
