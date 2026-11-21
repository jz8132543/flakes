{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.mihomo;
  inherit (cfg) subscription;
  updater = pkgs.writeShellApplication {
    name = "mihomo-subscription-update";
    runtimeInputs = [
      pkgs.curl
      pkgs.coreutils
      pkgs.diffutils
      cfg.package
      pkgs.systemd
    ];
    # The fork's executable is mihomo-smart, not mihomo, so the script cannot
    # rely on a PATH lookup of the upstream name.
    runtimeEnv.MIHOMO_BIN = lib.getExe cfg.package;
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

    systemd.services.mihomo-subscription-update = {
      description = "Update the Mihomo subscription";
      after = [
        "network-online.target"
        "sops-install-secrets.service"
        "mihomo-loop-prevention.service"
      ];
      wants = [
        "network-online.target"
        "mihomo-loop-prevention.service"
      ];
      # GeoIP/GeoSite/ASN and the LightGBM model are provided by nixpkgs or by
      # mihomo-smart's own geo/lgbm auto-update; this service only manages the
      # subscription file, so no Geo paths or Python runtime are needed here.
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
