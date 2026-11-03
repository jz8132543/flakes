{ lib }:
let
  mkConfig = proxyPublicTcp: {
    programs.ssh = {
      customHosts = {
        domestic.port = 50560;
        extra.port = 62022;
        https.port = 443;
      };
      transport = {
        effectiveEnabled = true;
        udpPortRange = {
          from = 61001;
          to = 61999;
        };
      };
    };
    networking.domain = "example.test";
    ports.ssh = 1022;
    users.users.mihomo.uid = 998;
    services = {
      mihomo = {
        enable = true;
        routing.proxyPublicSsh = proxyPublicTcp;
      };
      dn42 = {
        enable = true;
        ikePort = 500;
        natTPort = 4500;
        allClusterTunnelPorts = [
          500
          4500
        ];
      };
      subscriptionPublisher = {
        enable = true;
        dn42Domain = "dn42";
        nodes = [ ];
        groups = [ ];
      };
    };
  };
  enabled = mkConfig true;
  disabled = mkConfig false;
  routing =
    config:
    (import ../nixos/modules/desktop/mihomo-routing.nix {
      inherit config lib;
      pkgs = { };
    }).config.content;
  rules =
    config:
    (import ../nixos/modules/services/sub.nix {
      inherit config lib;
      # Capture the YAML value without building it or reading any secrets.
      pkgs.formats.yaml = _: { generate = _: value: value; };
    }).config.content.sops.templates."subscription/mihomo.yaml".file.rules;
  script = config: (routing config).systemd.services.mihomo-loop-prevention.script;
  nft = config: (routing config).networking.nftables.tables.mihomo-process-bypass.content;
  enabledRules = rules enabled;
  disabledRules = rules disabled;
  sshPorts = [
    22
    1022
    50560
    62022
  ];
  sshMark = "tcp dport { ${
    lib.concatMapStringsSep ", " toString sshPorts
  } } counter meta mark set meta mark | 0x1";
  before =
    first: second:
    let
      index = rule: lib.lists.findFirstIndex (r: r == rule) null enabledRules;
    in
    index first != null && index second != null && index first < index second;
  proxyRule = p: "AND,((NETWORK,TCP),(DST-PORT,${toString p})),PROXY";
  domesticRule = p: "AND,((NETWORK,TCP),(DST-PORT,${toString p}),(GEOIP,CN)),DIRECT";
  checks = {
    defaultDisabled =
      !(import ../nixos/modules/desktop/mihomo-routing.nix {
        config = disabled;
        inherit lib;
        pkgs = { };
      }).options.services.mihomo.routing.proxyPublicSsh.default;
    arx8Enabled =
      (import ../nixos/hosts/arx8/default.nix {
        config = { };
        nixosModules = { };
        pkgs = { };
      }).services.mihomo.routing.proxyPublicSsh;
    legacyBypass =
      lib.hasInfix sshMark (nft disabled)
      && lib.all (
        p:
        lib.hasInfix "ip -4 rule add ipproto tcp dport ${toString p} lookup main priority 8996" (
          script disabled
        )
      ) sshPorts
      && builtins.elem "DST-PORT,22,DIRECT" disabledRules
      && builtins.elem "DST-PORT,1022,DIRECT" disabledRules
      && lib.all (p: !builtins.elem (proxyRule p) disabledRules) sshPorts;
    publicIPv4EntersTun =
      !lib.hasInfix sshMark (nft enabled)
      && lib.all (
        p:
        !lib.hasInfix "ip -4 rule add ipproto tcp dport ${toString p} lookup main priority 8996" (
          script enabled
        )
      ) sshPorts
      && lib.hasInfix "ip -4 rule add not fwmark 0x1/0x1 lookup 2022 priority 8998" (script enabled);
    ipv6DirectWithFallback =
      lib.all (
        p:
        lib.hasInfix "ip -6 rule add ipproto tcp dport ${toString p} lookup main priority 8996" (
          script enabled
        )
      ) sshPorts
      && lib.hasInfix "ip -6 rule add not fwmark 0x1/0x1 lookup 2022 priority 8998" (script enabled);
    antiLoopUnchanged =
      lib.all (command: lib.hasInfix command (script enabled) && lib.hasInfix command (script disabled)) [
        "for prio in 8980 8985 8995 8996 8998; do"
        "ip -4 rule add uidrange $mihomoUid-$mihomoUid lookup main priority 8980"
        "ip -6 rule add uidrange $mihomoUid-$mihomoUid lookup main priority 8980"
        "ip -4 rule add uidrange $mihomoUid-$mihomoUid unreachable priority 8985"
        "ip -6 rule add uidrange $mihomoUid-$mihomoUid unreachable priority 8985"
        "ip -4 rule add fwmark 0x1/0x1 unreachable priority 8995"
        "ip -6 rule add fwmark 0x1/0x1 unreachable priority 8995"
        "ip -4 rule add to 224.0.0.0/4 lookup main priority 8996"
        "ip -6 rule add to ff00::/8 lookup main priority 8996"
      ]
      && lib.hasInfix "meta skuid 998 counter meta mark set meta mark | 0x1" (nft enabled)
      && lib.hasInfix "tcp dport { 500, 4500 } counter meta mark set meta mark | 0x1" (nft enabled);
    udpPoolUnchanged =
      lib.all
        (
          family:
          lib.all
            (
              direction:
              lib.hasInfix "ip -${family} rule add ipproto udp ${direction} 61001-61999 lookup main priority 8996" (
                script enabled
              )
              && lib.hasInfix "udp ${direction} 61001-61999 counter meta mark set meta mark | 0x1" (nft enabled)
            )
            [
              "sport"
              "dport"
            ]
        )
        [
          "4"
          "6"
        ];
    privateBeforeProxy = lib.all (guard: lib.all (p: before guard (proxyRule p)) sshPorts) [
      "IP-CIDR,172.20.0.0/14,DIRECT,no-resolve"
      "IP-CIDR,172.31.0.0/16,DIRECT,no-resolve"
      "IP-CIDR,10.0.0.0/8,DIRECT,no-resolve"
      "IP-CIDR,fd00::/8,DIRECT,no-resolve"
      "GEOSITE,private,DIRECT"
      "GEOIP,private,DIRECT"
      "IP-CIDR,100.64.0.0/10,DIRECT,no-resolve"
      "IP-CIDR,fc00::/7,DIRECT,no-resolve"
      "DOMAIN-SUFFIX,dn42,DIRECT"
      "DOMAIN-SUFFIX,ts,DIRECT"
      "DOMAIN-SUFFIX,et,DIRECT"
    ];
    domesticBeforeProxy = lib.all (p: before (domesticRule p) (proxyRule p)) sshPorts;
    earlyPublicOverride =
      lib.all (p: before (proxyRule p) "DOMAIN-SUFFIX,dora.im,DIRECT") sshPorts
      && !builtins.elem "DST-PORT,22,DIRECT" enabledRules
      && !builtins.elem "DST-PORT,1022,DIRECT" enabledRules
      && !builtins.elem (proxyRule 443) enabledRules;
    serviceDecoupling =
      !(import ../nixos/modules/base/openssh.nix {
        config = disabled;
        inherit lib;
        pkgs = { };
      }).options.programs.ssh
        ? proxyPublicTcp
      && !builtins.elem "AND,((NETWORK,TCP),(DST-PORT,443),(DOMAIN,ts.example.test)),PROXY" enabledRules;
  };
in
assert lib.assertMsg (lib.all (passed: passed) (builtins.attrValues checks))
  "Public TCP SSH routing regression: ${
    lib.concatStringsSep ", " (builtins.attrNames (lib.filterAttrs (_: passed: !passed) checks))
  }";
checks
