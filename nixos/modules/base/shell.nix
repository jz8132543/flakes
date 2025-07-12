{
  pkgs,
  lib,
  ...
}:
{
  programs.zsh = {
    enable = true;
  };

  programs.fish = {
    enable = true;
    # useBabelfish = true;
  };
  environment.systemPackages =
    (with pkgs.fishPlugins; [
      # keep-sorted start
      # https://github.com/acomagu/fish-async-prompt/issues/74
      # async-prompt
      autopair-fish
      done
      fish-you-should-use
      foreign-env
      forgit
      puffer
      # keep-sorted end
    ])
    ++ (with pkgs.nur.repos.linyinfeng.fishPlugins; [
      replay
    ])
    ++ (with pkgs; [
      libnotify # for done notification
    ])
    ++ lib.optional (pkgs ? comma-with-db) pkgs.comma-with-db;

  environment.global-persistence.user.directories = [
    ".local/share/fish"
  ];
}
