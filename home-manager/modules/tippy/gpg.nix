{pkgs, ...}: {
  services.gpg-agent = {
    enable = true;
    pinentryFlavor = "curses";
  };
  programs.gpg = {enable = true;};
  home.global-persistence = {
    directories = [
      ".gnupg"
    ];
  };
}
