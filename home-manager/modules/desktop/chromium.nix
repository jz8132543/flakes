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
  home.global-persistence = {
    directories = [
      ".config/chromium"
    ];
  };
}
