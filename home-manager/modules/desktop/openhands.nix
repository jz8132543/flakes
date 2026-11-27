{
  pkgs,
  ...
}:
let
  launcher = pkgs.writeShellScriptBin "openhands" ''
    exec ${pkgs.xdg-utils}/bin/xdg-open https://openhands.dora.im/canvas/ "$@"
  '';
  desktop = pkgs.makeDesktopItem {
    name = "agent-canvas";
    desktopName = "OpenHands Workspace";
    genericName = "Remote Autonomous Agent Workspace";
    comment = "Open the Keycloak-protected OpenHands workspace in a browser";
    exec = "${launcher}/bin/openhands";
    icon = "agent-canvas";
    terminal = false;
    categories = [ "Development" ];
  };
in
{
  home.packages = [
    pkgs.openhands-desktop
    launcher
  ];
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
