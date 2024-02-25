{osConfig, ...}: {
  programs = {
    ssh = {
      enable = true;
      userKnownHostsFile = "/dev/null";
      serverAliveInterval = 3;
      serverAliveCountMax = 6;
      compression = false;
      controlMaster = "auto";
      forwardAgent = true;
      # https://github.com/NixOS/nixpkgs/issues/168322
      # controlPersist = "10m";
      extraOptionOverrides = {
        "StrictHostKeyChecking" = "no";
        "LogLevel" = "ERROR";
        "CanonicalizeHostname" = "yes";
        "CanonicalDomains" = "dora.im ts.dora.im users.dora.im";
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
        };
        "canonical" = {
          match = "canonical final Host *.dora.im,*.ts.dora.im";
          port = osConfig.ports.ssh;
        };
      };
      includes = [
        "config.d/*"
      ];
    };
  };
}
