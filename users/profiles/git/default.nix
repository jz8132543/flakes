{ pkgs, ... }:

{
  programs.git = {
    enable = true;
    package = pkgs.gitFull;
    lfs.enable = true;

    userName = "jz8132543";
    userEmail = "jz8132543@live.cn";
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = false;
      pull.ff = "only";
      credential.helper = "libsecret";
      commit.gpgSign = true;

      # fish git status
      bash.showInformativeStatus = true;

      url."https://github.com/".insteadOf = "git://github.com/";
      url."https://gitlab.com/".insteadOf = "git://gitlab.com/";
    };

    aliases = {
      a = "add -p";
      co = "checkout";
      cob = "checkout -b";
      f = "fetch -p";
      c = "commit";
      p = "push";
      ba = "branch -a";
      bd = "branch -d";
      bD = "branch -D";
      d = "diff";
      dc = "diff --cached";
      ds = "diff --staged";
      r = "restore";
      rs = "restore --staged";
      st = "status -sb";

      # reset
      soft = "reset --soft";
      hard = "reset --hard";
      s1ft = "soft HEAD~1";
      h1rd = "hard HEAD~1";

      # logging
      lg =
        "log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
      plog =
        "log --graph --pretty='format:%C(red)%d%C(reset) %C(yellow)%h%C(reset) %ar %C(green)%aN%C(reset) %s'";
      tlog =
        "log --stat --since='1 Day Ago' --graph --pretty=oneline --abbrev-commit --date=relative";
      rank = "shortlog -sn --no-merges";

      # delete merged branches
      bdm = "!git branch --merged | grep -v '*' | xargs -n 1 git branch -d";
    };
  };
}
