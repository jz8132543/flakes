{ config, pkgs, osConfig, ... }:

let
  cfg = config.home.global-persistence;
  sysCfg = osConfig.environment.global-persistence;
in
{
  programs = {
    fish = {
      enable = true;
      shellAliases = {
        deploy = "deploy --skip-checks";
        rebuild =
          "nixos-rebuild --use-remote-sudo -L --flake $HOME/source/flakes";
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

        # kubectl = "sudo k3s kubectl";
        scp = "time scp -Cpr -o Compression=yes";
      };
      shellInit = ''
        set fish_greeting
        function fish_user_key_bindings
          fish_vi_key_bindings
          bind f accept-autosuggestion
        end
        string replace -r '^' 'set -g ' < ${pkgs.fishPlugins.tide}/share/fish/vendor_functions.d/tide/configure/configs/lean.fish         | source
        string replace -r '^' 'set -g ' < ${pkgs.fishPlugins.tide}/share/fish/vendor_functions.d/tide/configure/configs/lean_16color.fish         | source
        set -g tide_prompt_add_newline_before false
        set fish_color_normal normal
        set fish_color_command blue
        set fish_color_quote yellow
        set fish_color_redirection cyan --bold
        set fish_color_end green
        set fish_color_error brred
        set fish_color_param cyan
        set fish_color_comment red
        set fish_color_match --background=brblue
        set fish_color_selection white --bold --background=brblack
        set fish_color_search_match bryellow --background=brblack
        set fish_color_history_current --bold
        set fish_color_operator brcyan
        set fish_color_escape brcyan
        set fish_color_cwd green
        set fish_color_cwd_root red
        set fish_color_valid_path --underline brgreen
        set fish_color_autosuggestion white
        set fish_color_user brgreen
        set fish_color_host normal
        set fish_color_cancel --reverse
        set fish_pager_color_prefix normal --bold --underline
        set fish_pager_color_progress brwhite --background=cyan
        set fish_pager_color_completion normal
        set fish_pager_color_description B3A06D --italics
        set fish_pager_color_selected_background --reverse
        set tide_character_icon '>'
      '';
      plugins = with pkgs.fishPlugins; [
        {
          name = "tide";
          src = tide.src;
        }
        {
          name = "autopair-fish";
          src = autopair-fish.src;
        }
      ];
    };
  };
  home.global-persistence.directories = [
    ".local/share/fish"
  ];
}
