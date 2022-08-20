{ ...  }:

{
  programs = {
    ssh = {
      enable = true;
      extraConfig = ''
        CanonicalizeHostname yes
        CanonicalDomains dora.im
        CheckHostIP no
        StrictHostKeyChecking no
      '';
      matchBlocks = {
        "github.com" = {
          user = "git";
          identityFile = "~/.ssh/git_id_rsa";
        };
        "gitlab.com" = {
          user = "git";
          identityFile = "~/.ssh/git_id_rsa";
        };
        "*" = {
          user = "tippy";
        };
      };
    };
  };
}
