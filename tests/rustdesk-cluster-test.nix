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
assert !(services "cu").signal.enable;
assert !(services "fra0").relay.enable;
assert (services "cu").relay.enable;
assert lib.all (name: !(services name).openFirewall) names;
assert (services "fra0").cluster.role == "signal";
assert (services "cu").cluster.role == "relay";
assert (services "fra0").cluster.relayHosts == [ "cu.dora.im:50566" ];
assert (services "fra0").signal.relayHosts == [ "cu.dora.im:50566" ];
assert (services "cu").cluster.relayPort == 50566;
assert (services "fra0").cluster.api.enable;
assert !(services "cu").cluster.api.enable;
assert main.sops.secrets."rustdesk/server_private_key".key == "rustdesk/server_private_key";
assert !(cu.sops.secrets ? "rustdesk/server_private_key");
assert lib.all
  (secret: secret.sopsFile == main.sops-file.get "common.yaml" && !secret.terraformOutput.enable)
  [
    privateKey
    apiJwt
  ];
assert privateKey.key == "rustdesk/server_private_key";
assert privateKey.sopsFile == main.sops-file.get "common.yaml";
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
  && (
    !host.services.rustdesk-server.cluster.relay.enable
    ||
      host.systemd.services.rustdesk-relay.serviceConfig.LoadCredential == [ "public-key:${secret.path}" ]
  )
  && !lib.hasInfix "rustdesk" host.sops.terraformTemplate
) names;
assert lib.all (name: (services name).package == server) names;
assert lib.elem "private-key:${
  main.sops.secrets."rustdesk/server_private_key".path
}" main.systemd.services.rustdesk-signal.serviceConfig.LoadCredential;
assert lib.elem "api-jwt:${
  main.sops.secrets."rustdesk/api_jwt_key".path
}" main.systemd.services.rustdesk-signal.serviceConfig.LoadCredential;
assert lib.elem 21116 main.networking.firewall.allowedTCPPorts;
assert lib.elem 21116 main.networking.firewall.allowedUDPPorts;
assert !(lib.elem 21116 cu.networking.firewall.allowedTCPPorts);
assert !(lib.elem 21116 cu.networking.firewall.allowedUDPPorts);
assert lib.hasInfix "fib daddr type local tcp dport 50566 redirect to :21117"
  cu.networking.nftables.tables.rustdesk-ports.content;
assert !(cu.systemd.services ? rustdesk-signal);
assert !(main.systemd.services ? rustdesk-relay);
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
assert lib.elem "rustdesk-signal.service" main.systemd.services.rustdesk-api.requires;
assert lib.elem main.services.postgresql.package main.systemd.services.rustdesk-api.path;
assert lib.elem "admin-password:${main.sops.secrets.password.path}"
  main.systemd.services.rustdesk-api.serviceConfig.LoadCredential;
assert main.sops.secrets.password.sopsFile == main.sops-file.get "common.yaml";
assert lib.hasInfix "runtime.py" main.systemd.services.rustdesk-api.serviceConfig.ExecStartPre;
assert lib.hasInfix " admin" main.systemd.services.rustdesk-api.serviceConfig.ExecStartPre;
assert lib.hasInfix "rustdesk.dora.im:21116" (
  builtins.readFile main.systemd.services.rustdesk-api.serviceConfig.ExecStart
);
assert main.systemd.services.rustdesk-api.environment.PGDATABASE == "rustdesk";
assert main.systemd.services.rustdesk-api.environment.PGHOST == "127.0.0.1";
assert !(main.systemd.services.rustdesk-api.unitConfig ? ConditionPathExists);
assert !(main.systemd.services ? rustdesk-api-migrate-postgresql);
assert !(main.systemd.services ? rustdesk-relay);
assert cu.systemd.services.rustdesk-relay.environment.LIMIT_SPEED == "128";
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
