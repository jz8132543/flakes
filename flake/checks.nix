{
  config,
  self,
  inputs,
  lib,
  wineAudioHome,
  ...
}:
let
  getHostToplevel =
    name: cfg:
    let
      inherit (cfg.pkgs.stdenv.hostPlatform) system;
    in
    {
      "${system}"."nixos/${name}" = cfg.config.system.build.toplevel;
    };
  hostToplevels = lib.foldr lib.recursiveUpdate { } (
    lib.mapAttrsToList getHostToplevel config.flake.nixosConfigurations
  );
  fra0Pkgs = config.flake.nixosConfigurations.fra0.pkgs;
  livekitSuiteTest = {
    "${fra0Pkgs.stdenv.hostPlatform.system}"."livekit-suite-test" =
      let
        lazy = import ../nixos/modules/services/livekit-suite/test-discovery.nix { inherit lib; };
        cfg = config.flake.nixosConfigurations.fra0.config.services.livekitSuite;
        hosts = map (name: config.flake.nixosConfigurations.${name}.config.services.livekitSuite) [
          "fra0"
          "cu"
          "sjc0"
        ];
      in
      assert lazy.noPackages && lazy.colmena;
      assert cfg.topology.primary.name == "fra0";
      assert builtins.length cfg.topology.sfuNodes == 3;
      assert builtins.length cfg.topology.turnServers == 9;
      assert builtins.length cfg.topology.redisNodes == 1;
      assert lib.all (host: host.sfu.enable && host.turn.enable && !host.development) hosts;
      fra0Pkgs.runCommand "livekit-suite-test"
        {
          nativeBuildInputs = with fra0Pkgs; [
            python3
            nodejs
            livekit
            coturn
            redis
          ];
        }
        ''
          cp -r ${../nixos/modules/services/livekit-suite} suite
          chmod -R u+w suite
          python3 -B suite/test-runtime.py -v
          python3 -B suite/test-android-control.py -v
          node --check suite/frontend/app.js
          python3 -B suite/test-services.py
          touch "$out"
        '';
  };
  desktopEvaluationTest = {
    "x86_64-linux"."desktop-evaluation-test" =
      let
        results = lib.genAttrs [ "arx8" "surface" ] (
          name:
          lib.genAttrs [ "umbriel" "gnome" ] (
            session:
            let
              host = config.flake.nixosConfigurations.${name}.extendModules {
                modules = [ { desktop.defaultSession = lib.mkForce session; } ];
              };
            in
            {
              # Force complete module evaluation, without building either system.
              system = builtins.unsafeDiscardStringContext host.config.system.build.toplevel.drvPath;
              home = builtins.unsafeDiscardStringContext host.config.home-manager.users.tippy.home.activationPackage.drvPath;
            }
          )
        );
      in
      fra0Pkgs.runCommand "desktop-evaluation-test" { result = builtins.toJSON results; } ''
        printf '%s\n' "$result" > "$out"
      '';
  };
  wineAudioLaunchersTest = {
    "x86_64-linux"."wine-audio-launchers-test" = import ../tests/wine-audio-launchers-test.nix {
      inherit (wineAudioHome) pkgs;
      home = wineAudioHome.config;
      bitwigPackage = config.flake.packages.x86_64-linux.bitwig-studio-patched;
    };
  };
  fluxdownConfigTest = {
    "x86_64-linux"."fluxdown-config-test" = import ../tests/fluxdown-config-test.nix {
      pkgs = config.flake.nixosConfigurations.arx8.pkgs;
      configurations = config.flake.nixosConfigurations;
    };
  };
  bitwigPackageTest = {
    "x86_64-linux"."bitwig-package-test" = import ../tests/bitwig-package-test.nix {
      pkgs = config.flake.nixosConfigurations.arx8.pkgs;
      package = config.flake.packages.x86_64-linux.bitwig-studio-patched;
      hostPackages = config.flake.nixosConfigurations.arx8.config.environment.systemPackages;
    };
  };
  gpuStorageConfigTest = {
    "x86_64-linux"."gpu-storage-config-test" =
      fra0Pkgs.runCommand "gpu-storage-config-test"
        {
          result = builtins.toJSON (
            import ../tests/gpu-storage-config-test.nix {
              inherit lib;
              configurations = config.flake.nixosConfigurations;
            }
          );
        }
        ''
          printf '%s\n' "$result" > "$out"
        '';
  };
  umbrielNoctaliaTest = {
    "x86_64-linux"."umbriel-noctalia-test" =
      fra0Pkgs.runCommand "umbriel-noctalia-test"
        {
          result = builtins.toJSON (
            import ../tests/umbriel-noctalia-test.nix {
              inherit lib;
              configurations = config.flake.nixosConfigurations;
            }
          );
        }
        ''
          set -o pipefail
          mkdir -p "$out"
          printf '%s\n' "$result" > "$out/checks.json"
          ${fra0Pkgs.luajit}/bin/luajit ${../tests/noctalia-sysmon-cards-test.lua} \
            ${../home-manager/modules/desktop/noctalia/sysmon-cards/card.luau}
          ${lib.concatMapStringsSep "\n"
            (
              name:
              let
                home = config.flake.nixosConfigurations.${name}.config.home-manager.users.tippy;
              in
              ''
                # Config-only CLI: never launch a graphical compositor in the sandbox.
                ${home.programs.umbriel.package}/bin/umbriel config validate \
                  -c ${home.xdg.configFile."umbriel/config.toml".source} --json \
                  | tee "$out/${name}-umbriel.json"
                # Realize the upstream HM checkConfig derivation as well.
                test -s ${home.xdg.configFile."noctalia/config.toml".source}
                # Building the override catches read-only upstream .desktop modes.
                grep -Fx 'NotShowIn=Umbriel;umbriel;' \
                  ${home.xdg.configFile."autostart/org.fcitx.Fcitx5.desktop".source}
              ''
            )
            [
              "arx8"
              "surface"
            ]
          }
        '';
  };
  wallpaperHdrTest = {
    "x86_64-linux"."wallpaper-hdr-test" =
      let
        pkgs = config.flake.nixosConfigurations.arx8.pkgs;
      in
      pkgs.runCommand "wallpaper-hdr-test"
        {
          nativeBuildInputs = [
            (pkgs.python3.withPackages (p: [
              p.numpy
              p.pillow
            ]))
          ];
        }
        ''
          python3 -B ${../tests/wallpaper-hdr-test.py} ${../pkgs/wallpaper/hdr.py} \
            ${pkgs.wallpaper.hdr}/wallpaper-hdr.png
          touch "$out"
        '';
  };
  mihomoSubscriptionTest = {
    "x86_64-linux"."mihomo-subscription-test" =
      let
        host = config.flake.nixosConfigurations.arx8;
        source = lib.fileset.toSource {
          root = ../.;
          fileset = lib.fileset.unions [
            ../tests/test-mihomo-subscription.py
            ../tests/test-mihomo-runtime-policy.py
            ../nixos/modules/desktop/mihomo-subscription.sh
            ../nixos/modules/desktop/mihomo-runtime-policy.py
          ];
        };
      in
      host.pkgs.runCommand "mihomo-subscription-test"
        {
          nativeBuildInputs = [
            (host.pkgs.python3.withPackages (ps: [ ps.pyyaml ]))
            host.pkgs.bash
            host.pkgs.coreutils
          ];
          updater = host.config.system.build.mihomoSubscriptionUpdater;
          PUBLISHED_MIHOMO_CONFIG =
            config.flake.nixosConfigurations.fra0.config.sops.templates."subscription/mihomo.yaml".file;
          PUBLISHED_MIHOMO_SMART_CONFIG =
            config.flake.nixosConfigurations.fra0.config.sops.templates."subscription/mihomo-smart.yaml".file;
          PUBLISHED_VLESS_URIS =
            config.flake.nixosConfigurations.fra0.config.sops.templates."subscription/v2ray.txt".file;
          PUBLISHED_HEALTH_CHECK_URL =
            config.flake.nixosConfigurations.fra0.config.services.subscriptionPublisher.healthCheckUrl;
          MIHOMO_REAL_BIN = lib.getExe host.config.services.mihomo.package;
          # The desktop host runs the fork kernel, so validate with that binary.
          MIHOMO_SMART_BIN = lib.getExe host.pkgs.nur.repos.zerozawa.mihomo-smart;
          inherit (host.config.systemd.services.mihomo-subscription-update.environment)
            MIHOMO_GEOIP
            MIHOMO_GEOSITE
            MIHOMO_MMDB
            MIHOMO_POLICY_FILE
            ;
        }
        ''
          test -x "$updater/bin/mihomo-subscription-update"
          python3 -B ${source}/tests/test-mihomo-runtime-policy.py -v
          python3 -B ${source}/tests/test-mihomo-subscription.py -v
          touch "$out"
        '';
  };
  proxyXhttpTest = {
    "x86_64-linux"."proxy-xhttp-test" = import ../tests/xray-config-test.nix {
      pkgs = fra0Pkgs;
    };
  };
  mihomoSmartGroupTest = {
    "x86_64-linux"."mihomo-smart-group-test" =
      let
        assertions = import ../tests/mihomo-smart-group-test.nix { inherit lib; };
        failures = lib.attrNames (lib.filterAttrs (_: v: v.expected != v.result) assertions);
      in
      fra0Pkgs.runCommand "mihomo-smart-group-test"
        {
          # runCommand 的 env 需要字符串；列表会让求值失败。
          failures = lib.concatStringsSep " " failures;
        }
        ''
          if [ -n "$failures" ]; then
            echo "mihomo-smart group assertions failed:" >&2
            for name in $failures; do echo "  - $name" >&2; done
            exit 1
          fi
          touch "$out"
        '';
  };
  speedtestWorkerTest = {
    "x86_64-linux"."speedtest-worker-test" =
      let
        source = lib.fileset.toSource {
          root = ../.;
          fileset = lib.fileset.unions [
            ../tests/speedtest-worker-test.mjs
            ../terraform/cloudflare.tf
            ../terraform/.terraform.lock.hcl
            ../terraform/modules/speedtest-worker
          ];
        };
      in
      fra0Pkgs.runCommand "speedtest-worker-test" { nativeBuildInputs = [ fra0Pkgs.nodejs ]; } ''
        node --test ${source}/tests/speedtest-worker-test.mjs
        touch "$out"
      '';
  };
  mactahoeMigrationTest = {
    "x86_64-linux"."mactahoe-migration-test" =
      fra0Pkgs.runCommand "mactahoe-migration-test"
        {
          nativeBuildInputs = [ fra0Pkgs.python3 ];
          MIGRATION_SOURCE = ../home-manager/modules/desktop/mactahoe/migration.py;
        }
        ''
          python3 -B ${../tests/mactahoe-migration-test.py} -v
          touch "$out"
        '';
  };
  mactahoeAppearanceTest = {
    "x86_64-linux"."mactahoe-appearance-test" =
      let
        pkgs = config.flake.nixosConfigurations.arx8.pkgs;
      in
      pkgs.runCommand "mactahoe-appearance-test"
        {
          nativeBuildInputs = [ pkgs.python3 ];
          APPEARANCE_SOURCE = ../home-manager/modules/desktop/mactahoe/appearance.py;
          FLATPAK_BIN = "${pkgs.flatpak}/bin/flatpak";
        }
        ''
          python3 -B ${../tests/mactahoe-appearance-test.py} -v
          touch "$out"
        '';
  };
  mactahoeFirefoxTest = {
    "x86_64-linux"."mactahoe-firefox-test" =
      fra0Pkgs.runCommand "mactahoe-firefox-test"
        {
          nativeBuildInputs = [ fra0Pkgs.python3 ];
          FIREFOX_SOURCE = ../home-manager/modules/desktop/mactahoe/firefox.py;
          FIREFOX_MODULE_SOURCE = ../home-manager/modules/desktop/mactahoe/firefox.nix;
        }
        ''
          python3 -B ${../tests/mactahoe-firefox-test.py} -v
          touch "$out"
        '';
  };
  mactahoeStartupAssetsTest = {
    "x86_64-linux"."mactahoe-startup-assets-test" =
      let
        host = config.flake.nixosConfigurations.arx8;
      in
      host.pkgs.runCommand "mactahoe-startup-assets-test"
        {
          nativeBuildInputs = [ host.pkgs.python3 ];
          STARTUP_SOURCE = ../nixos/modules/desktop/mactahoe/assets;
          STARTUP_PACKAGE = host.config.desktop.mactahoe.startupPackage;
          PLYMOUTH_PLUGIN = "${host.config.boot.plymouth.package}/lib/plymouth/script.so";
        }
        ''
          python3 -B ${../tests/mactahoe-startup-assets-test.py} -v
          touch "$out"
        '';
  };
  rimeStateTest = {
    "x86_64-linux" = lib.genAttrs [ "rime-state-test" "fcitx5-rime-state-test" ] (
      testName:
      let
        isFcitx = testName == "fcitx5-rime-state-test";
        cfg =
          (config.flake.nixosConfigurations.arx8.extendModules {
            modules = [
              { desktop.inputMethod.framework = lib.mkForce (if isFcitx then "fcitx5" else "ibus"); }
            ];
          }).config;
        home = cfg.home-manager.users.tippy;
      in
      fra0Pkgs.runCommand testName
        {
          nativeBuildInputs = [
            fra0Pkgs.python3
            fra0Pkgs.bash
            fra0Pkgs.stdenv.cc
          ];
          buildInputs = [ fra0Pkgs.librime ];
          RIME_DATA = cfg.system.build.rimeUserData;
          RIME_HOME = home.home.homeDirectory;
          RIME_INIT = home.home.activation.initializeRimeState.data;
          RIME_SUBDIR = if isFcitx then ".local/share/fcitx5/rime" else ".config/ibus/rime";
          FCITX_CONFIG = if isFcitx then home.xdg.configFile."fcitx5/config".source else "";
          FCITX_PROFILE = if isFcitx then home.xdg.configFile."fcitx5/profile".source else "";
          CHROMIUM_ARGS = if isFcitx then builtins.toJSON home.programs.chromium.commandLineArgs else "[]";
        }
        ''
          cc ${../tests/rime-smoke-test.c} -lrime -o rime-smoke-test
          export RIME_SMOKE="$PWD/rime-smoke-test"
          python3 -B ${../tests/rime-state-test.py} -v
          touch "$out"
        ''
    );
  };
  hpbTest = {
    "${fra0Pkgs.stdenv.hostPlatform.system}"."nextcloud-hpb-test" =
      fra0Pkgs.runCommand "nextcloud-hpb-test"
        {
          testResult = builtins.toJSON (import ../tests/nextcloud-hpb-test.nix);
        }
        ''
          echo "$testResult" > $out
        '';
  };
  tsshTest = {
    "${fra0Pkgs.stdenv.hostPlatform.system}"."tssh-auto-test" = import ../tests/tssh-auto-test.nix {
      pkgs = fra0Pkgs;
    };
  };
  tsshPolicyTest = {
    "${fra0Pkgs.stdenv.hostPlatform.system}"."tssh-policy-test" =
      let
        results = lib.mapAttrs (
          name: host:
          let
            cfg = host.config;
            transport = cfg.programs.ssh.transport;
            enabled = !(builtins.elem name transport.excludedHosts);
            marker = cfg.services.openssh.settings.VersionAddendum or null;
            packages = map toString cfg.environment.systemPackages;
            home = cfg.home-manager.users.tippy;
            tsshSettings = home.xdg.configFile."tssh/tssh.conf" or { enable = false; };
            tsshProfile = home.xdg.configFile."tssh/ssh_config" or { enable = false; };
          in
          {
            inherit (transport) excludedHosts;
            valid =
              transport.enable
              && transport.effectiveEnabled == enabled
              && cfg.programs.ssh.package.pname == "openssh"
              && cfg.services.openssh.package.pname == "openssh"
              && !cfg.services.logind.settings.Login.KillUserProcesses
              && (
                !(cfg.environment.minimal or false)
                || (
                  cfg.systemd.services.systemd-logind.reloadIfChanged
                  &&
                    builtins.elem cfg.environment.etc."systemd/logind.conf".source
                      cfg.systemd.services.systemd-logind.restartTriggers
                )
              )
              && builtins.elem 22 cfg.services.openssh.ports
              && builtins.elem cfg.ports.ssh cfg.services.openssh.ports
              && (marker == "tsshd-kcp-auto-v1") == enabled
              && builtins.elem (toString transport.package) packages == enabled
              && builtins.elem transport.udpPortRange cfg.networking.firewall.allowedUDPPortRanges == enabled
              && (
                if enabled then
                  lib.hasInfix "FuzzyHostSelection = no" tsshSettings.text
                  && lib.hasInfix "ConfigPath = ${home.xdg.configHome}/tssh/ssh_config" tsshSettings.text
                  && lib.hasInfix "UserKnownHostsFile none" tsshProfile.text
                  && lib.hasInfix "CanonicalizeHostname no" tsshProfile.text
                  && home.programs.ssh.settings."*".data.userKnownHostsFile == "/dev/null"
                else
                  !tsshSettings.enable && !tsshProfile.enable
              );
          }
        ) config.flake.nixosConfigurations;
      in
      assert lib.assertMsg (lib.all (result: result.valid) (
        builtins.attrValues results
      )) "SSH transport policy does not preserve OpenSSH or the host exception list";
      fra0Pkgs.runCommand "tssh-policy-test" { result = builtins.toJSON results; } ''
        printf '%s\n' "$result" > "$out"
      '';
  };
  tsshAdapterTest = {
    "${fra0Pkgs.stdenv.hostPlatform.system}"."tssh-adapter-test" =
      fra0Pkgs.runCommand "tssh-adapter-test" { nativeBuildInputs = [ fra0Pkgs.python3 ]; }
        ''
          mkdir -p tests home-manager/modules/desktop
          cp ${../tests/test-vscode-ssh-adapter.py} tests/test-vscode-ssh-adapter.py
          cp ${../home-manager/modules/desktop/vscode-ssh-adapter.py} home-manager/modules/desktop/vscode-ssh-adapter.py
          python3 -B tests/test-vscode-ssh-adapter.py
          touch "$out"
        '';
  };
  hostIndependenceTest = {
    "${fra0Pkgs.stdenv.hostPlatform.system}"."host-independence-test" =
      let
        result = import ../tests/ssh-host-independence-test.nix {
          inherit self lib;
          configurations = config.flake.nixosConfigurations;
        };
      in
      assert lib.assertMsg (
        result.sshArtifactsUnchanged && result.extensionControlUnchanged && result.systemToplevelsUnchanged
      ) "Adding a host inventory entry changed an existing system derivation.";
      fra0Pkgs.runCommand "host-independence-test" { result = builtins.toJSON result; } ''
        printf '%s\n' "$result" > "$out"
      '';
  };
  grafanaRuntimeHostsTest = {
    "${fra0Pkgs.stdenv.hostPlatform.system}"."grafana-runtime-hosts-test" =
      fra0Pkgs.runCommand "grafana-runtime-hosts-test"
        {
          nativeBuildInputs = [ fra0Pkgs.python3 ];
          dashboard =
            config.flake.nixosConfigurations.fra0.config.services.grafana.settings.dashboards.default_home_dashboard_path;
        }
        ''
          python3 -c 'import json,os; v=json.load(open(os.environ["dashboard"]))["templating"]["list"][0]; assert v["type"] == "query"; assert v["query"] == "label_values(up{job=\"node\"}, instance)"; assert v["options"] == []; assert v["refresh"] == 1; assert v["datasource"]["uid"] == "prometheus-default"'
          touch "$out"
        '';
  };
  aiRegistrationTest = {
    "${fra0Pkgs.stdenv.hostPlatform.system}"."ai-registration-test" =
      let
        cfg = config.flake.nixosConfigurations.fra0.config;
        containers = cfg.virtualisation.oci-containers.containers;
        difyRegistrationDisabled =
          env:
          env.ALLOW_REGISTER == "false"
          && env.ALLOW_CREATE_WORKSPACE == "false"
          && env.ENABLE_EMAIL_CODE_LOGIN == "false"
          && env.ENABLE_SOCIAL_OAUTH_LOGIN == "false"
          && env.ENABLE_EMAIL_PASSWORD_LOGIN == "true";
        newApiScript = cfg.systemd.services.new-api-bootstrap.script;
        mcpEnv = containers.contextforge.environment;
        realm = builtins.fromJSON cfg.sops.templates."keycloak-realm-dora".content;
        results = {
          newApi =
            lib.hasInfix ''upsert_opt "RegisterEnabled" "false"'' newApiScript
            && lib.hasInfix ''upsert_opt "PasswordRegisterEnabled" "false"'' newApiScript
            && lib.hasInfix ''upsert_opt "PasswordLoginEnabled" "true"'' newApiScript;
          difyApi = difyRegistrationDisabled containers.dify-api.environment;
          difyWorker = difyRegistrationDisabled containers.dify-worker.environment;
          contextforge =
            mcpEnv.PUBLIC_REGISTRATION_ENABLED == "false"
            && mcpEnv.SSO_AUTO_CREATE_USERS == "false"
            && mcpEnv.SSO_ENABLED == "true"
            && mcpEnv.SSO_PRESERVE_ADMIN_AUTH == "true"
            && mcpEnv.PLATFORM_ADMIN_EMAIL == "i@${cfg.networking.domain}";
          keycloakRealm = realm.realm == "users" && !realm.registrationAllowed;
          keycloakExistingRealm =
            lib.hasInfix "registration_allowed = false" cfg.systemd.services.keycloak-ldap-reconcile.script
            && builtins.elem "keycloak-ldap-reconcile.service" cfg.systemd.services.keycloak.requires;
        };
      in
      assert lib.assertMsg (lib.all (value: value) (
        builtins.attrValues results
      )) "fra0 AI registration policy must block self-registration while preserving existing logins";
      fra0Pkgs.runCommand "ai-registration-test" { result = builtins.toJSON results; } ''
        printf '%s\n' "$result" > "$out"
      '';
  };
  newApiResponsesPolicyTest = {
    "${fra0Pkgs.stdenv.hostPlatform.system}"."new-api-responses-policy-test" =
      let
        host = config.flake.nixosConfigurations.fra0;
        cfg = host.config;
        policy = cfg.services.new-api.chatCompletionsToResponses;
        variant =
          value:
          (host.extendModules {
            modules = [ { services.new-api.chatCompletionsToResponses = lib.mkForce value; } ];
          }).config;
        valid =
          value:
          lib.all (
            item: item.assertion || !(lib.hasPrefix "services.new-api.chatCompletionsToResponses:" item.message)
          ) (variant value).assertions;
        unmanaged = variant null;
        disabled = variant { enable = false; };
        defaults = variant { };
        custom = variant {
          enable = true;
          allChannels = false;
          channelIds = [ 17 ];
          channelTypes = [ 1 ];
          modelPatterns = policy.modelPatterns ++ [
            "^alias's[.]name\\\\path\"[$](suffix)?$"
            "^alias[\n\t]$"
          ];
        };
        invalidRegex = variant {
          enable = true;
          modelPatterns = [ "(?=unsupported-lookahead)" ];
        };
        fixture = conf: {
          policy = conf.services.new-api.chatCompletionsToResponses;
          # Only test the emitted text, not builds referenced by unrelated bootstrap steps.
          script = builtins.unsafeDiscardStringContext conf.systemd.services.new-api-bootstrap.script;
        };
        script = cfg.systemd.services.new-api-bootstrap.script;
      in
      assert cfg.services.new-api.enable && !(cfg.services.ai.litellm.enable or false);
      assert !(builtins.hasAttr "litellm" cfg.virtualisation.oci-containers.containers);
      assert cfg.services.new-api.domain == "api.dora.im";
      assert host.options.services.new-api.chatCompletionsToResponses.default == { };
      assert policy.enable && policy.allChannels;
      assert policy.channelIds == [ ] && policy.channelTypes == [ ];
      assert policy == defaults.services.new-api.chatCompletionsToResponses;
      assert builtins.length policy.modelPatterns == 4;
      assert valid null && valid { } && valid { enable = true; };
      assert valid {
        enable = true;
        allChannels = false;
        channelIds = [ 17 ];
      };
      assert valid {
        enable = true;
        allChannels = false;
        channelTypes = [ 1 ];
      };
      assert
        !(valid {
          enable = true;
          allChannels = false;
        });
      assert lib.all
        (
          patterns:
          !(valid {
            enable = true;
            modelPatterns = patterns;
          })
        )
        [
          [ ]
          [ "" ]
          [ " \t\r\n" ]
          [
            "^valid$"
            " "
          ]
        ];
      assert valid {
        enable = false;
        allChannels = false;
        modelPatterns = [ ];
      };
      assert lib.all (text: lib.hasInfix text script) [
        ''upsert_opt "RegisterEnabled" "false"''
        ''upsert_opt "PasswordRegisterEnabled" "false"''
        ''upsert_opt "PasswordLoginEnabled" "true"''
        "SYNC_FREQUENCY"
      ];
      assert !(lib.hasInfix "systemctl restart" script);
      fra0Pkgs.runCommand "new-api-responses-policy-test"
        {
          nativeBuildInputs = [
            fra0Pkgs.go
            cfg.services.postgresql.package
          ];
          fixtures = fra0Pkgs.writeText "new-api-responses-policy-fixtures.json" (
            builtins.toJSON (
              lib.mapAttrs (_: fixture) {
                fra0 = cfg;
                inherit
                  unmanaged
                  disabled
                  custom
                  invalidRegex
                  defaults
                  ;
              }
            )
          );
        }
        ''
          export HOME="$TMPDIR" GOCACHE="$TMPDIR/go-cache" GO111MODULE=off
          export PGHOST="$PWD" PGPORT=55432 PGDATABASE=new_api
          initdb -D pg --auth=trust --no-locale >/dev/null
          trap 'pg_ctl -D pg -m immediate -w stop >/dev/null' EXIT
          pg_ctl -D pg -o "-k $PWD -h \"\" -p $PGPORT" -w start >/dev/null
          createdb new_api
          go run ${../tests/new-api-responses-policy-test.go} "$fixtures"
          touch "$out"
        '';
  };
  workbuddyTest = {
    "${fra0Pkgs.stdenv.hostPlatform.system}"."workbuddy2api-hub-test" =
      let
        cfg = config.flake.nixosConfigurations.fra0.config;
        gateway = cfg.services.workbuddy2api-hub;
        container = cfg.virtualisation.oci-containers.containers.workbuddy2api-hub;
        proxy = cfg.services.traefik.proxies.workbuddy2api-hub;
        env = cfg.sops.templates."workbuddy2api-hub-env";
      in
      assert lib.assertMsg (
        gateway.enable
        && gateway.domain == "workbuddy.dora.im"
        && container.ports == [ "127.0.0.1:${toString gateway.port}:8788" ]
        && lib.hasInfix "--lan >/dev/null" (lib.concatStringsSep " " container.cmd)
        && container.environment.WB_MEDIA_DIR == "/app/usage/media"
        && container.environmentFiles == [ env.path ]
        && env.mode == "0600"
        && lib.hasInfix cfg.sops.placeholder.openai_api_key env.content
        && proxy.rule == "Host(`${gateway.domain}`)"
        && proxy.target == "http://127.0.0.1:${toString gateway.port}"
        && builtins.elem "https://${gateway.domain}/health" cfg.services.cluster-monitoring.server.publicEndpoints
        && builtins.elem gateway.dataDir cfg.environment.global-persistence.directories
        && builtins.elem gateway.dataDir cfg.services.restic.backups.borgbase.paths
      ) "WorkBuddy must use SOPS credentials, loopback-only publishing and persistent data";
      fra0Pkgs.runCommand "workbuddy2api-hub-test" { nativeBuildInputs = [ fra0Pkgs.python3 ]; } ''
        mkdir -p tests nixos/modules/services/ai/gateway
        cp ${../tests/test-workbuddy2api-hub.py} tests/test-workbuddy2api-hub.py
        cp ${../nixos/modules/services/ai/gateway/workbuddy2api-hub-init.py} nixos/modules/services/ai/gateway/workbuddy2api-hub-init.py
        python3 -B tests/test-workbuddy2api-hub.py -v
        touch "$out"
      '';
  };
  dn42SdwanTest = {
    "${fra0Pkgs.stdenv.hostPlatform.system}"."dn42-sdwan-state-test" =
      let
        services = config.flake.nixosConfigurations.fra0.config.systemd.services;
      in
      fra0Pkgs.runCommand "dn42-sdwan-state-test"
        {
          nativeBuildInputs = with fra0Pkgs; [
            python3
            bash
            jq
            util-linux
            coreutils
            gnugrep
            iproute2
          ];
          DN42_SDWAN_CONTROLLER_SCRIPT = builtins.head services.dn42-sdwan-controller.restartTriggers;
          DN42_SDWAN_AGENT_SCRIPT = builtins.head services.dn42-sdwan-agent.restartTriggers;
          DN42_SDWAN_CHARON_PRESTART = services.strongswan-swanctl.preStart;
        }
        ''
          mkdir -p tests nixos/modules/services/networking/dn42
          cp ${../tests/dn42-sdwan-state-test.py} tests/dn42-sdwan-state-test.py
          cp ${../nixos/modules/services/networking/dn42/sdwan-state.sh} nixos/modules/services/networking/dn42/sdwan-state.sh
          cp ${../nixos/modules/services/networking/dn42/sdwan-state.jq} nixos/modules/services/networking/dn42/sdwan-state.jq
          python3 -B tests/dn42-sdwan-state-test.py -v
          touch "$out"
        '';
  };
  tcpBrutalRoutingTest = {
    "${fra0Pkgs.stdenv.hostPlatform.system}"."tcp-brutal-routing-test" =
      let
        render =
          target:
          let
            module = import ../nixos/modules/optimize/brutal.nix {
              inherit inputs;
              inherit (fra0Pkgs) lib;
              pkgs = fra0Pkgs // {
                writeShellScriptBin = _: text: { outPath = text; };
              };
              config = {
                boot.kernelPackages = fra0Pkgs.linuxPackages;
                optimize.brutal = {
                  inherit target;
                  enable = true;
                  bandwidth = 500;
                  enableIpv4 = true;
                  enableIpv6 = true;
                  extraCidrs = [
                    "198.51.100.0/24"
                    "2001:db8:ffff::/48"
                  ];
                };
              };
            };
            script = lib.removeSuffix "/bin/tcp-brutal-apply-rules" module.config.content.systemd.services.tcp-brutal-china-rules.serviceConfig.ExecStart;
          in
          # The test replaces kernel/proc and binary paths; do not build a kernel.
          fra0Pkgs.writeText "tcp-brutal-${if target == "cn" then "cn" else "non-cn"}-test.sh" (
            builtins.unsafeDiscardStringContext script
          );
      in
      fra0Pkgs.runCommand "tcp-brutal-routing-test"
        {
          nativeBuildInputs = with fra0Pkgs; [
            python3
            bash
            gawk
            coreutils
            gnugrep
          ];
          TCP_BRUTAL_CN_SCRIPT = render "cn";
          TCP_BRUTAL_NON_CN_SCRIPT = render "!cn";
        }
        ''
          mkdir -p tests
          cp ${../tests/tcp-brutal-routing-test.py} tests/tcp-brutal-routing-test.py
          python3 -B tests/tcp-brutal-routing-test.py -v
          touch "$out"
        '';
  };
in
{
  flake.checks = lib.foldr lib.recursiveUpdate { } [
    hostToplevels
    livekitSuiteTest
    desktopEvaluationTest
    wineAudioLaunchersTest
    fluxdownConfigTest
    bitwigPackageTest
    gpuStorageConfigTest
    umbrielNoctaliaTest
    wallpaperHdrTest
    mihomoSubscriptionTest
    proxyXhttpTest
    mihomoSmartGroupTest
    speedtestWorkerTest
    mactahoeMigrationTest
    mactahoeAppearanceTest
    mactahoeFirefoxTest
    mactahoeStartupAssetsTest
    rimeStateTest
    hpbTest
    tsshTest
    tsshPolicyTest
    tsshAdapterTest
    hostIndependenceTest
    grafanaRuntimeHostsTest
    aiRegistrationTest
    newApiResponsesPolicyTest
    workbuddyTest
    dn42SdwanTest
    tcpBrutalRoutingTest
  ];
}
