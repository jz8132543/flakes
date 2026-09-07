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
    # nixosModules.services.ntopng
  ];
  programs.k3b.enable = true;
  services.udev.extraRules = ''
    SUBSYSTEM=="block", KERNEL=="sr[0-9]*", GROUP="cdrom", MODE="0660"
  '';
  services.gvfs.enable = true;
  environment.systemPackages = with pkgs; [
    libmtp
    simple-mtpfs
    brasero # Added GNOME native burning tool
    qrcp
    android-tools
    wpsoffice-cn
    dvdplusrwtools
    peazip
    # mihomo-party
  ];
  environment.shellAliases = {
    qrcp = "qrcp --port ${toString config.ports.qrcp}";
  };
  services.udev.packages = [ pkgs.libmtp ];
  networking.firewall.allowedTCPPorts = [
    config.ports.qrcp
  ];
}
