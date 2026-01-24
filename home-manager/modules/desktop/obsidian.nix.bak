{
  pkgs,
  ...
}:
{
  home.packages = with pkgs; [
    # obsidian
  ];
  programs = {
    obsidian = {
      enable = true;
      vaults = {
        Privat = {
          enable = true;
          target = ".local/XDG/Documents/Notes/Privat";
        };
      };
    };
  };
  # home.file."Documents/Notes/Privat".source =
  #   config.lib.file.mkOutOfStoreSymlink "/var/lib/syncthing/data/Obsidian";
  home.global-persistence = {
    directories = [
    ];
  };
}
