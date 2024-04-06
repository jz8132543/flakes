{pkgs, ...}: {
  services.gpg-agent = {
    enable = true;
    # pinentryPackage = [pkgs.curses];
  };
  programs.gpg = {enable = true;};
  home.global-persistence = {
    directories = [
      ".gnupg"
    ];
  };
}
