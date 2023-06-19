{
  config,
  pkgs,
  ...
}: {
  programs = {
    clash-verge = {
      enable = true;
      autoStart = true;
      tunMode = true;
    };
  };
  environment.global-persistence.user = {
    directories = [
      ".config/clash-verge"
    ];
  };
}
