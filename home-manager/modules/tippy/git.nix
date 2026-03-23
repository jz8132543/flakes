{ pkgs, ... }:
{
  programs.delta.enable = true;
  programs.git = {
    enable = true;
    package = pkgs.gitFull;
    lfs.enable = true;
    settings = {
      user.name = "jz8132543";
      user.email = "i@dora.im";
      # user.signingkey = "23232A6D050ACE46DF02D72B84A772A8519FC163";
      init.defaultBranch = "main";
      pull.rebase = false;
      pull.ff = "only";
      commit.gpgSign = true;
      gpg.format = "ssh";
      user.signingkey = "~/.ssh/id_ed25519.pub";
      bash.showInformativeStatus = true;

      # Git 原生配置节名是 [alias]，这里显式写成 `settings.alias`
      # 比 `settings.aliases` 更标准，也更容易和上游文档对应。
      alias = {
        # 基础高频操作：尽量保持短、稳、没有歧义。
        a = "add -p";
        c = "commit";
        co = "checkout";
        cob = "checkout -b";
        ba = "branch -a";
        bd = "branch -d";
        bD = "branch -D";
        d = "diff";
        dc = "diff --cached";
        ds = "diff --staged";
        f = "fetch -p";
        p = "push";
        r = "restore";
        rs = "restore --staged";
        st = "status -sb";

        # Reset 类命令保留显式名字，降低误操作概率。
        soft = "reset --soft";
        hard = "reset --hard";
        s1ft = "soft HEAD~1";
        h1rd = "hard HEAD~1";

        # 日志类命令统一保留图形化输出，便于快速扫历史。
        lg = "log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
        plog = "log --graph --pretty='format:%C(red)%d%C(reset) %C(yellow)%h%C(reset) %ar %C(green)%aN%C(reset) %s'";
        tlog = "log --stat --since='1 Day Ago' --graph --pretty=oneline --abbrev-commit --date=relative";
        rank = "shortlog -sn --no-merges";

        # 仅清理已合并且不是当前分支的本地分支，避免误删。
        bdm = "!git branch --merged | grep -v '^\\*' | xargs -r -n 1 git branch -d";
      };
    };
  };
}
