{ pkgs, ... }:
let
  tide = pkgs.fishPlugins.tide.src;
in
{
  programs.fish = {
    enable = true;
    plugins = [{
      name = "tide";
      src = tide;
    }];

    shellInit = ''
      set fish_greeting
      function fish_user_key_bindings
        fish_vi_key_bindings
        bind f accept-autosuggestion
      end
      string replace -r '^' 'set -g ' < ${tide}/functions/tide/configure/configs/lean.fish         | source
      string replace -r '^' 'set -g ' < ${tide}/functions/tide/configure/configs/lean_16color.fish | source
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
      set fish_color_valid_path --underline
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
      scp = "time scp -Cpr -o Compression=yes";
    };
  };
  home.persistence."/nix/persist/home/tippy" = {
    directories = [
      ".local/share/fish"
    ];
  };
}
