{
  nixosConfig,
  config,
  lib,
  pkgs,
  ...
}: {
  programs.chromium = {
    enable = true;
    extensions = [
      "padekgcemlokbadohgkifijomclgjgif" # SwitchyOmega
      "nngceckbapebfimnlniiiahkandclblb" # Bitwarden
      "kgljlkdpcelbbmdfilomhgjaaefofkfh" # DeepL
    ];
  };
  home.persistence."/nix/persist/home/tippy" = {
    directories = [
      ".config/chromium"
    ];
  };
}
