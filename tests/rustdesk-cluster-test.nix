{ pkgs, configurations }:
let
  inherit (pkgs) lib;
  config = name: configurations.${name}.config;
  main = config "fra0";
  cu = config "cu";
  sjc = config "sjc0";
  services = name: (config name).services.rustdesk-server;
  names = [
    "fra0"
    "cu"
    "sjc0"
  ];
  python = pkgs.python3.withPackages (ps: [
    ps.cryptography
    ps.websockets
  ]);
  api = pkgs.callPackage ../pkgs/rustdesk-api { };
  server = (services "fra0").package;
  privateKey = main.sops.secrets."rustdesk/server_private_key";
  apiJwt = main.sops.secrets."rustdesk/api_jwt_key";
in
assert (services "fra0").signal.enable;
assert !(services "cu").signal.enable && !(services "sjc0").signal.enable;
assert lib.all (name: (services name).relay.enable && !(services name).openFirewall) names;
assert
  (services "fra0").cluster.relayHosts == [
    "fra0.dora.im:21117"
    "sjc0.dora.im:21117"
  ];
assert (services "fra0").signal.relayHosts == [ "fra0.dora.im:21117,sjc0.dora.im:21117" ];
assert (services "cu").cluster.relayPort == 50566;
assert (services "fra0").cluster.api.enable;
assert !(services "sjc0").cluster.api.enable && !(services "cu").cluster.api.enable;
assert lib.all
  (
    host:
    !(host.sops.secrets ? "rustdesk/api_jwt_key")
    && !(host.sops.secrets ? "rustdesk/server_private_key")
  )
  [
    cu
    sjc
  ];
assert lib.all
  (secret: secret.sopsFile == main.sops-file.get "common.yaml" && !secret.terraformOutput.enable)
  [
    privateKey
    apiJwt
  ];
assert privateKey.key == "rustdesk/server_private_key";
assert apiJwt.key == "rustdesk/api_jwt_key";
assert lib.all (
  name:
  let
    host = config name;
    secret = host.sops.secrets."rustdesk/server_public_key";
  in
  secret.sopsFile == host.sops-file.get "common.yaml"
  && secret.key == "rustdesk/server_public_key"
  && !secret.terraformOutput.enable
  &&
    host.systemd.services.rustdesk-relay.serviceConfig.LoadCredential == [ "public-key:${secret.path}" ]
  && !lib.hasInfix "rustdesk" host.sops.terraformTemplate
) names;
assert lib.all (name: (services name).package == server) names;
assert lib.elem "rustdesk.target" main.systemd.services.rustdesk-api.wantedBy;
assert lib.elem "rustdesk" main.services.postgresql.ensureDatabases;
assert lib.any (
  user: user.name == "rustdesk" && user.ensureDBOwnership
) main.services.postgresql.ensureUsers;
assert lib.all (host: !(lib.elem "rustdesk" host.services.postgresql.ensureDatabases)) [
  cu
  sjc
];
assert lib.elem "postgresql.service" main.systemd.services.rustdesk-api.requires;
assert lib.elem "postgresql-setup.service" main.systemd.services.rustdesk-api.requires;
assert lib.elem main.services.postgresql.package main.systemd.services.rustdesk-api.path;
assert lib.elem "admin-password:${main.sops.secrets.password.path}"
  main.systemd.services.rustdesk-api.serviceConfig.LoadCredential;
assert main.sops.secrets.password.sopsFile == main.sops-file.get "common.yaml";
assert lib.hasInfix "runtime.py" main.systemd.services.rustdesk-api.serviceConfig.ExecStartPre;
assert lib.hasInfix " admin" main.systemd.services.rustdesk-api.serviceConfig.ExecStartPre;
assert lib.hasInfix "RUSTDESK_API_RUSTDESK_ID_SERVER=rustdesk.dora.im:21116" (
  builtins.readFile main.systemd.services.rustdesk-api.serviceConfig.ExecStart
);
assert main.systemd.services.rustdesk-api.environment.PGDATABASE == "rustdesk";
assert main.systemd.services.rustdesk-api.environment.PGHOST == "127.0.0.1";
assert !(main.systemd.services.rustdesk-api.unitConfig ? ConditionPathExists);
assert !(main.systemd.services ? rustdesk-api-migrate-postgresql);
assert lib.all (
  name: (config name).systemd.services.rustdesk-relay.environment.LIMIT_SPEED == "128"
) names;
assert !builtins.elem 21119 sjc.networking.firewall.allowedTCPPorts;
assert cu.services.dn42.natTPort == 50568;
assert cu.services.easytierMesh.protocols.ws.port == 50567;
assert !lib.any (mapping: mapping.listenPort == 50566) cu.services.kernel-relay.mappings;
pkgs.runCommand "rustdesk-cluster-test"
  {
    nativeBuildInputs = [
      python
      server
      api
      main.services.postgresql.package
    ];
    passthru.rules = lib.genAttrs names (
      name: (config name).networking.nftables.tables.rustdesk-ports.content
    );
  }
  ''
    cp -r ${../nixos/modules/services/rustdesk-server} rustdesk
    chmod -R u+w rustdesk
    bash -n ${main.systemd.services.rustdesk-api.serviceConfig.ExecStart}
    python3 -B rustdesk/test-runtime.py -v
    python3 -B rustdesk/test-services.py
    RUSTDESK_API_BIN=${api}/bin/rustdesk-api \
      RUSTDESK_API_RESOURCES=${api}/libexec/rustdesk-api/resources \
      RUSTDESK_ADMIN_SYNC=rustdesk/runtime.py \
      python3 -B rustdesk/api-smoke.py
    touch "$out"
  ''
