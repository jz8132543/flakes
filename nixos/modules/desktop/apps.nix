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
  ];
  environment.systemPackages = with pkgs; [
    qrcp
    android-tools
    wpsoffice-cn
    # mihomo-party
  ];
  environment.shellAliases = {
    qrcp = "qrcp --port ${toString config.ports.qrcp}";
  };
  networking.firewall.allowedTCPPorts = [
    config.ports.qrcp
  ];
}
