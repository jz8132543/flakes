{
  config,
  self,
  inputs,
  lib,
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
