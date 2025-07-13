{
  pkgs,
  ...
}:
{
  home.sessionPath = [ "$HOME/.local/bin" ];
  # TODO: https://github.com/nix-community/home-manager/issues/2064
  systemd.user.targets.tray = {
    Unit = {
      Description = "Home Manager System Tray";
      Requires = [ "graphical-session-pre.target" ];
    };
  };
  home.file.".config/nixpkgs/config.nix".source = pkgs.writeText "pub" ''
    {
      allowUnfree = true;
    }
  '';
  # programs.home-manager.enable = true;
  # https://github.com/nix-community/home-manager/issues/3211
  home.packages = [ pkgs.home-manager ];
}
