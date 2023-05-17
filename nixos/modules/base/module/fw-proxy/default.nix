{ config
, lib
, pkgs
, ...
}:
let
  cfg = config.networking.fw-proxy;

  scripts = pkgs.stdenvNoCC.mkDerivation rec {
    name = "fw-proxy-scripts";
    buildCommand = ''
      install -Dm644 $enableProxy     $out/bin/enable-proxy
      install -Dm644 $disableProxy    $out/bin/disable-proxy
      install -Dm755 $updateClashUrl  $out/bin/update-clash-url
      install -Dm755 $updateClash     $out/bin/update-clash
      install -Dm755 $tproxySetup     $out/bin/fw-tproxy-setup
      install -Dm755 $tproxyClean     $out/bin/fw-tproxy-clean
      install -Dm755 $tproxyUse       $out/bin/fw-tproxy-use
      install -Dm755 $tproxyUsePid    $out/bin/fw-tproxy-use-pid
      install -Dm755 $tproxyCgroup    $out/bin/fw-tproxy-cgroup
      install -Dm755 $tproxyInterface $out/bin/fw-tproxy-if
    '';
    enableProxy = pkgs.substituteAll {
      src = ./enable-proxy;
      mixedPort = cfg.mixinConfig.mixed-port;
    };
    disableProxy = pkgs.substituteAll {
      src = ./disable-proxy;
    };
    updateClashUrl = pkgs.substituteAll {
      src = ./update-clash-url.sh;
      isExecutable = true;
      inherit (pkgs.stdenvNoCC) shell;
      inherit (pkgs) coreutils curl systemd;
      yqGo = pkgs.yq-go;
      mixinConfig = builtins.toJSON cfg.mixinConfig;
      directory = "/var/lib/clash";
      externalControllerSecretFile = cfg.externalController.secretFile;
      webui = config.nur.repos.linyinfeng.yacd;
    };
    updateClash = pkgs.substituteAll {
      src = ./update-clash.sh;
      isExecutable = true;
      inherit (pkgs.stdenvNoCC) shell;
      inherit updateClashUrl;
      mainUrl = config.sops.secrets."clash/main".path;
      alternativeUrl = config.sops.secrets."clash/alternative".path;
    };
    tproxySetup = pkgs.substituteAll {
      src = ./tproxy-setup.sh;
      isExecutable = true;
      inherit (pkgs.stdenvNoCC) shell;
      inherit (pkgs) iproute2 nftables;
      tproxyPort = cfg.mixinConfig.tproxy-port;
      inherit
        (cfg.tproxy)
        routingTable
        fwmark
        cgroup
        nftTable
        extraFilterRules
        maxCgroupLevel
        bypassCgroup
        bypassCgroupLevel
        ;
      allCgroups = lib.concatStringsSep " " cfg.tproxy.allCgroups;
      proxiedInterfaces = lib.concatStringsSep " " cfg.tproxy.proxiedInterfaces;
      inherit tproxyCgroup tproxyInterface;
    };
    tproxyClean = pkgs.substituteAll {
      src = ./tproxy-clean.sh;
      isExecutable = true;
      inherit (pkgs.stdenvNoCC) shell;
      inherit (pkgs) iproute2 nftables;
      inherit (cfg.tproxy) routingTable fwmark cgroup nftTable;
    };
    tproxyUse = pkgs.substituteAll {
      src = ./tproxy-use.sh;
      isExecutable = true;
      inherit (pkgs.stdenvNoCC) shell;
      inherit tproxyUsePid;
    };
    tproxyUsePid = pkgs.substituteAll {
      src = ./tproxy-use-pid.sh;
      isExecutable = true;
      inherit (pkgs.stdenvNoCC) shell;
      cgroupPath = "/sys/fs/cgroup/${cfg.tproxy.cgroup}";
    };
    tproxyCgroup = pkgs.substituteAll {
      src = ./tproxy-cgroup.sh;
      isExecutable = true;
      inherit (pkgs.stdenvNoCC) shell;
      inherit (cfg.tproxy) nftTable maxCgroupLevel;
    };
    tproxyInterface = pkgs.substituteAll {
      src = ./tproxy-interface.sh;
      isExecutable = true;
      inherit (pkgs.stdenvNoCC) shell;
      inherit (cfg.tproxy) nftTable;
    };
  };
