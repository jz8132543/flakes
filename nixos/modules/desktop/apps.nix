{
  config,
  pkgs,
  nixosModules,
  ...
}:
{
  imports = [
    nixosModules.services.aria2
    nixosModules.services.podman
    nixosModules.services.easytier-web
    # nixosModules.services.ntopng
  ];
  programs.k3b.enable = true;
  services.udev.extraRules = ''
    SUBSYSTEM=="block", KERNEL=="sr[0-9]*", GROUP="cdrom", MODE="0660"
  '';
  environment.systemPackages = with pkgs; [
    brasero # Added GNOME native burning tool
    qrcp
    android-tools
    wpsoffice-cn
    dvdplusrwtools
    # mihomo-party
  ];
  environment.shellAliases = {
    qrcp = "qrcp --port ${toString config.ports.qrcp}";
  };
  networking.firewall.allowedTCPPorts = [
    config.ports.qrcp
  ];

  programs.chromium = {
    enable = true;
    extensions = [
      # CookieCloud - 同步PT站点Cookie
      "ffjiejobkoibkjlhjnlgmcnnigeelbdl"
      # Bitwarden
      "nngceckbapebfimnlniiiahkandclblb"
      # uBlock Origin
      "cjpalhdlnbpafiamejdnhcphjbkeiagm"
      # PT-Depiler - PT站点效率工具
      "gfkgnjfipffpfdnfmcpaoajkidapcplc"
      # Aria2 Explorer
      "mpkodccbngfoacfalldjimigihfbocjn"
      # Linkwarden - Bookmark Manager
      "efpglpohdfnodejoimcladancmgeibao"
    ];
    extraOpts = {
      "3rdparty" = {
        "extensions" = {
          "ffjiejobkoibkjlhjnlgmcnnigeelbdl" = {
            "host" = "https://cookiecloud.${config.networking.domain or "dora.im"}";
          };
          "efpglpohdfnodejoimcladancmgeibao" = {
            "host" = "https://link.${config.networking.domain or "dora.im"}";
          };
        };
      };
    };
  };
}
