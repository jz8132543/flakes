{ pkgs, ... }:
{
  programs.starship = {
    enable = true;
  };

  programs.zsh = {
    enable = true;
    history.path = "$HOME/.local/share/zsh/zsh_history";

    enableVteIntegration = true;
    enableAutosuggestions = true;
    enableSyntaxHighlighting = true;
    enableCompletion = true;
    autocd = true;
    oh-my-zsh = {
      enable = true;
      theme = "";
      plugins = [ "git" "sudo" "z" "vi-mode" "colored-man-pages" ];
    };
    shellAliases = {
      ls = "${pkgs.exa}/bin/exa --icons";
      tree = "${pkgs.exa}/bin/exa --tree --icons";
      top = "${pkgs.bottom}/bin/btm";
      cat = "${pkgs.bat}/bin/bat --style=plain";
      fzf =
        "${pkgs.fzf}/bin/fzf --preview 'bat --color=always --style=numbers --line-range=:500 {}'";
      batdiff =
        "git diff --name-only --relative --diff-filter=d | xargs ${pkgs.bat}/bin/bat --diff";
      rg = "${pkgs.ripgrep}/bin/rg --no-ignore";
      # scp = "time scp -Cpr -o Compression=yes";
    };
  };
  home.persistence."/nix/persist/home/tippy" = {
    directories = [
      ".local/share/zsh"
    ];
  };
}