in
with lib; {
  options.networking.fw-proxy = {
    enable = mkOption {
      type = with types; bool;
      default = false;
    };
    tproxy = {
      enable = mkOption {
        type = with types; bool;
        default = false;
      };
      proxiedInterfaces = mkOption {
        type = with types; listOf str;
        default = [ ];
      };
      routingTable = mkOption {
        type = with types; str;
        default = "854";
      };
      fwmark = mkOption {
        type = with types; str;
        default = "0x356";
      };
      nftTable = mkOption {
        type = with types; str;
        # tproxy is a keyword in nft
        default = "fw-tproxy";
      };
      bypassCgroupLevel = mkOption {
        type = with types; int;
        default = 2;
      };
      bypassCgroup = mkOption {
        type = with types; str;
        default = "system.slice/clash.service";
      };
      maxCgroupLevel = mkOption {
        type = with types; int;
        default = 6;
      };
      cgroup = mkOption {
        type = with types; str;
        default = "tproxy.slice";
      };
      allCgroups = mkOption {
        type = with types; listOf str;
        default = [ ];
      };
      extraFilterRules = mkOption {
        type = with types; lines;
        default = "";
      };
    };
    mixinConfig = mkOption {
      type = with types; attrs;
    };
    externalController = {
      expose = mkOption {
        type = with types; bool;
      };
      virtualHost = mkOption {
        type = with types; str;
        default = "localhost";
      };
      location = mkOption {
        type = with types; str;
        default = "/";
      };
      secretFile = mkOption {
        type = with types; path;
      };
    };
    environment = mkOption {
      type = with types; attrsOf str;
      description = ''
        Proxy environment.
      '';
      default =
        let
          proxyUrl = "http://localhost:${toString cfg.mixinConfig.mixed-port}";
        in
        {
          HTTP_PROXY = proxyUrl;
          HTTPS_PROXY = proxyUrl;
          http_proxy = proxyUrl;
          https_proxy = proxyUrl;
        };
    };
    environmentContainter = mkOption {
      type = with types; attrsOf str;
      description = ''
        Proxy environment for containers.
      '';
      default =
        let
          proxyUrl = "http://host.containers.internal:${toString cfg.mixinConfig.mixed-port}";
        in
        {
          HTTP_PROXY = proxyUrl;
          HTTPS_PROXY = proxyUrl;
          http_proxy = proxyUrl;
          https_proxy = proxyUrl;
        };
    };
    stringEnvironment = mkOption {
      type = with types; listOf str;
      description = ''
        Proxy environment in strings.
      '';
      default =
        map
          (
            key:
            let
              value = lib.getAttr key cfg.environment;
            in
            "${key}=${value}"
          )
          (lib.attrNames cfg.environment);
    };
    auto-update = {
      enable = mkEnableOption "clash auto-update";
      service = mkOption {
        type = with types; str;
        description = ''
          Service used in auto update.
        '';
      };
    };
  };

  config = mkIf (cfg.enable) (mkMerge [
    {
      systemd.services.clash = {
        description = "A rule based proxy in GO";
        script = ''
          "${config.nur.repos.linyinfeng.clash-premium}/bin/clash-premium" -d "$STATE_DIRECTORY"
        '';
        serviceConfig = {
          Type = "exec";
          DynamicUser = true;
          StateDirectory = "clash";
          AmbientCapabilities = [
            "CAP_NET_BIND_SERVICE"
            "CAP_NET_ADMIN"
          ];
        };
        wantedBy = [ "multi-user.target" ];
      };

      sops.secrets."clash/main" = {
        sopsFile = config.sops-file.get "common.yaml";
        restartUnits = [ "clash-auto-update.service" ];
      };
      sops.secrets."clash/alternative" = {
        sopsFile = config.sops-file.get "common.yaml";
        restartUnits = [ "clash-auto-update.service" ];
      };

      environment.systemPackages = [
        scripts
      ];
      security.sudo.extraConfig = ''
        Defaults env_keep += "HTTP_PROXY HTTPS_PROXY FTP_PROXY ALL_PROXY NO_PROXY"
        Defaults env_keep += "http_proxy https_proxy ftp_proxy all_proxy no_proxy"
      '';
    }

    (mkIf (cfg.externalController.expose) {
      services.nginx.enable = true;
      services.nginx.virtualHosts.${cfg.externalController.virtualHost} = {
        locations = {
          "${cfg.externalController.location}".proxyPass = "http://${cfg.mixinConfig.external-controller}/";
        };
      };
    })

    (mkIf (cfg.tproxy.enable) {
      systemd.services.fw-tproxy = {
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${scripts}/bin/fw-tproxy-setup";
          ExecStopPost = "${scripts}/bin/fw-tproxy-clean";
        };
        after = [ "clash.service" ];
        requires = [ "clash.service" ];
        wantedBy = [ "multi-user.target" ];
      };
      networking.firewall.extraCommands = ''
        ${optionalString (config.networking.firewall.checkReversePath != false) ''
          ip46tables --table mangle --insert nixos-fw-rpfilter --match mark --mark ${cfg.tproxy.fwmark} --jump RETURN
        ''}
        ip46tables --append nixos-fw --match mark --mark ${cfg.tproxy.fwmark} --jump nixos-fw-accept
      '';

      networking.fw-proxy.tproxy.allCgroups = [ cfg.tproxy.cgroup ];
      passthru.fw-proxy-tproxy-scripts = scripts;
    })

    (mkIf cfg.auto-update.enable {
      systemd.services.clash-auto-update = {
        script = ''
          "${scripts}/bin/update-clash" "${cfg.auto-update.service}"
        '';
        serviceConfig = {
          Type = "oneshot";
          Restart = "on-failure";
          RestartSec = 30;
        };
        after = [ "network-online.target" "clash.service" ];
      };
      systemd.timers.clash-auto-update = {
        timerConfig = {
          OnCalendar = "03:30";
        };
        wantedBy = [ "timers.target" ];
      };
    })

    (mkIf (config.virtualisation.podman.enable)
      (
        let
          podmanInterface = config.virtualisation.podman.defaultNetwork.settings.network_interface;
        in
        {
          networking.firewall.interfaces.${podmanInterface}.allowedTCPPorts = [
            cfg.mixinConfig.mixed-port
          ];
        }
      ))

    (mkIf (config.virtualisation.libvirtd.enable)
      (
        let
          libvirtdInterfaces = config.virtualisation.libvirtd.allowedBridges;
          mkIfCfg = name: {
            ${name}.allowedTCPPorts = [
              cfg.mixinConfig.mixed-port
            ];
          };
          ifCfgs = lib.mkMerge (lib.lists.map mkIfCfg libvirtdInterfaces);
        in
        {
          networking.firewall.interfaces = ifCfgs;
        }
      ))
  ]);
}
