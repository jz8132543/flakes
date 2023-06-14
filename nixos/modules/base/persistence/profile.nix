{inputs, ...}: {
  environment.global-persistence = {
    enable = true;
    root = "/persist";
    directories = [
      # service state directory
      "/var/lib"
      "/var/db"
      "/var/log"
      "/var/backup"
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
