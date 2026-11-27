{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.ai.openhands;
  inherit (cfg) network;
  bridge = "openhands0";
  subnet = "10.231.48.0/28";
  gatewayPort = toString config.services.new-api.port;
  resolvers = [
    "1.1.1.1"
    "9.9.9.9"
  ];
  fromCanvas = ''iifname "${bridge}"'';
  gateway = "${fromCanvas} ip saddr ${subnet} ip daddr ${network.gatewayAddress} tcp dport ${gatewayPort}";
in
{
  config = lib.mkIf (cfg.enable && network.enable) {
    assertions = [
      {
        assertion = config.networking.firewall.enable && config.networking.nftables.enable;
        message = "The dedicated OpenHands network requires the nftables firewall.";
      }
    ];

    environment.etc."containers/networks/openhands.json".source =
      pkgs.writeText "openhands-network.json"
        (
          builtins.toJSON {
            name = "openhands";
            id = builtins.hashString "sha256" "openhands";
            driver = "bridge";
            network_interface = bridge;
            created = "0001-01-01T00:00:00Z";
            subnets = [
              {
                inherit subnet;
                gateway = network.gatewayAddress;
              }
            ];
            ipv6_enabled = false;
            dns_enabled = false;
            ipam_options.driver = "host-local";
          }
        );

    services.ai.openhands.gatewayBaseUrl = lib.mkDefault "http://${network.gatewayAddress}:${gatewayPort}/v1";

    virtualisation.oci-containers.containers.openhands.extraOptions = [
      "--network=openhands"
    ]
    ++ map (ip: "--dns=${ip}") resolvers;

    systemd.services.podman-openhands = {
      after = [ "nftables.service" ];
      requires = [ "nftables.service" ];
    };

    networking.firewall.extraInputRules = ''
      ${gateway} accept
    '';

    networking.firewall.interfaces.${bridge}.allowedTCPPorts = [ config.services.new-api.port ];

    networking.nftables.tables.openhands = {
      family = "inet";
      content = ''
        chain host_input {
          type filter hook input priority filter - 10; policy accept;

          # Do not expose the bridge's gateway address through another interface.
          iifname != { "lo", "${bridge}" } ip daddr ${network.gatewayAddress} counter drop
          ${fromCanvas} ip saddr ${subnet} ct state { established, related } accept
          ${gateway} ct state new accept
          ${fromCanvas} counter drop
        }

        chain routed_egress {
          type filter hook forward priority filter - 10; policy accept;

          oifname "${bridge}" ct state { established, related } accept
          oifname "${bridge}" counter drop
          ${fromCanvas} meta nfproto != ipv4 counter drop
          ${fromCanvas} ip saddr != ${subnet} counter drop
          ${fromCanvas} ip daddr {
            0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8,
            169.254.0.0/16, 172.16.0.0/12, 192.0.0.0/24, 192.0.2.0/24,
            192.88.99.0/24, 192.168.0.0/16, 198.18.0.0/15, 198.51.100.0/24,
            203.0.113.0/24, 224.0.0.0/4, 240.0.0.0/4
          } counter drop
          ${lib.optionalString (network.publicInterface != null) ''
            ${fromCanvas} oifname "${network.publicInterface}" tcp dport { 80, 443 } accept
            ${fromCanvas} oifname "${network.publicInterface}" ip daddr { ${lib.concatStringsSep ", " resolvers} } meta l4proto { tcp, udp } th dport 53 accept
          ''}
          ${fromCanvas} counter drop
        }
      '';
    };
  };
}
