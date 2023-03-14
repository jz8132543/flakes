{ ... }:

{
  programs = {
    ssh = {
      enable = true;
      extraConfig = ''
        CanonicalizeHostname yes
        CanonicalDomains dora.im
        CheckHostIP no
        StrictHostKeyChecking no
        UserKnownHostsFile /dev/null
      '';
      matchBlocks = {
        "github.com" = { user = "git"; };
        "gitlab.com" = { user = "git"; };
        "*" = { user = "tippy"; };
      };
      includes = [
        "config.d/*"
      ];
    };
  };
}
