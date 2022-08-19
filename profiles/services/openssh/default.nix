{ ... }:

let
  aliveInterval = "30";
  aliveCountMax = "60";
in
{
  services.openssh = {
    enable = true;
    forwardX11 = true;
    openFirewall = true;
    extraConfig = ''
      ClientAliveInterval ${aliveInterval}
      ClientAliveCountMax ${aliveCountMax}
    '';
  };

  programs.ssh = {
    extraConfig = ''
      ServerAliveInterval ${aliveInterval}
      ServerAliveCountMax ${aliveCountMax}
    '';
  };

}
