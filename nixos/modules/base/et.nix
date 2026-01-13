{ pkgs, ... }:
{
  services.eternal-terminal.enable = true;
  environment.systemPackages = with pkgs; [ eternal-terminal ];
  networking.firewall.allowedTCPPorts = [
    2022 # Eternal Terminal 默认数据传输端口
  ];
}
