{ pkgs, ... }: {
  programs.git = {
    enable = true;
    package = pkgs.gitAndTools.gitFull;
    aliases = {
      pushall = "!git remote | xargs -L1 git push --all";
      graph = "log --decorate --oneline --graph";
    };
    userName = "jz8132543";
    userEmail = "jz8132543@live.cn";
    extraConfig = {
      init.defaultBranch = "main";
      url."https://github.com/".insteadOf = "git://github.com/";
      url."https://gitlab.com/".insteadOf = "git://gitlab.com/";
    };
    lfs = { enable = true; };
    ignores = [ ".direnv" "result" ];
    #signing = {
    #  signByDefault = true;
    #  key = "CE707A2C17FAAC97907FF8EF2E54EA7BFE630916";
    #};
  };
}
