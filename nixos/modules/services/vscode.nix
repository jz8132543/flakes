{
  config,
  pkgs,
  inputs,
  nixosModules,
  ...
}:
let
  vscodeExtensionsPkgs = inputs.nix-vscode-extensions.extensions.${pkgs.system};
in
{
  # https://github.com/alienzj/dotfiles/blob/dev/modules/editors/vscode.nix
  imports = [ nixosModules.desktop.fonts ];
  services.code-server = {
    enable = true;
    user = "tippy";
    port = config.ports.code;
    disableGettingStartedOverride = true;
    disableTelemetry = true;
    disableUpdateCheck = true;
    disableWorkspaceTrust = true;
    hashedPassword = "$argon2i$v=19$m=4096,t=3,p=1$bElKaGtpd1RnMEpOK3psNmpyU2dwcDFHU0U0PQ$ZCgtKICfKUwPFsChiEIqcmVDRGafF1JEZAN9Fu5klQA";
    #auth = "";
    package = pkgs.vscode-with-extensions.override {
      vscode = pkgs.code-server;
      vscodeExtensions =
        (with pkgs.vscode-extensions; [
          # ai
          github.copilot-chat
          github.copilot

          # ui
          pkief.material-icon-theme
          catppuccin.catppuccin-vsc
          naumovs.color-highlight
          ibm.output-colorizer
          dracula-theme.theme-dracula

          # format
          esbenp.prettier-vscode
          oderwat.indent-rainbow
          shardulm94.trailing-spaces
          editorconfig.editorconfig
          davidanson.vscode-markdownlint

          # error
          usernamehw.errorlens

          # code runner
          formulahendry.code-runner

          # test
          hbenl.vscode-test-explorer
          ms-vscode.test-adapter-converter

          # comments
          aaron-bond.better-comments

          # nix
          bbenoist.nix
          # kamadorueda.alejandra
          arrterian.nix-env-selector
          jnoortheen.nix-ide
          mkhl.direnv

          # lua
          sumneko.lua
          vscodeExtensionsPkgs.vscode-marketplace.johnnymorganz.stylua

          # debug
          vadimcn.vscode-lldb

          # shell
          foxundermoon.shell-format

          # python
          ms-python.python
          ms-python.vscode-pylance
          ms-python.debugpy
          ms-python.isort

          # jupyter
          ms-toolsai.jupyter
          ms-toolsai.jupyter-keymap
          ms-toolsai.jupyter-renderers
          ms-toolsai.vscode-jupyter-cell-tags
          ms-toolsai.vscode-jupyter-slideshow

          # cpp
          ms-vscode.cpptools
          ms-vscode.cmake-tools
          ms-vscode.makefile-tools
          twxs.cmake
          xaver.clang-format

          # rust
          rust-lang.rust-analyzer
          #serayuzgur.crates
          fill-labs.dependi
          tamasfe.even-better-toml

          # docker
          ms-azuretools.vscode-docker

          # remote dev
          ms-vscode-remote.remote-ssh
          ms-vscode-remote.remote-ssh-edit
          ms-vscode-remote.remote-containers

          # vim keybindings
          vscodevim.vim

          # csv
          mechatroner.rainbow-csv

          # yaml
          redhat.vscode-yaml

          # markdown
          yzhang.markdown-all-in-one

          # svg
          jock.svg

          # pdf
          tomoki1207.pdf

          # tex
          james-yu.latex-workshop

          # haskell
          haskell.haskell
          justusadam.language-haskell

          # lisp
          mattn.lisp

          # go
          golang.go

          # git
          github.codespaces
          github.vscode-pull-request-github
          github.vscode-github-actions
          eamodio.gitlens
          donjayamanne.githistory
          mhutchie.git-graph

          # r
          reditorsupport.r

          # web
          octref.vetur
          christian-kohler.path-intellisense
          formulahendry.auto-close-tag
          batisteo.vscode-django

          # janet
          janet-lang.vscode-janet

          # efficiently manage dependencies
          fill-labs.dependi
        ])
        ++ (with vscodeExtensionsPkgs.vscode-marketplace; [
          # remote dev
          # ms-vscode.remote-explorer
          ms-vscode.remote-server

          # utils
          wayou.vscode-todo-highlight

          # bash
          rogalmic.bash-debug
          shakram02.bash-beautify

          # rust
          jscearcy.rust-doc-viewer
          #zhangyue.rust-mod-generator
          swellaby.vscode-rust-test-adapter
          conradludgate.rust-playground

          # R
          rdebugger.r-debugger

          # snakemake
          snakemake.snakemake-lang
          tfehlmann.snakefmt

          # nextflow
          nextflow.nextflow

          # kdl
          kdl-org.kdl
        ])
        ++ (with vscodeExtensionsPkgs.open-vsx; [
        ]);
    };
  };
  home-manager.users.${config.services.code-server.user}.home.file = {
    code-server = {
      target = ".local/share/code-server/User/settings.json";
      text = builtins.toJSON {
        # dataFile."code-server/User/settings.json".text = builtins.toJSON {
        "workbench.iconTheme" = "material-icon-theme";
        "workbench.colorTheme" = "Catppuccin Macchiato";
        "workbench.panel.defaultLocation" = "right";
        "workbench.startupEditor" = "none";
        "workbench.list.smoothScrolling" = true;

        "catppuccin.accentColor" = "mauve";

        "editor.fontFamily" =
          "\"JetBrains Mono\", \"Fira Code\", \"Fira Sans\", \"Material Design Icons\", \"Font Awesome 6 Free\", \"Symbols Nerd Font Mono\"";
        # "editor.fontSize" = cfg.fontsize;
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
      };
    };
  };

  systemd.services.code-server.serviceConfig.EnvironmentFile = [
    config.sops.templates."code-server-environment".path
  ];
  sops.templates."code-server-environment" = {
    content = ''
      # CODER_OIDC_ISSUER_URL="https://sso.dora.im/realms/users"
      # CODER_OIDC_CLIENT_ID="code-server"
      # CODER_OIDC_CLIENT_SECRET=${config.sops.placeholder."code-server/oidc-secret"}
      # CODER_OIDC_SCOPES="openid,profile,email"
      # CODER_DISABLE_PASSWORD_AUTH=true
      HASHED_PASSWORD=${config.sops.placeholder."code-server/hashed-password"}
    '';
  };
  sops.secrets = {
    "code-server/oidc-secret" = { };
    "code-server/hashed-password" = { };
  };

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      code = {
        rule = "Host(`code.${config.networking.domain}`)";
        service = "code";
      };
    };
    services = {
      code.loadBalancer = {
        passHostHeader = true;
        servers = [ { url = "http://localhost:${toString config.ports.code}"; } ];
      };
    };
  };

  nix.settings.allowed-users = [ config.services.code-server.user ];
  environment.global-persistence.user = {
    directories = [
      ".local/share/code-server"
      ".local/share/direnv"
      ".vscode-server"
    ];
  };
}
