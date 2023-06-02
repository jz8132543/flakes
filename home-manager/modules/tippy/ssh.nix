{osConfig, ...}: {
  programs = {
    ssh = {
      enable = true;
      userKnownHostsFile = "/dev/null";
      serverAliveInterval = 15;
      serverAliveCountMax = 4;
      compression = false;
      controlMaster = "auto";
      controlPersist = "10m";
      extraOptionOverrides = {
        "StrictHostKeyChecking" = "no";
        "LogLevel" = "ERROR";
        "CanonicalizeHostname" = "yes";
        "CanonicalDomains" = "ts.dora.im dora.im";
        "CanonicalizeMaxDots" = "0";
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
          # forwardAgent = true;
          # forwardX11 = true;
        };
        "canonical" = {
          match = "canonical final Host *.ts.dora.im,*.dora.im";
          port = osConfig.ports.ssh;
        };
      };
      includes = [
        "config.d/*"
      ];
    };
  };
}
