{
  config,
  pkgs,
  nixosModules,
  ...
}:
{
  imports = [
    nixosModules.services.aria2
    nixosModules.services.podman
    nixosModules.services.easytier-web
    nixosModules.services.ntopng
  ];
  programs.k3b.enable = true;
  environment.systemPackages = with pkgs; [
    qrcp
    android-tools
    wpsoffice-cn
    dvdplusrwtools
    # mihomo-party
  ];
  environment.shellAliases = {
    qrcp = "qrcp --port ${toString config.ports.qrcp}";
  };
  networking.firewall.allowedTCPPorts = [
    config.ports.qrcp
  ];
}
