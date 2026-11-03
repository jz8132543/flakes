{
  config,
  lib,
  pkgs,
  ...
}:
let
  launcher = pkgs.writeShellScriptBin "openhands" ''
    export OPENHANDS_SERVER_URL=https://openhands.dora.im
    export OPENHANDS_PASSWORD_FILE=${lib.escapeShellArg config.sops.secrets.password.path}
    exec ${pkgs.openhands-desktop}/bin/openhands-desktop "$@"
  '';
  desktop = pkgs.makeDesktopItem {
    name = "agent-canvas";
    desktopName = "OpenHands Agent Canvas";
    genericName = "Remote AI Coding Workspace";
    comment = "Connect to the authenticated OpenHands server";
    exec = "${launcher}/bin/openhands";
    icon = "agent-canvas";
    terminal = false;
    categories = [ "Development" ];
    startupWMClass = "OpenHands Agent Canvas";
  };
in
{
  home.packages = [
    pkgs.openhands-desktop
    launcher
  ];
  sops.secrets.password = { };

  # The user-level entry overrides the package's original local-stack launcher.
  xdg.dataFile."applications/agent-canvas.desktop".source =
    "${desktop}/share/applications/agent-canvas.desktop";

  # Keep a browser fallback without putting credentials in a URL or argv.
  xdg.desktopEntries.openhands-server = {
    name = "OpenHands (Server)";
    genericName = "Remote AI Coding Workspace";
    comment = "Open the authenticated OpenHands server in the default browser";
    exec = "${pkgs.xdg-utils}/bin/xdg-open https://openhands.dora.im/canvas/";
    icon = "agent-canvas";
    terminal = false;
    categories = [ "Development" ];
  };

  home.global-persistence.directories = [
    ".openhands"
    ".config/OpenHands Agent Canvas"
  ];
}
