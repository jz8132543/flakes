{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  onboardingState = pkgs.writeText "vicinae-onboarding-complete.json" ''
    {"version":1,"completedAt":""}
  '';
  sandstoneTheme = variant: core: {
    meta = {
      name = "Sandstone";
      description = "Warm sandstone colors for ${variant} mode";
      inherit variant;
      inherits = "vicinae-${variant}";
    };
    colors = {
      inherit core;
      accents = {
        orange = if variant == "dark" then "#d79a55" else "#a85f24";
        yellow = if variant == "dark" then "#e4c27a" else "#8b642d";
      };
    };
  };
in
{
  config = lib.mkIf osConfig.desktop.noctalia.enable {
    # The pinned Home Manager exposes its native daemon under programs.vicinae.
    programs.vicinae = {
      enable = true;
      mutableSettings = true;
      systemd = {
        enable = true;
        target = config.window-manager.sessionTarget;
      };
      settings = {
        theme = {
          light = {
            name = "sandstone-light";
            icon_theme = "default";
          };
          dark = {
            name = "sandstone-dark";
            icon_theme = "default";
          };
        };
        launcher_window = {
          opacity = 0.88;
          material = "none";
          rounding = 12;
          client_side_decorations = {
            border_width = 0;
            shadow_size = 18;
          };
        };
      };
      themes = {
        sandstone-dark = sandstoneTheme "dark" {
          accent = "#c9a76e";
          accent_foreground = "#171511";
          background = "#171511";
          foreground = "#e9e1d2";
          secondary_background = "#211e18";
          border = "#3b3428";
        };
        sandstone-light = sandstoneTheme "light" {
          accent = "#8b642d";
          accent_foreground = "#fffaf0";
          background = "#fffaf0";
          foreground = "#29251e";
          secondary_background = "#f2ecdf";
          border = "#d6c9b3";
        };
      };
    };
    # Vicinae only records onboarding completion when its welcome window's
    # finish action is clicked. Treat a missing record as dismissed, without
    # overwriting state from users who completed onboarding themselves.
    home.activation.vicinaeOnboarding = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      state_dir=${lib.escapeShellArg "${config.xdg.stateHome}/vicinae"}
      state_file="$state_dir/onboarding.json"
      if [ ! -e "$state_file" ]; then
        run mkdir -p "$state_dir"
        run ${pkgs.coreutils}/bin/install -m 0600 ${onboardingState} "$state_file"
      fi
    '';
    # NVIDIA's Wayland EGL path can block the first Qt Quick frame here.
    # Vulkan keeps the native GPU renderer without changing other applications.
    systemd.user.services.vicinae.Service.Environment =
      lib.mkIf (lib.elem "nvidia" osConfig.services.xserver.videoDrivers)
        [ "QSG_RHI_BACKEND=vulkan" ];
  };
}
