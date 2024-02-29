{...}: {
  programs.chromium = {
    enable = true;
    extensions = [
      "padekgcemlokbadohgkifijomclgjgif" # SwitchyOmega
      "nngceckbapebfimnlniiiahkandclblb" # Bitwarden
      "kgljlkdpcelbbmdfilomhgjaaefofkfh" # DeepL
      "cjpalhdlnbpafiamejdnhcphjbkeiagm" # uBlock Origin
      # "dbepggeogbaibhgnhhndojpepiihcmeb" # Vimium
    ];
  };
  # https://github.com/linyinfeng/dotfiles/blob/main/home-manager/profiles/chromium/default.nix
  home.sessionVariables = {
    GOOGLE_DEFAULT_CLIENT_ID = "77185425430.apps.googleusercontent.com";
    GOOGLE_DEFAULT_CLIENT_SECRET = "OTJgUOQcT7lO7GsGZq2G4IlT";
  };
  home.global-persistence = {
    directories = [
      ".config/chromium"
    ];
  };
}
