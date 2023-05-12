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
      '';
      matchBlocks = {
        "github.com" = { user = "git"; };
        "gitlab.com" = { user = "git"; };
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
