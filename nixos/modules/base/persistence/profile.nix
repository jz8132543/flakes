{ inputs, ... }: {
  imports = [
    inputs.impermanence.nixosModules.impermanence
  ];
  environment.persistence."/nix/persist" = {
    # hideMounts = true;
    directories = [
      # service state directory
      "/var/lib"
      "/var/db"
      "/var/log"
    ];
    files = [
      # systemd machine-id
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
    ];
  };
}
