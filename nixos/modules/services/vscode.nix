{
  config,
  pkgs,
  lib,
  nixosModules,
  ...
}:
let
  user = "tippy";
  workspace = "/home/tippy/source/flakes";
  vscodeWebPort = toString config.ports.code;
  vscodeWebStart = pkgs.writeShellScript "vscode-web-start" ''
    exec ${lib.getExe pkgs.openvscode-server} \
      --host 127.0.0.1 \
      --port ${vscodeWebPort} \
      --without-connection-token \
      --accept-server-license-terms \
      --github-auth "$GITHUB_TOKEN" \
      --server-data-dir /home/${user}/.vscode-server \
      --disable-telemetry
  '';
in
{
  # https://github.com/alienzj/dotfiles/blob/dev/modules/editors/vscode.nix
  imports = [ nixosModules.desktop.fonts ];

  systemd.services.vscode-web = {
    description = "VS Code Web";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      User = user;
      ExecStart = vscodeWebStart;
      Restart = "on-failure";
      WorkingDirectory = workspace;
    };
    environment = {
      LANG = "zh_CN.UTF-8";
    };
  };

  home-manager.users.${user}.home.file = {
    vscode = {
      target = ".vscode-server/data/User/settings.json";
      text = builtins.toJSON {
        "workbench.iconTheme" = "material-icon-theme";
        "workbench.colorTheme" = "Catppuccin Macchiato";
        "workbench.panel.defaultLocation" = "right";
        "workbench.startupEditor" = "none";
        "workbench.list.smoothScrolling" = true;

        "catppuccin.accentColor" = "mauve";

        "editor.fontFamily" =
          "\"JetBrains Mono\", \"Fira Code\", \"Fira Sans\", \"Material Design Icons\", \"Font Awesome 6 Free\", \"Symbols Nerd Font Mono\"";
        "editor.fontLigatures" = true;
        "window.zoomLevel" = 0.5;

        "[shellscript]"."editor.defaultFormatter" = "foxundermoon.shell-format";

        "files.trimTrailingWhitespace" = false;

        "terminal.integrated.fontFamily" = "JetBrains Mono";
        "terminal.integrated.defaultProfile.linux" = "zsh";
        "terminal.integrated.cursorBlinking" = true;

        "editor.minimap.enabled" = true;
        "editor.minimap.size" = "proportional";
        "editor.minimap.showSlider" = "mouseover";
        "editor.minimap.renderCharacters" = true;
        "editor.minimap.scale" = 1;
        "editor.minimap.maxColumn" = 120;

        "editor.overviewRulerBorder" = false;
        "editor.renderLineHighlight" = "all";
        "editor.inlineSuggest.enabled" = true;
        "editor.smoothScrolling" = true;
        "editor.suggestSelection" = "first";
        "editor.guides.indentation" = false;

        "[nix]"."editor.tabSize" = 2;
        "nix.enableLanguageServer" = true;
        "nix.serverPath" = "/run/current-system/sw/bin/nixd";
        "nix.serverSettings.nixd.formatting.command" = [ "nixfmt" ];
        "nix.serverSettings.nixd.nixpkgs.expr" =
          "import (builtins.getFlake \"/home/tippy/source/flakes\").inputs.nixpkgs {  }";
        "nix.serverSettings.nixd.options.nixos.expr" =
          "(builtins.getFlake \"/home/tippy/source/flakes\").nixosConfigurations.${config.networking.hostName}.options";
        "nix.serverSettings.nixd.options.home_manager.expr" =
          "(builtins.getFlake \"/home/tippy/source/flakes\").homeConfigurations.tippy.options";
        "nix.formatterPath" = "nixfmt";

        "window.restoreWindows" = "all";
        "window.menuBarVisibility" = "toggle";
        "window.titleBarStyle" = "custom";

        "security.workspace.trust.enabled" = false;

        "explorer.confirmDelete" = true;

        "breadcrumbs.enabled" = true;
        "update.mode" = "none";
        "extensions.autoCheckUpdates" = false;
        "github.copilot.nextEditSuggestions.enabled" = true;
      };
    };
  };

  systemd.services.vscode-web.serviceConfig.EnvironmentFile = [
    config.sops.templates."vscode-web-environment".path
  ];

  sops.templates."vscode-web-environment" = {
    content = ''
      GITHUB_TOKEN=${config.sops.placeholder."nix/github-token"}
    '';
  };

  services.traefik.proxies.code = {
    rule = "Host(`code.${config.networking.domain}`)";
    target = "http://localhost:${vscodeWebPort}";
    middlewares = [ "auth" ];
  };

  nix.settings.allowed-users = [ user ];
  environment.global-persistence.user = {
    directories = [
      ".local/share/direnv"
      ".vscode-server"
      ".config/Code"
    ];
  };
}
