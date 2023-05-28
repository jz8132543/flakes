{...}: {
  time.timeZone = "Asia/Shanghai";

  users.mutableUsers = true;

  documentation = {
    nixos.enable = false;
    man.generateCaches = false;
  };
  programs.command-not-found.enable = false;
}
