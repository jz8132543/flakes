{
  pkgs,
  config,
  ...
}:
{
  programs.zsh = {
    enable = true;
  };

  programs.fish = {
    enable = true;
    useBabelfish = true;
  };
  environment.systemPackages =
    (with pkgs.fishPlugins; [
      foreign-env
      done
      autopair-fish
    ])
    ++ (with config.nur.repos.linyinfeng.fishPlugins; [
      git
      bang-bang
      replay
    ])
    ++ (with pkgs; [
      libnotify # for done notification
      comma
    ]);

  environment.global-persistence.user.directories = [
    ".local/share/fish"
  ];
}
