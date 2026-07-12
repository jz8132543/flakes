{
  osConfig,
  lib,
  pkgs,
  ...
}:
let
  sshRaceDomains = [
    "dora.im"
    "mag"
    "et"
  ];
in
with lib.strings;
{
  programs = {
    ssh = {
      enable = true;
      enableDefaultConfig = false;
      # https://github.com/NixOS/nixpkgs/issues/168322
      # controlPersist = "10m";
      extraOptionOverrides = {
        "StrictHostKeyChecking" = "no";
        "LogLevel" = "ERROR";
        "CanonicalizeHostname" = "yes";
        "CanonicalDomains" = concatStringsSep " " sshRaceDomains;
        # fix kde connection for android
        "HostKeyAlgorithms" = "+ssh-rsa";
      };
      settings = {
        "Host github.com" = {
          User = "git";
          HostName = "ssh.github.com";
          Port = 443;
        };
        "Host gitlab.com" = {
          User = "git";
          HostName = "altssh.gitlab.com";
          Port = 443;
        };
        "Host *" = {
          User = "tippy";
          CheckHostIP = false;
          ForwardAgent = true;
          Port = osConfig.ports.ssh;
          ProxyCommand = "${pkgs.ssh-race}/bin/ssh-race -domains ${concatStringsSep "," sshRaceDomains} %h %p";
          # ForwardX11 = true;
          UserKnownHostsFile = "/dev/null";
          ServerAliveInterval = 3;
          ServerAliveCountMax = 6;
          Compression = false;
          ControlMaster = "auto";
          ControlPath = "~/.ssh/master-%r@%n:%p";
          ControlPersist = "10m";
        };
        "Match canonical final Host ${concatMapStringsSep "," (x: "*.${x}") sshRaceDomains}" = {
          Port = osConfig.ports.ssh;
        };
      };
      includes = [
        "config.d/*"
      ];
    };
  };

  home.file.".ssh/config".force = true;

  home.activation.sshConfigPermissions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ssh_dir="$HOME/.ssh"
    if [ -d "$ssh_dir" ]; then
      $DRY_RUN_CMD echo "Fixing permissions for $ssh_dir..."
      $DRY_RUN_CMD chmod 700 "$ssh_dir"

      # Handle config file
      ssh_config="$ssh_dir/config"
      if [ -e "$ssh_config" ]; then
        if [ -L "$ssh_config" ]; then
          $DRY_RUN_CMD echo "Converting $ssh_config from symlink to real file..."
          target=$(readlink -f "$ssh_config")
          $DRY_RUN_CMD rm "$ssh_config"
          $DRY_RUN_CMD cp "$target" "$ssh_config"
        fi
        $DRY_RUN_CMD chmod 600 "$ssh_config"
      fi

      # Handle private keys
      for key in "$ssh_dir"/id_*; do
        if [ -e "$key" ] && [[ ! "$key" == *.pub ]]; then
          if [ -L "$key" ]; then
            $DRY_RUN_CMD echo "Converting private key $key from symlink to real file..."
            target=$(readlink -f "$key")
            $DRY_RUN_CMD rm "$key"
            $DRY_RUN_CMD cp "$target" "$key"
          fi
          $DRY_RUN_CMD chmod 600 "$key"
        fi
      done
    fi
  '';
  home.global-persistence.directories = [
    ".ssh"
  ];
}
