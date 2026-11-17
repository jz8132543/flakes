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
    ss = {
      ss = true;
    };
    ssProxy = {
      ss = true;
      needProxy = true;
    };
    packet = {
      xhttpMode = "packet-up";
    };
    alternate = {
      xrayPort = 16811;
      xhttpPath = "/alternate";
      serverName = "alternate.example";
    };
    legacy = {
      core = "sing-box";
    };
    legacyProxy = {
      core = "sing-box";
      needProxy = true;
    };
    legacySs = {
      core = "sing-box";
      ss = true;
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
      core = args.core or "xray";
      template = cfg.sops.templates."${core}-config.json";
      moduleAssertions =
        ((import ../nixos/modules/services/xray.nix args) {
          config = cfg;
          inherit pkgs lib;
        }).assertions;
    in
    assert lib.all (entry: entry.assertion) moduleAssertions;
    {
      inherit args core;
      config = builtins.fromJSON template.content;
      templateMode = template.mode;
      templatePath = template.path;
      templateNames = builtins.attrNames cfg.sops.templates;
      inherit (template) restartUnits;
      secretModes = lib.mapAttrs (_: secret: secret.mode) cfg.sops.secrets;
      service = cfg.systemd.services.${core}.serviceConfig;
      environment = cfg.systemd.services.${core}.environment;
      xrayEnabled = cfg.services.xray.enable;
      singBoxEnabled = cfg.services.sing-box.enable;
      restartCommand = cfg.systemd.services.proxy-restart.serviceConfig.ExecStart;
      firewall = {
        tcp = cfg.networking.firewall.allowedTCPPorts;
        udp = cfg.networking.firewall.allowedUDPPorts;
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
  }
  ''
    python3 ${./xray-config-test.py} "$fixtures"
    touch "$out"
  ''
