{ ... }:

{
  programs = {
    ssh = {
      enable = true;
      userKnownHostsFile = "/dev/null";
      serverAliveInterval = 30;
      serverAliveCountMax = 60;
      compression = true;
      extraConfig = ''
        CanonicalizeHostname yes
        CanonicalDomains dora.im
        StrictHostKeyChecking no
        LogLevel ERROR
      '';
      matchBlocks = {
        "github.com" = { user = "git"; hostname = "ssh.github.com"; port = 443; };
        "gitlab.com" = { user = "git"; hostname = "altssh.gitlab.com"; port = 443; };
        "*" = {
          user = "tippy";
          checkHostIP = false;
          forwardAgent = true;
          forwardX11 = true;
        };
      };
      includes = [
        "config.d/*"
      ];
    };
  };
}
