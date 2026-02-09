{
  osConfig,
  lib,
  config,
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
        "HostKeyAlgorithms " = "+ssh-rsa";
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

  # SSH requires the config file to be a real file with 0600 permissions, not a symlink
  # programs.ssh generates a symlink by default, so we copy it to a real file on activation
  home.activation.fixSshPermissions = lib.hm.dag.entryAfter ["writeBoundary"] ''
    # Ensure .ssh directory exists with correct permissions
    $DRY_RUN_CMD mkdir -p $HOME/.ssh
    $DRY_RUN_CMD chmod 700 $HOME/.ssh
    
    # The SSH config symlink that home-manager creates
    SSH_CONFIG_LINK="$HOME/.ssh/config"
    
    # Get the actual file from the store that the symlink points to
    if [ -L "$SSH_CONFIG_LINK" ]; then
      SSH_CONFIG_SOURCE=$(readlink -f "$SSH_CONFIG_LINK")
      $DRY_RUN_CMD rm -f "$SSH_CONFIG_LINK"
      $DRY_RUN_CMD cp "$SSH_CONFIG_SOURCE" "$SSH_CONFIG_LINK"
      $DRY_RUN_CMD chmod 600 "$SSH_CONFIG_LINK"
    elif [ ! -f "$SSH_CONFIG_LINK" ]; then
      # If config doesn't exist, something went wrong
      echo "Warning: SSH config not found at $SSH_CONFIG_LINK"
    fi
  '';
}
