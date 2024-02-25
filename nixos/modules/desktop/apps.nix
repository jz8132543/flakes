{
  config,
  pkgs,
  ...
}: {
  programs = {
    clash-verge = {
      enable = true;
      # autoStart = true;
      tunMode = true;
    };
  };
  environment.systemPackages = with pkgs; [
    qrcp
  ];
  environment.shellAliases = {
    qrcp = "qrcp --port ${toString config.ports.qrcp}";
  };
  networking.firewall.allowedTCPPorts = [
    config.ports.qrcp
  ];
  environment.global-persistence.user = {
    directories = [
      ".config/clash-verge"
    ];
  };
}
