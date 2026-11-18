{ pkgs }:
let
  inherit (pkgs) lib;
  secretNames = [
    "uuid"
    "private_key"
    "public_key"
    "short_id"
    "cf_tunnel_token"
  ];
  fixtureSops = {
    options.sops = lib.mkOption {
      type = lib.types.submodule {
        options = {
          placeholder = lib.mkOption { type = lib.types.attrsOf lib.types.str; };
          secrets = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.submodule {
                options.mode = lib.mkOption { type = lib.types.str; };
              }
            );
          };
          templates = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.submodule (
                { name, ... }: {
                  options = {
                    content = lib.mkOption { type = lib.types.str; };
                    mode = lib.mkOption { type = lib.types.str; };
                    restartUnits = lib.mkOption { type = lib.types.listOf lib.types.str; };
                    path = lib.mkOption {
                      type = lib.types.str;
                      default = "/run/secrets/rendered/${name}";
                    };
                  };
                }
              )
            );
          };
        };
      };
    };
    config = {
      sops.placeholder = lib.genAttrs (map (name: "xray/${name}") secretNames) (name: "@${name}@");
      lib.self.data.dn42 = {
        ipv4 = "172.20.232.0/26";
        ipv6 = "fd53:90fd:4bb6::/48";
      };
    };
  };
  cases = {
    default = { };
    proxy = {
      needProxy = true;
    };
    single = {
      needProxy = true;
      proxyHosts = [ "relay.example" ];
    };
    noSocks = {
      socks = false;
    };
    xray = {
      core = "xray";
    };
    xrayProxy = {
      core = "xray";
      needProxy = true;
    };
    xraySingle = {
      core = "xray";
      needProxy = true;
      proxyHosts = [ "relay.example" ];
    };
    xrayNoSocks = {
      core = "xray";
      socks = false;
    };
    xrayPacket = {
      core = "xray";
      xhttpMode = "packet-up";
    };
    xrayAlternate = {
      core = "xray";
      xrayPort = 16811;
      xhttpPath = "/alternate";
      serverName = "alternate.example";
    };
    packet = {
      xhttpMode = "packet-up";
    };
    alternate = {
      xrayPort = 16811;
      xhttpPath = "/alternate";
      serverName = "alternate.example";
    };
    alternateProxy = {
      needProxy = true;
      xhttpXmux = {
        maxConnections = "2-4";
        hMaxRequestTimes = "100-200";
        hMaxReusableSecs = "300-600";
        hKeepAlivePeriod = 30;
      };
      realityMaxTimeDifference = "30s";
    };
    paced = {
      needProxy = true;
      xhttpUplinkChunkSize = "131072-262144";
      xhttpScMaxEachPostBytes = "131072-262144";
      xhttpScMinPostsIntervalMs = "20-50";
    };
    xrayAlternateProxy = {
      core = "xray";
      needProxy = true;
      xhttpXmux = cases.alternateProxy.xhttpXmux;
    };
    legacy = {
      core = "sing-box";
    };
    legacyProxy = {
      core = "sing-box";
      needProxy = true;
    };
  };
  evaluate =
    name: args:
    let
      cfg =
        (import "${pkgs.path}/nixos/lib/eval-config.nix" {
          inherit pkgs;
          system = pkgs.stdenv.hostPlatform.system;
          modules = [
            fixtureSops
            (import ../nixos/modules/services/xray.nix args)
            { networking.nftables.enable = name != "default"; }
          ];
        }).config;
      core = args.core or "sing-box-extended";
      serviceName = if core == "xray" then "xray" else "sing-box";
      template = cfg.sops.templates."${serviceName}-config.json";
      moduleAssertions =
        ((import ../nixos/modules/services/xray.nix args) {
          config = cfg;
          inherit pkgs lib;
        }).assertions;
    in
    assert lib.all (entry: entry.assertion) moduleAssertions;
    {
      inherit args core serviceName;
      config = builtins.fromJSON template.content;
      templateMode = template.mode;
      templatePath = template.path;
      templateNames = builtins.attrNames cfg.sops.templates;
      inherit (template) restartUnits;
      secretModes = lib.mapAttrs (_: secret: secret.mode) cfg.sops.secrets;
      service = cfg.systemd.services.${serviceName}.serviceConfig;
      environment = cfg.systemd.services.${serviceName}.environment;
      serviceNames = builtins.attrNames cfg.systemd.services;
      package = lib.getExe (
        if core == "xray" then cfg.services.xray.package else cfg.services.sing-box.package
      );
      xrayEnabled = cfg.services.xray.enable;
      singBoxEnabled = cfg.services.sing-box.enable;
      restartCommand = cfg.systemd.services.proxy-restart.serviceConfig.ExecStart;
      firewall = {
        tcp = cfg.networking.firewall.allowedTCPPorts;
        udp = cfg.networking.firewall.allowedUDPPorts;
        trustedInterfaces = cfg.networking.firewall.trustedInterfaces;
        extraCommands = cfg.networking.firewall.extraCommands;
        extraInputRules = cfg.networking.firewall.extraInputRules;
      };
      traefik = cfg.services.traefik.dynamicConfigOptions.tcp;
    };
  fixtures = builtins.toJSON (lib.mapAttrs evaluate cases);
in
pkgs.runCommand "xray-config-test"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgs.openssl
      pkgs.xray
      pkgs.mihomo
      pkgs.sing-box
    ];
    inherit fixtures;
    extended = lib.getExe pkgs.nur.repos.ataraxiasjel.sing-box-extended;
  }
  ''
    python3 ${./xray-config-test.py} "$fixtures"
    touch "$out"
  ''
