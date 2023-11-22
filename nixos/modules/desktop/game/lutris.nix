{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    lutris
    heroic
  ];
  environment.global-persistence.user.directories = [
    "Games"
    ".local/share/lutris"
    ".config/heroic"
  ];
}
