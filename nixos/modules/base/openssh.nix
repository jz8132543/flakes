{
  lib,
  config,
  ...
}: {
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      # PermitRootLogin = lib.mkForce "no";
      PasswordAuthentication = lib.mkForce false;
      KbdInteractiveAuthentication = false;
    };
    ports = [config.ports.ssh];
    openFirewall = true;
    extraConfig = ''
      ClientAliveInterval 3
      ClientAliveCountMax 6
    '';
    hostKeys = [
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
      {
        path = "/etc/ssh/ssh_host_rsa_key";
        type = "rsa";
      }
    ];

    # certAuth = lib.optionalAttrs (builtins.pathExists /etc/ssh/ssh_host_ed25519_key-cert.pub) {
    #   enable = true;
    #   hostCertificate = "/etc/ssh/ssh_host_ed25519_key-cert.pub";
    #   userCAKey = "/etc/ssh/CA_User_key.pub";
    # };
  };

  services.fail2ban = {
    enable = true;
    maxretry = 5;
    ignoreIP = [
      "127.0.0.0/8"
      "10.0.0.0/8"
      "100.64.0.0/10"
      "192.168.0.0/16"
    ];
  };

  # programs.ssh.package = pkgs.openssh_hpn;
  programs.mosh.enable = true;
}
