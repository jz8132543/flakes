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
      "cjpalhdlnbpafiamejdnhcphjbkeiagm" # uBlock Origin
    ];
  };
  home.persistence."/nix/persist/home/tippy" = {
    directories = [
      ".config/chromium"
    ];
  };
}
