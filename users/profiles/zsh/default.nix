{ config, pkgs, osConfig, ... }:

let
  cfg = config.home.global-persistence;
  sysCfg = osConfig.environment.global-persistence;
in{
  programs = {
    zsh = {
      enable = true;
      enableAutosuggestions = true;
      enableCompletion = true;
      enableSyntaxHighlighting = false;
      dotDir = ".config/zsh";
      shellAliases = {
        deploy = "deploy --skip-checks";
        rebuild =
          "nixos-rebuild --use-remote-sudo -v -L --flake $HOME/Source/flakes";
        nu = "rebuild switch --upgrade";
        hu = "home-manager switch";
        ngc =
          "sudo nix-env --profile /nix/var/nix/profiles/system --delete-generations +2;nix-env --delete-generations +2;nix-collect-garbage";
        catage =
          "nix-shell -p ssh-to-age --run 'cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age'";
        ll = "ls -l";
        ls = "exa --icons";
        tree = "exa --tree --icons";
        top = "btm";
        # BAT
        cat = "bat --style=plain";
        fd = "fd -X bat";
        fzf =
          "fzf --preview 'bat --color=always --style=numbers --line-range=:500 {}'";
        batdiff =
          "git diff --name-only --relative --diff-filter=d | xargs bat --diff";

        kubectl = "sudo k3s kubectl";
        sops-update = "find . -name '*' -exec sops updatekeys {} \\;";
      };
      history = {
        size = 10000;
        path = 
          (if config.home.global-persistence.enabled
          then "../../${sysCfg.root}${cfg.home}/.config/zsh/zsh_history"
          else "$HOME/.config/zsh/zsh_history");
      };
      oh-my-zsh = {
        enable = true;
        plugins = [
          "git"
          "thefuck"
          "docker"
          "sudo"
          "colored-man-pages"
          "vi-mode"
          "z"
          "extract"
        ];
      };
      plugins = with pkgs; [
        {
          name = "powerlevel10k";
          src = pkgs.zsh-powerlevel10k;
          file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
        }
        {
          name = "powerlevel10k-config";
          src = ./p10k;
          file = "p10k.zsh";
        }
        {
          name = "fast-syntax-highlighting";
          src = pkgs.zsh-fast-syntax-highlighting;
          file = "share/zsh/site-functions/fast-syntax-highlighting.plugin.zsh";
        }
      ];
    };
    z-lua = {
      enable = true;
      enableZshIntegration = true;
    };
  };
}
