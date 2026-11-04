{
  lib,
  osConfig ? { },
  ...
}:
let
  systemConfig = if osConfig == null then { } else osConfig;
  minimal = systemConfig.environment.minimal or false;
in
{

  home.sessionVariables = lib.mkIf (!minimal) {
    MANPAGER = "nvim -c 'Man!' -o -";
  };

  xdg.configFile = {
    "ripgrep_ignore".text = ''
      .git/
      yarn.lock
      package-lock.json
      packer_compiled.lua
      .DS_Store
      .netrwhist
      dist/
      node_modules/
      **/node_modules/
      wget-log
      wget-log.*
      /vendor
    '';
  };
  home.global-persistence = {
    directories = [
      ".cargo"
      ".local/share/nvim"
      # ".config/nvim"
      # ".config/coc"
    ];
  };
}
