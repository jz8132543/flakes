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
  extensionsEnv = pkgs.buildEnv {
    name = "vscode-extensions-env";
    paths = with pkgs.vscode-extensions; [
      usernamehw.errorlens
      timonwong.shellcheck
      redhat.vscode-yaml
      tamasfe.even-better-toml
      yzhang.markdown-all-in-one
      bierner.markdown-mermaid
      eamodio.gitlens
      pkief.material-icon-theme
      foxundermoon.shell-format
      mkhl.direnv
      jnoortheen.nix-ide
      mhutchie.git-graph
      donjayamanne.githistory
      ms-ceintl.vscode-language-pack-zh-hans
    ];
  };
  vscodeSettings = {
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
    "nix.serverPath" = "nixd";
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

    # Direnv
    "direnv.restart.automatic" = true;
    "direnv.status.enabled" = true;
    "direnv.path.executable" = "direnv";

    # Git & Git Graph
    "git.autofetch" = true;
    "git.confirmSync" = false;
    "git-graph.repository.showCommitsOnlyReferencedByTagsOrBranches" = false;
    "git-graph.commitDetailsView.location" = "Docked to Bottom";
  };
  defaultSettingsFile = pkgs.writeText "vscode-default-settings.json" (
    builtins.toJSON vscodeSettings
  );
  vscodeWebStart = pkgs.writeShellScript "vscode-web-start" ''
            export EXTENSIONS_GALLERY='${extensionsGallery}'
            EXT_DIR="/home/${user}/.vscode-server/extensions"
            mkdir -p "$EXT_DIR"

            # Link official NixOS extensions from extensionsEnv
            for ext_path in ${extensionsEnv}/share/vscode/extensions/*; do
              ext_name=$(basename "$ext_path")
              if [ ! -d "$EXT_DIR/$ext_name" ] || [ -L "$EXT_DIR/$ext_name" ]; then
                ln -sfn "$ext_path" "$EXT_DIR/$ext_name"
              fi
            done

            # Pre-install marketplace extensions if needed
            for ext in kilocode.kilo-code; do
              if ! ls "$EXT_DIR" 2>/dev/null | grep -qi "$ext"; then
                echo "Installing extension: $ext"
                ${lib.getExe pkgs.openvscode-server} \
                  --server-data-dir /home/${user}/.vscode-server \
                  --extensions-dir "$EXT_DIR" \
                  --install-extension "$ext" --force || true
              fi
            done

            # Initialize and merge default settings into mutable User settings
            SETTINGS_DIR="/home/${user}/.vscode-server/data/User"
            mkdir -p "$SETTINGS_DIR" "/home/${user}/.vscode-server/data/Machine"

            if [ -L "$SETTINGS_DIR/settings.json" ]; then
              rm -f "$SETTINGS_DIR/settings.json"
            fi
            if [ -L "/home/${user}/.vscode-server/data/Machine/settings.json" ]; then
              rm -f "/home/${user}/.vscode-server/data/Machine/settings.json"
            fi

            if [ ! -f "$SETTINGS_DIR/settings.json" ]; then
              cp "${defaultSettingsFile}" "$SETTINGS_DIR/settings.json"
              chmod 0644 "$SETTINGS_DIR/settings.json"
            else
              ${lib.getExe pkgs.jq} -s '.[0] * .[1]' "${defaultSettingsFile}" "$SETTINGS_DIR/settings.json" > "$SETTINGS_DIR/settings.json.tmp" && \
              mv -f "$SETTINGS_DIR/settings.json.tmp" "$SETTINGS_DIR/settings.json"
              chmod 0644 "$SETTINGS_DIR/settings.json"
            fi

            # Pre-configure ContextForge Virtual Gateway for Kilo Code & MCP
            MCP_SETTINGS_DIR="/home/${user}/.vscode-server/data/User/globalStorage/kilocode.kilo-code/settings"
            mkdir -p "$MCP_SETTINGS_DIR"
            cat <<EOF > "$MCP_SETTINGS_DIR/mcpSettings.json"
    {
      "mcpServers": {
        "contextforge-dev": {
          "type": "sse",
          "url": "http://127.0.0.1:${toString config.ports.mcp-contextforge-api}/api/gateways/ide/sse",
          "headers": {
            "Authorization": "Bearer $OPENAI_API_KEY"
          }
        }
      }
    }
    EOF
            chmod 0600 "$MCP_SETTINGS_DIR/mcpSettings.json"

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
    after = [
      "network.target"
      "podman-cpa.service"
    ];
    wants = [
      "podman-cpa.service"
    ];
    path = with pkgs; [
      nix
      direnv
      git
      nixd
      nixfmt
      coreutils
      curl
      jq
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

  sops.secrets."openai_api_key" = { };

  systemd.services.vscode-web.serviceConfig.EnvironmentFile = [
    config.sops.templates."vscode-web-environment".path
  ];

  sops.templates."vscode-web-environment" = {
    content = ''
      GITHUB_TOKEN=${config.sops.placeholder."github-token"}
      CPA_API_KEY=${config.sops.placeholder."openai_api_key"}
      OPENAI_API_KEY=${config.sops.placeholder."openai_api_key"}
      OPENAI_BASE_URL=https://${config.services.cpa.domain}/v1
      ANTHROPIC_API_KEY=${config.sops.placeholder."openai_api_key"}
      ANTHROPIC_BASE_URL=https://${config.services.cpa.domain}
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
    ];
  };
}
