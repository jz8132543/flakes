{
  osConfig,
  lib,
  ...
}:
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
        "CanonicalDomains" = concatStringsSep " " (
          [ osConfig.networking.domain ] ++ osConfig.environment.domains
        );
        "CanonicalizeMaxDots" = "0";
        # fix kde connection for android
        "HostKeyAlgorithms" = "+ssh-rsa";
      };
      matchBlocks = {
        "github.com" = {
          user = "git";
          hostname = "ssh.github.com";
          port = 443;
        };
        "gitlab.com" = {
          user = "git";
          hostname = "altssh.gitlab.com";
          port = 443;
        };
        "*" = {
          user = "tippy";
          checkHostIP = false;
          forwardAgent = true;
          # forwardX11 = true;
          userKnownHostsFile = "/dev/null";
          serverAliveInterval = 3;
          serverAliveCountMax = 6;
          compression = false;
          controlMaster = "auto";
          controlPath = "~/.ssh/master-%r@%n:%p";
          controlPersist = "10m";
        };
        "canonical" = {
          match = concatStrings [
            "canonical final Host "
            (concatMapStringsSep "," (
              x:
              concatStrings [
                "*."
                x
              ]
            ) ([ osConfig.networking.domain ] ++ osConfig.environment.domains))
          ];
          port = osConfig.ports.ssh;
        };
      };
      includes = [
        "config.d/*"
      ];
    };
  };

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
}
