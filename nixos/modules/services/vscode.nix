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

        # Pre-install AI Agent (Roo Code, Continue), Nix IDE, and Git workflow extensions
        for ext in \
          RooVeterinaryInc.roo-cline \
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

        # Dynamically fetch available models from CPA to configure Continue without hardcoding in Nix
        if [ -n "''${OPENAI_BASE_URL:-}" ] && [ -n "''${OPENAI_API_KEY:-}" ]; then
          echo "Fetching available models from $OPENAI_BASE_URL/models..."
          CPA_MODELS=""
          for retry in 1 2 3; do
            CPA_MODELS=$(${lib.getExe pkgs.curl} -sf --max-time 5 \
              -H "Authorization: Bearer $OPENAI_API_KEY" \
              "$OPENAI_BASE_URL/models" 2>/dev/null || true)
            if [ -n "$CPA_MODELS" ] && echo "$CPA_MODELS" | ${lib.getExe pkgs.jq} -e '.data | length > 0' >/dev/null 2>&1; then
              break
            fi
            sleep 1
          done

          if [ -n "$CPA_MODELS" ] && echo "$CPA_MODELS" | ${lib.getExe pkgs.jq} -e '.data | length > 0' >/dev/null 2>&1; then
            echo "Dynamically updating Continue configuration from CPA models..."
            mkdir -p "/home/${user}/.continue"
            rm -f "/home/${user}/.continue/config.ts"
            echo "$CPA_MODELS" | ${lib.getExe pkgs.jq} --arg base "$OPENAI_BASE_URL" --arg key "$OPENAI_API_KEY" '
              .data | map(.id) as $ids |
              ($ids | map(select(test("flash.*low|flash.*lite|flash"))) | first // $ids[0]) as $tab_model |
              {
                name: "CPA",
                version: "1.0.0",
                schema: "v1",
                models: (
                  ($ids | map({
                    name: (
                      if test("-thinking$") then (. | sub("-thinking$"; "") + " (Thinking)")
                      elif test("-high$") then (. | sub("-high$"; "") + " (High Thinking)")
                      elif test("-medium$") then (. | sub("-medium$"; "") + " (Medium Thinking)")
                      elif test("-low$") then (. | sub("-low$"; "") + " (Low Thinking)")
                      else . end
                    ),
                    title: (
                      if test("-thinking$") then (. | sub("-thinking$"; "") + " (Thinking)")
                      elif test("-high$") then (. | sub("-high$"; "") + " (High Thinking)")
                      elif test("-medium$") then (. | sub("-medium$"; "") + " (Medium Thinking)")
                      elif test("-low$") then (. | sub("-low$"; "") + " (Low Thinking)")
                      else . end
                    ),
                    provider: "openai",
                    model: .,
                    apiBase: $base,
                    apiKey: $key,
                    roles: ["chat", "edit", "apply"]
                  })) +
                  (if $tab_model then [{
                    name: ($tab_model + " (Autocomplete)"),
                    title: ($tab_model + " (Autocomplete)"),
                    provider: "openai",
                    model: $tab_model,
                    apiBase: $base,
                    apiKey: $key,
                    roles: ["autocomplete"]
                  }] else [] end)
                ),
                tabAutocompleteModel: (if $tab_model then {
                  title: ($tab_model + " (Autocomplete)"),
                  name: ($tab_model + " (Autocomplete)"),
                  provider: "openai",
                  model: $tab_model,
                  apiBase: $base,
                  apiKey: $key
                } else null end),
                allowAnonymousTelemetry: false
              }
            ' > "/home/${user}/.continue/config.yaml"
            cp -f "/home/${user}/.continue/config.yaml" "/home/${user}/.continue/config.json"
            chmod 0600 "/home/${user}/.continue/config.yaml" "/home/${user}/.continue/config.json"

            echo "Dynamically updating Roo Code configuration from CPA models..."
            mkdir -p "/home/${user}/.vscode-server/data/User" "/home/${user}/.vscode-server/data/Machine"
            echo "$CPA_MODELS" | ${lib.getExe pkgs.jq} --arg base "$OPENAI_BASE_URL" --arg key "$OPENAI_API_KEY" '
              .data | map(.id) as $ids |
              ($ids | map(select(test("claude-3-7-sonnet.*thinking|claude-3-7-sonnet|claude"))) | first // $ids[0]) as $default_model |
              {
                providerProfiles: {
                  currentApiConfigName: "cpa",
                  apiConfigs: (
                    {
                      "cpa": {
                        id: "cpa",
                        apiProvider: "openai",
                        openAiBaseUrl: $base,
                        openAiApiKey: $key,
                        openAiModelId: $default_model
                      }
                    } +
                    ($ids | map({
                      key: ("cpa-" + .),
                      value: {
                        id: ("cpa-" + .),
                        apiProvider: "openai",
                        openAiBaseUrl: $base,
                        openAiApiKey: $key,
                        openAiModelId: .
                      }
                    }) | from_entries)
                  )
                }
              }
            ' > "/home/${user}/.vscode-server/data/User/roo-settings.json"
            chmod 0600 "/home/${user}/.vscode-server/data/User/roo-settings.json"

            # Ensure Machine settings and workspace settings have roo-cline.autoImportSettingsPath
            if [ -f "/home/${user}/.vscode-server/data/User/settings.json" ]; then
              cp -f "/home/${user}/.vscode-server/data/User/settings.json" "/home/${user}/.vscode-server/data/Machine/settings.json" || true
            fi
          else
            if [ ! -f "/home/${user}/.continue/config.yaml" ]; then
              mkdir -p "/home/${user}/.continue"
              rm -f "/home/${user}/.continue/config.ts"
              cat << EOF > "/home/${user}/.continue/config.yaml"
    {
      "name": "CPA",
      "version": "1.0.0",
      "schema": "v1",
      "models": [
        {
          "title": "Claude 3.7 Sonnet (Thinking)",
          "name": "Claude 3.7 Sonnet (Thinking)",
          "provider": "openai",
          "model": "claude-3-7-sonnet-thinking",
          "apiBase": "$OPENAI_BASE_URL",
          "apiKey": "$OPENAI_API_KEY",
          "roles": ["chat", "edit", "apply"]
        }
      ],
      "tabAutocompleteModel": {
        "title": "Claude 3.7 Sonnet (Thinking)",
        "name": "Claude 3.7 Sonnet (Thinking)",
        "provider": "openai",
        "model": "claude-3-7-sonnet-thinking",
        "apiBase": "$OPENAI_BASE_URL",
        "apiKey": "$OPENAI_API_KEY"
      },
      "allowAnonymousTelemetry": false
    }
    EOF
              cp -f "/home/${user}/.continue/config.yaml" "/home/${user}/.continue/config.json"
              chmod 0600 "/home/${user}/.continue/config.yaml" "/home/${user}/.continue/config.json"
            fi
            if [ ! -f "/home/${user}/.vscode-server/data/User/roo-settings.json" ]; then
              mkdir -p "/home/${user}/.vscode-server/data/User"
              cat << EOF > "/home/${user}/.vscode-server/data/User/roo-settings.json"
    {
      "providerProfiles": {
        "currentApiConfigName": "cpa",
        "apiConfigs": {
          "cpa": {
            "id": "cpa",
            "apiProvider": "openai",
            "openAiBaseUrl": "$OPENAI_BASE_URL",
            "openAiApiKey": "$OPENAI_API_KEY",
            "openAiModelId": "claude-3-7-sonnet-thinking"
          }
        }
      }
    }
    EOF
              chmod 0600 "/home/${user}/.vscode-server/data/User/roo-settings.json"
            fi
            if [ -f "/home/${user}/.vscode-server/data/User/settings.json" ]; then
              mkdir -p "/home/${user}/.vscode-server/data/Machine"
              cp -f "/home/${user}/.vscode-server/data/User/settings.json" "/home/${user}/.vscode-server/data/Machine/settings.json" || true
            fi
          fi
        fi

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

  home-manager.users.${user}.home.file =
    let
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
        "continue.enableTabAutocomplete" = true;
        "roo-cline.autoImportSettingsPath" = "/home/${user}/.vscode-server/data/User/roo-settings.json";

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
    in
    {
      vscode = {
        target = ".vscode-server/data/User/settings.json";
        text = builtins.toJSON vscodeSettings;
      };
      vscodeMachine = {
        target = ".vscode-server/data/Machine/settings.json";
        text = builtins.toJSON vscodeSettings;
      };
    };

  sops.secrets."cpa/api_key" = { };

  systemd.tmpfiles.rules = [
    "d /home/${user}/.continue 0750 ${user} users -"
  ];

  systemd.services.vscode-web.serviceConfig.EnvironmentFile = [
    config.sops.templates."vscode-web-environment".path
  ];

  sops.templates."vscode-web-environment" = {
    content = ''
      GITHUB_TOKEN=${config.sops.placeholder."github-token"}
      CPA_API_KEY=${config.sops.placeholder."cpa/api_key"}
      OPENAI_API_KEY=${config.sops.placeholder."cpa/api_key"}
      OPENAI_BASE_URL=https://${config.services.cpa.domain}/v1
      ANTHROPIC_API_KEY=${config.sops.placeholder."cpa/api_key"}
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
      ".continue"
    ];
  };
}
