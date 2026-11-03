{
  config,
  self,
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
in
{
  flake.checks = lib.foldr lib.recursiveUpdate { } [
    hostToplevels
    hpbTest
    tsshTest
    tsshPolicyTest
    tsshAdapterTest
    hostIndependenceTest
    grafanaRuntimeHostsTest
    aiRegistrationTest
  ];
}
