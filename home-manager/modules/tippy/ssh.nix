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
}
