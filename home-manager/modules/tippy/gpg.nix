{pkgs, ...}: {
  services.gpg-agent = {
    enable = true;
    pinentryPackage = pkgs.pinentry-curses;
  };
  programs.gpg = {enable = true;};
  home.global-persistence = {
    directories = [
      ".gnupg"
    ];
  };
}
