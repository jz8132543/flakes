{ nixosConfig, config, lib, pkgs, ...  }:

lib.mkIf nixosConfig.environment.graphical.enable {
  programs.chromium = {
    enable = true;
    extensions = [
      "padekgcemlokbadohgkifijomclgjgif" # SwitchyOmega
      "nngceckbapebfimnlniiiahkandclblb" # Bitwarden
      "kgljlkdpcelbbmdfilomhgjaaefofkfh" # DeepL
    ];
  };
}
