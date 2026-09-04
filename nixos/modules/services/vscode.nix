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
  extensionsGallery = builtins.toJSON {
    serviceUrl = "https://marketplace.visualstudio.com/_apis/public/gallery";
    cacheUrl = "https://vscode.blob.core.windows.net/gallery/index";
    itemUrl = "https://marketplace.visualstudio.com/items";
    resourceUrlTemplate = "https://{publisher}.vscode-unpkg.net/{publisher}/{name}/{version}/{path}";
    controlUrl = "";
  };
  vscodeWebStart = pkgs.writeShellScript "vscode-web-start" ''
    export EXTENSIONS_GALLERY='${extensionsGallery}'
    EXT_DIR="/home/${user}/.vscode-server/extensions"
    mkdir -p "$EXT_DIR"

    # Clean up deprecated / conflicting extensions if present
    for old_ext in \
      lyadhgod.antigravity-vscode \
      punal100.antigravity-copilot \
      GoogleCloudTools.cloudcode; do
      if ls "$EXT_DIR" 2>/dev/null | grep -qi "$old_ext"; then
        echo "Removing deprecated extension: $old_ext"
        ${lib.getExe pkgs.openvscode-server} \
          --server-data-dir /home/${user}/.vscode-server \
          --extensions-dir "$EXT_DIR" \
          --uninstall-extension "$old_ext" 2>/dev/null || true
        rm -rf "$EXT_DIR"/''${old_ext}* 2>/dev/null || true
      fi
    done

    # Pre-install official Antigravity, Copilot, Cline/Continue, Nix IDE, and Git workflow extensions
    for ext in \
      google.google-antigravity \
      GitHub.copilot \
      GitHub.copilot-chat \
      saoudrizwan.claude-dev \
      Continue.continue \
      mkhl.direnv \
      jnoortheen.nix-ide \
      mhutchie.git-graph \
      donjayamanne.githistory; do
      if ! ls "$EXT_DIR" 2>/dev/null | grep -qi "$ext"; then
        echo "Installing extension: $ext"
        ${lib.getExe pkgs.openvscode-server} \
          --server-data-dir /home/${user}/.vscode-server \
          --extensions-dir "$EXT_DIR" \
          --install-extension "$ext" --force || true
      fi
    done

    exec ${lib.getExe pkgs.openvscode-server} \
      --host 127.0.0.1 \
      --port ${vscodeWebPort} \
      --without-connection-token \
      --accept-server-license-terms \
      --github-auth "$GITHUB_TOKEN" \
      --server-data-dir /home/${user}/.vscode-server \
      --extensions-dir "$EXT_DIR" \
      --disable-telemetry \
      "${workspace}"
  '';
in
{
  # https://github.com/alienzj/dotfiles/blob/dev/modules/editors/vscode.nix
  imports = [ nixosModules.desktop.fonts ];

  systemd.services.vscode-web = {
    description = "VS Code Web";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    path = with pkgs; [
      nix
      direnv
      git
      nixd
      nixfmt
      coreutils
      curl
      bashInteractive
    ];
    serviceConfig = {
      User = user;
      ExecStart = vscodeWebStart;
      Restart = "on-failure";
      WorkingDirectory = workspace;
    };
    environment = {
      LANG = "zh_CN.UTF-8";
      EXTENSIONS_GALLERY = extensionsGallery;
    };
  };

  home-manager.users.${user}.home.file = {
    vscode = {
      target = ".vscode-server/data/User/settings.json";
      text = builtins.toJSON {
        "workbench.iconTheme" = "material-icon-theme";
        "workbench.colorTheme" = "Default Dark Modern";
        "workbench.panel.defaultLocation" = "right";
        "workbench.startupEditor" = "none";
        "workbench.list.smoothScrolling" = true;

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

        # Web & PWA Keyboard shortcut optimization
        "keyboard.dispatch" = "keyCode";

        "[nix]"."editor.tabSize" = 2;
        "nix.enableLanguageServer" = true;
        "nix.serverPath" = "${lib.getExe pkgs.nixd}";
        "nix.serverSettings.nixd.formatting.command" = [ "${lib.getExe pkgs.nixfmt}" ];
        "nix.serverSettings.nixd.nixpkgs.expr" =
          "import (builtins.getFlake \"/home/tippy/source/flakes\").inputs.nixpkgs {  }";
        "nix.serverSettings.nixd.options.nixos.expr" =
          "(builtins.getFlake \"/home/tippy/source/flakes\").nixosConfigurations.${config.networking.hostName}.options";
        "nix.serverSettings.nixd.options.home_manager.expr" =
          "(builtins.getFlake \"/home/tippy/source/flakes\").homeConfigurations.tippy.options";
        "nix.formatterPath" = "${lib.getExe pkgs.nixfmt}";

        "window.restoreWindows" = "all";
        "window.menuBarVisibility" = "toggle";
        "window.titleBarStyle" = "custom";

        "security.workspace.trust.enabled" = false;

        "explorer.confirmDelete" = true;

        "breadcrumbs.enabled" = true;
        "update.mode" = "none";
        "extensions.autoCheckUpdates" = false;
        "github.copilot.nextEditSuggestions.enabled" = true;
        "github.copilot.enable" = {
          "*" = true;
        };
        "github.copilot.chat.localeOverride" = "zh-CN";
        "chat.commandCenter.enabled" = true;

        # Direnv
        "direnv.restart.automatic" = true;
        "direnv.status.enabled" = true;
        "direnv.path.executable" = "${lib.getExe pkgs.direnv}";

        # Git & Git Graph
        "git.autofetch" = true;
        "git.confirmSync" = false;
        "git-graph.repository.showCommitsOnlyReferencedByTagsOrBranches" = false;
        "git-graph.commitDetailsView.location" = "Docked to Bottom";
      };
    };
  };

  systemd.services.vscode-web.serviceConfig.EnvironmentFile = [
    config.sops.templates."vscode-web-environment".path
  ];

  sops.templates."vscode-web-environment" = {
    content = ''
      GITHUB_TOKEN=${config.sops.placeholder."github-token"}
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
      # VS Code / OpenVSCode Server store workspace trust and machine identity
      # state under data/, so keep that tree persistent as well.
      ".vscode-server/data"
      ".continue"
    ];
  };
}
