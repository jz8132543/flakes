{ config, pkgs, ... }:

{
  services.gpg-agent = {
    enable = true;
    pinentryFlavor = "curses";
  };
  programs.gpg = { enable = true; };
  environment.global-persistence.user.directories = [
    ".gnupg"
  ];
}

