{
  inputs,
  lib,
  self,
  ...
}:
let
  pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
  bitwig = self.packages.x86_64-linux.bitwig-studio-patched;
  stateDirectory = "/mnt/games/Audio/.launcher-state";
  cacheDirectory = "/mnt/games/Audio/.launcher-cache";
  home = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      ../home-manager/modules/desktop/wine-audio/launchers.nix
      ../home-manager/modules/desktop/wine-audio/low-latency.nix
      ({ config, ... }: {
        home.username = "tippy";
        home.homeDirectory = "/home/tippy";
        home.stateVersion = lib.importJSON ../lib/state-version.json;
        programs.wineAudio.enable = true;
        programs.wineAudio.lowLatency.enable = true;
        xdg.desktopEntries."com.bitwig.BitwigStudio" = {
          name = "Bitwig Studio";
          genericName = "Digital Audio Workstation";
          comment = "Modern music production and performance";
          exec = lib.getExe bitwig;
          icon = "${bitwig}/share/icons/hicolor/scalable/apps/com.bitwig.BitwigStudio.svg";
          terminal = false;
          startupNotify = true;
          categories = [
            "AudioVideo"
            "Music"
            "Audio"
            "Sequencer"
            "Midi"
            "Mixer"
            "Player"
            "Recorder"
          ];
          settings = {
            Keywords = "daw;bitwig;audio;midi;";
            StartupWMClass = "com.bitwig.BitwigStudio";
          };
        };
        xdg.dataFile."applications/com.bitwig.BitwigStudio.desktop".source = "${
          lib.findFirst (
            package: package.name == "com.bitwig.BitwigStudio.desktop"
          ) (throw "Missing Home Manager Bitwig desktop entry") config.home.packages
        }/share/applications/com.bitwig.BitwigStudio.desktop";
        xdg.enable = false;
        xdg.stateHome = stateDirectory;
        xdg.cacheHome = cacheDirectory;
        xdg.mime.enable = false;
        nix.enable = false;
        nix.assumeXdg = true;
        systemd.user.enable = false;
        programs.man.enable = false;
        home.file."${cacheDirectory}/.keep".enable = false;
        home.file."${stateDirectory}/.keep".enable = false;
      })
    ];
  };
  installer = pkgs.writeShellApplication {
    name = "install-wine-audio-launchers";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.nix
    ];
    text = ''
      if [[ "$USER" != tippy || "$HOME" != /home/tippy || "$UID" != "$(id -u tippy)" ]]; then
        printf 'Run this launcher configuration as tippy with the real HOME.\n' >&2
        exit 1
      fi
      if [[ ! -d /mnt/games/Audio ]]; then
        printf 'The mounted Audio directory is unavailable.\n' >&2
        exit 1
      fi
      for directory in \
        ${lib.escapeShellArg stateDirectory} \
        ${lib.escapeShellArg cacheDirectory} \
        ${lib.escapeShellArg "${stateDirectory}/nix"} \
        ${lib.escapeShellArg "${stateDirectory}/nix/profiles"} \
        ${lib.escapeShellArg "${stateDirectory}/nix-global"}; do
        if [[ -L "$directory" || ( -e "$directory" && ( ! -d "$directory" || ! -O "$directory" ) ) ]]; then
          printf 'Refusing non-private launcher state: %s\n' "$directory" >&2
          exit 1
        fi
        if [[ ! -d "$directory" ]]; then
          mkdir -m 0700 -- "$directory"
        fi
      done
      unset oldGenPath NIX_STATE_HOME NIX_PROFILE
      export XDG_STATE_HOME=${lib.escapeShellArg stateDirectory}
      export XDG_CACHE_HOME=${lib.escapeShellArg cacheDirectory}
      export NIX_STATE_DIR=${lib.escapeShellArg "${stateDirectory}/nix-global"}
      export NIX_REMOTE=unix:///nix/var/nix/daemon-socket/socket
      export NIX_CONFIG="''${NIX_CONFIG-}"$'\nuse-xdg-base-directories = true'
      exec ${home.activationPackage}/activate --driver-version 0 "$@"
    '';
  };
in
{
  _module.args.wineAudioHome = home;
  # Do not expose this as a normal HM switch target: its runtime state is private.
  flake.packages.x86_64-linux.wine-audio-launchers = installer;
  flake.apps.x86_64-linux.wine-audio-launchers = {
    type = "app";
    program = "${installer}/bin/install-wine-audio-launchers";
  };
}
