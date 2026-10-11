{ pkgs, ... }:
{
  services.eternal-terminal.enable = false;
  # eternal-terminal package is omitted since the service is disabled
  environment.systemPackages = with pkgs; [ ];
  # Optionally include the package only when the service is enabled
  # environment.systemPackages = with pkgs; optional services.eternal-terminal.enable eternal-terminal;

  networking.firewall.allowedTCPPorts = [
    2022 # Eternal Terminal 默认数据传输端口
  ];
}
