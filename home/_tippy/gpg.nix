{ pkgs, ... }:
{
  services.gpg-agent = {
    enable = true;
    pinentryFlavor = "curses";
  };
  programs.gpg = { enable = true; };
  home.persistence."/nix/persist/home/tippy" = {
    directories = [
      ".gnupg"
    ];
  };
}
