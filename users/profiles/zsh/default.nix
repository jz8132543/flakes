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
        sops-update = "find . -name '*' -exec sops updatekeys {} \\;";
        # ll = "ls -l";
        # ls = "exa --icons";
        # tree = "exa --tree --icons";
        top = "btm";
        # BAT
        cat = "bat --style=plain";
        fzf =
          "fzf --preview 'bat --color=always --style=numbers --line-range=:500 {}'";
        batdiff =
          "git diff --name-only --relative --diff-filter=d | xargs bat --diff";

        kubectl = "sudo k3s kubectl";
        scp = "time scp -Cpr -o Compression=yes";
      };
      history = {
        size = 10000;
        path = 
          (if config.home.global-persistence.enabled
          then "${sysCfg.root}${cfg.home}/.config/zsh/zsh_history"
          else "$HOME/.config/zsh/zsh_history");
      };
      plugins = with pkgs; [
        {
          name = "pure-prompt";
          src = pkgs.pure-prompt;
        }
        {
          name = "fast-syntax-highlighting";
          src = pkgs.zsh-fast-syntax-highlighting;
          file = "share/zsh/site-functions/fast-syntax-highlighting.plugin.zsh";
        }
        {
          name = "zsh-nix-shell";
          src = pkgs.zsh-nix-shell;
          file = "share/zsh-nix-shell/nix-shell.plugin.zsh";
        }
        {
          name = "zsh-edit";
          file = "zsh-edit.plugin.zsh";
          src = pkgs.fetchFromGitHub {
            owner = "marlonrichert";
            repo = "zsh-edit";
            rev = "4a8fa599792b6d52eadbb3921880a40872013d28";
            sha256 = "09gjb0c9ilnlc14ihpm93v6f7nz38fbn856djn3lj5vz62zjg3iw";
          };
        }
        {
          name = "exa-zsh";
          file = "exa-zsh.plugin.zsh";
          src = pkgs.fetchFromGitHub {
            owner = "MohamedElashri";
            repo = "exa-zsh";
            rev = "c2ae91faabe41b5e2fcd5d7b79bf20c46e6e034e";
            sha256 = "003zh8wmyqyg6jgm2bzx36agjnhrfad802i7wgb1w61hx1skykbj";
          };
        }
      ];
      initExtra = ''
        setopt auto_cd
        alias -g ...='../..'
        alias -g ....='../../..'
        alias -g .....='../../../..'
        alias -g ......='../../../../..'
        alias l="ls -al"
        export NIX_PATH="nixpkgs=$HOME/.nix-defexpr/channels/nixpkgs"
        # pure-prompt
        fpath+=(${pkgs.pure-prompt}/share/zsh/site-functions)
        autoload -U promptinit; promptinit -i
        zstyle :prompt:pure:git:action show yes
        zstyle :prompt:pure:git:arrow show yes
        zstyle :prompt:pure:git:stash show yes
        zstyle :prompt:pure:execution_time show yes
        zstyle :prompt:pure:prompt:success color yellow
        zstyle :prompt:pure:prompt:error color red
        zstyle :prompt:pure:path color cyan
        zstyle :prompt:pure:git.branch color yellow
        zstyle :prompt:pure:host color yellow
        PURE_PROMPT_SYMBOL='>'
        prompt pure
        # zsh-edit
        bindkey "^W" backward-kill-subword
      '';
      # profileExtra = ''
      #   if [ -z $DISPLAY ] && [ "$(tty)" = "/dev/tty1" ]; then
      #     exec sway
      #   fi
      # '';
    };
    z-lua = {
      enable = true;
      enableZshIntegration = true;
    };
  };
}
