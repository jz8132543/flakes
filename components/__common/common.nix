{ ... }:
{
  time.timeZone = "Asia/Shanghai";

  users.mutableUsers = true;

  documentation.nixos.enable = false;
  programs.command-not-found.enable = false;

  system.stateVersion = "23.05";
}
