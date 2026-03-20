{
  config,
  nixosModules,
  lib,
  pkgs,
  ...
}:
{
  imports =
    nixosModules.cloud.all
    ++ nixosModules.users.tippy.all
    ++ nixosModules.services.media.all
    ++ [
      ./hardware-configuration.nix
      ./_steam
      nixosModules.services.ddns
      nixosModules.services.traefik
      nixosModules.optimize.dev
      # nixosModules.services.postgres
      nixosModules.services.derp
      nixosModules.services.homepage-machine
      nixosModules.desktop.mihomo

      # (import nixosModules.services.matrix { PG = "127.0.0.1"; })
    ];
  # services.qemuGuest.enable = true;

  environment.seedbox.enable = false;

  # Enable NVIDIA HWA for Jellyfin and containers
  systemd.services.jellyfin-disable-transcoding.enable = false;
  users.users.jellyfin.extraGroups = [
    "video"
    "render"
  ];

  environment.isNAT = true;
  environment.isCN = true;

  # Prevent laptop from sleeping on lid close

  ports.derp-stun = lib.mkForce 3440;
  environment.altHTTPS = 8443;

  nix.settings.substituters = lib.mkForce [ "https://mirrors.ustc.edu.cn/nix-channels/store" ];

  networking.nftables.tables.vpn-holepunch-bypass = {
    family = "inet";
    content = ''
      chain output {
        type route hook output priority mangle; policy accept;

        # Keep Tailscale/EasyTier hole-punch and transport traffic on real WAN
        # routes so it cannot recurse into Meta/TUN policy routing.
        udp dport { 3478, ${toString config.services.tailscale.port}, ${toString config.ports.easytier-quic} } counter meta mark set meta mark | 0x1
        udp sport { 3478, ${toString config.services.tailscale.port}, ${toString config.ports.easytier-quic} } counter meta mark set meta mark | 0x1
        tcp dport { ${toString config.ports.easytier-traefik-wss}, ${toString config.ports.easytier-faketcp} } counter meta mark set meta mark | 0x1
        tcp sport { ${toString config.ports.easytier-traefik-wss}, ${toString config.ports.easytier-faketcp} } counter meta mark set meta mark | 0x1
      }
    '';
  };

  systemd.services.vpn-holepunch-bypass = {
    description = "Route Tailscale and EasyTier hole-punch traffic via main";
    after = [
      "network-online.target"
      "nftables.service"
      "mihomo.service"
      "tailscaled.service"
      "easytier-mesh.service"
    ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.iproute2 ];
    script = ''
      while ip rule del fwmark 0x1/0x1 lookup main priority 8990 2>/dev/null; do :; done
      ip rule add fwmark 0x1/0x1 lookup main priority 8990
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };
}
