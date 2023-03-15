{ nixosConfig, config, lib, pkgs, ... }:

{
  home.persistence."/nix/persist/home/tippy" = {
    directories = [
      ".config/fcitx5"
      ".local/share/fcitx5/rime"
    ];
  };
}
