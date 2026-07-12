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
      matchBlocks = {
        github = {
          host = "github.com";
          user = "git";
          hostname = "ssh.github.com";
          port = 443;
        };
        gitlab = {
          host = "gitlab.com";
          user = "git";
          hostname = "altssh.gitlab.com";
          port = 443;
        };
        raceDomains = lib.hm.dag.entryBefore [ "*" ] {
          match = "canonical final host ${concatMapStringsSep "," (x: "*.${x}") sshRaceDomains}";
          user = "tippy";
          port = osConfig.ports.ssh;
        };
        "*" = {
          checkHostIP = false;
          forwardAgent = true;
          port = osConfig.ports.ssh;
          proxyCommand = "${pkgs.ssh-race}/bin/ssh-race -domains ${concatStringsSep "," sshRaceDomains} %h %p";
          # ForwardX11 = true;
          userKnownHostsFile = "/dev/null";
          serverAliveInterval = 3;
          serverAliveCountMax = 6;
          compression = false;
          controlMaster = "auto";
          controlPath = "~/.ssh/master-%r@%n:%p";
          controlPersist = "10m";
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
