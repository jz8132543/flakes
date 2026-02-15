{ inputs, ... }:
{
  imports = [ inputs.aagl.nixosModules.default ];

  # Enable the launcher for Genshin Impact
  programs.anime-game-launcher.enable = true;

  # Optionally enable other launchers if needed
  # programs.honkers-railway-launcher.enable = true;
  # programs.honkers-launcher.enable = true;

  environment.global-persistence.user.directories = [
    ".local/share/anime-game-launcher"
    ".config/anime-game-launcher"
  ];
}
