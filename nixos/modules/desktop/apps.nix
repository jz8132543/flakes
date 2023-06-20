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
  # environment.systemPackages = with pkgs; [
  #   clash-meta
  # ];
  environment.global-persistence.user = {
    directories = [
      ".config/clash-verge"
    ];
  };
}
