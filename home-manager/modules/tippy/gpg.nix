{
  pkgs,
  ...
}:
{
  services.gpg-agent = {
    enable = true;
    pinentryPackage = pkgs.pinentry-curses;
    # pinentryPackage = lib.mkForce pkgs.pinentry-qt;
  };
  programs.gpg = {
    enable = true;
  };
  home.global-persistence = {
    directories = [
      ".gnupg"
    ];
  };
}
