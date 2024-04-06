{pkgs, ...}: {
  programs.chromium = {
    enable = true;
    package = pkgs.chromium;
    extensions = [
      "padekgcemlokbadohgkifijomclgjgif" # SwitchyOmega
      "nngceckbapebfimnlniiiahkandclblb" # Bitwarden
      "kgljlkdpcelbbmdfilomhgjaaefofkfh" # DeepL
      "cjpalhdlnbpafiamejdnhcphjbkeiagm" # uBlock Origin
      # "dbepggeogbaibhgnhhndojpepiihcmeb" # Vimium
    ];
    # https://wiki.archlinux.org/title/Chromium#Native_Wayland_support
    commandLineArgs = [
      "--ozone-platform-hint=auto"
      "--ozone-platform=wayland"
      # make it use GTK_IM_MODULE if it runs with Gtk4, so fcitx5 can work with it.
      # (only supported by chromium/chrome at this time, not electron)
      "--gtk-version=4"
      # make it use text-input-v1, which works for kwin 5.27 and weston
      # "--enable-wayland-ime"

      # enable hardware acceleration - vulkan api
      # "--enable-features=Vulkan"
    ];
  };
  # programs.chromium = {
  #   enable = true;
  #   extensions = [
  #     "padekgcemlokbadohgkifijomclgjgif" # SwitchyOmega
  #     "nngceckbapebfimnlniiiahkandclblb" # Bitwarden
  #     "kgljlkdpcelbbmdfilomhgjaaefofkfh" # DeepL
  #     "cjpalhdlnbpafiamejdnhcphjbkeiagm" # uBlock Origin
  #     # "dbepggeogbaibhgnhhndojpepiihcmeb" # Vimium
  #   ];
  # };
  home.global-persistence = {
    directories = [
      ".config/chromium"
    ];
  };
}
