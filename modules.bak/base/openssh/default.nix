{ ... }:

let
  aliveInterval = "30";
  aliveCountMax = "60";
in {
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

  networking.firewall.allowedTCPPorts = [ 22 ];

  environment.global-persistence = {
    files = [
      # ssh daemon host keys
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
    ];
    user.files = [
      ".ssh/known_hosts"
    ];
  };
}
