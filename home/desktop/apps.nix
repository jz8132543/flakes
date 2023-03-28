{ nixosConfig, config, lib, pkgs, ... }:

{
  home.packages = with pkgs; [
    tdesktop
    thunderbird
  ];
  home.persistence."/nix/persist/home/tippy" = {
    directories = [
      ".local/share/TelegramDesktop"
      ".thunderbird"
    ];
  };
}
