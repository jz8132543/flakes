{
  lib,
  buildGoModule,
  fetchFromGitHub,
  nettools,
}:
buildGoModule rec {
  pname = "trafficcontrol";
  version = "8.0.2";

  src = fetchFromGitHub {
    owner = "apache";
    repo = "trafficcontrol";
    rev = "v${version}";
    sha256 = "1xcfd9g6zd9yli73pxsy98qdnilxpiwp5ar6hakyavjykg6kcpl6";
  };

  # Upstream source vendor/ tree is incomplete, fetch dependencies via Go modules
  vendorHash = "sha256-dNz602E8BNUGy6gWNvzGUjkyG9MncHukBhDVhq8psNk=";
  deleteVendor = true;

  postPatch = ''
    substituteInPlace traffic_monitor/config/staticappdata.go \
      --replace-fail 'exec.Command("/bin/hostname", "-s")' \
      'exec.Command("${nettools}/bin/hostname", "-s")'

    substituteInPlace traffic_ops/traffic_ops_golang/dbhelpers/db_helpers.go \
      --replace-fail 'AND ds.active = $2' \
      "AND ds.active = (\$2)::ds_active_state"

    substituteInPlace traffic_ops/traffic_ops_golang/monitoring/monitoring.go \
      --replace-fail "WHERE ds.active = 'ACTIVE'" \
      "WHERE ds.active = 'ACTIVE'::ds_active_state"

    # t3c only reads CDN SSL key metadata. Upstream marks this GET endpoint
    # Admin-only, which prevents the dedicated read-only edge sync account
    # from generating normal cache configuration.
    substituteInPlace traffic_ops/traffic_ops_golang/routing/routes.go \
      --replace-fail 'Path: `cdns/name/{name}/sslkeys/?$`, Handler: cdn.GetSSLKeys, RequiredPrivLevel: auth.PrivLevelAdmin' \
      'Path: `cdns/name/{name}/sslkeys/?$`, Handler: cdn.GetSSLKeys, RequiredPrivLevel: auth.PrivLevelReadOnly' \
      --replace-fail 'Path: `servers/{id-or-name}/update$`, Handler: server.UpdateHandlerV4, RequiredPrivLevel: auth.PrivLevelOperations, RequiredPermissions: []string{"SERVER:UPDATE", "SERVER:READ"}' \
      'Path: `servers/{id-or-name}/update$`, Handler: server.UpdateHandlerV4, RequiredPrivLevel: auth.PrivLevelReadOnly, RequiredPermissions: []string{"SERVER:READ"}'

    # When Traffic Vault is not configured, return an empty array instead of 500
    # so edge t3c sync can generate CDN cache configurations smoothly without error.
    substituteInPlace traffic_ops/traffic_ops_golang/cdn/sslkeys.go \
      --replace-fail 'api.HandleErr(w, r, inf.Tx.Tx, http.StatusInternalServerError, nil, errors.New("getting CDN SSL keys from Traffic Vault: Traffic Vault is not configured"))' \
      'api.WriteResp(w, r, []interface{}{})'

    # Support NixOS systemd and dynamic paths instead of hardcoded FHS paths
    substituteInPlace cache-config/t3c-apply/util/util.go \
      --replace-fail '"/usr/sbin/service"' '"service"'

    substituteInPlace cache-config/t3c-apply/t3c-apply.go \
      --replace-fail '"/usr/bin/touch"' '"touch"'

    substituteInPlace cache-config/t3c-check-refs/config/config.go \
      --replace-fail 'defaultATSPluginDir = "/opt/trafficserver/libexec/trafficserver"' 'defaultATSPluginDir = "/var/lib/trafficserver/libexec"' \
      --replace-fail 'defaultATSConfigDir = "/opt/trafficserver/etc/trafficserver"' 'defaultATSConfigDir = "/var/lib/trafficserver/etc"'

    # Treat packages as installed on NixOS (bypassing non-existent rpm -q checks)
    substituteInPlace cache-config/t3c-apply/torequest/torequest.go \
      --replace-fail 'func (r *TrafficOpsReq) IsPackageInstalled(name string) bool {' \
                     'func (r *TrafficOpsReq) IsPackageInstalled(name string) bool { return true; '
  '';

  subPackages = [
    "cache-config/t3c"
    "cache-config/t3c-apply"
    "cache-config/t3c-check"
    "cache-config/t3c-check-refs"
    "cache-config/t3c-check-reload"
    "cache-config/t3c-diff"
    "cache-config/t3c-generate"
    "cache-config/t3c-preprocess"
    "cache-config/t3c-request"
    "cache-config/t3c-tail"
    "cache-config/t3c-update"
    "traffic_ops/traffic_ops_golang"
    "traffic_monitor"
  ];

  ldflags = [
    "-X main.Version=${version}"
    "-s"
    "-w"
  ];

  outputs = [
    "out"
    "t3c"
  ];

  postInstall = ''
    # Ensure t3c binary exists
    if [ ! -f "$out/bin/t3c" ]; then
      echo "Error: t3c binary not found in $out/bin" >&2
      exit 1
    fi

    # Support traffic_control/install_dir/bin/t3c path expectation
    mkdir -p "$out/traffic_control/install_dir/bin"
    ln -sf "$out/bin/t3c" "$out/traffic_control/install_dir/bin/t3c"

    # Export lightweight t3c output containing only edge t3c client binaries
    mkdir -p "$t3c/bin"
    cp -a "$out/bin"/t3c* "$t3c/bin/"

    # Install Traffic Ops database initialization schemas
    mkdir -p "$out/share/traffic_ops/db"
    cp -a traffic_ops/app/db/create_tables.sql traffic_ops/app/db/seeds.sql traffic_ops/app/db/patches.sql "$out/share/traffic_ops/db/"
    mkdir -p "$out/share/traffic_ops/db/migrations"
    cp -a traffic_ops/app/db/migrations/. "$out/share/traffic_ops/db/migrations/"

    mkdir -p "$out/share/traffic_ops/app/conf"
    cp -a traffic_ops/app/conf/invalid_passwords.txt "$out/share/traffic_ops/app/conf/"

    mkdir -p "$out/share/traffic_monitor/static"
    cp -a traffic_monitor/static/. "$out/share/traffic_monitor/static/"
  '';

  passthru = {
    inherit version;
  };

  doCheck = false;

  meta = with lib; {
    description = "Apache Traffic Control - Open source CDN management suite (t3c, Traffic Ops, Traffic Monitor)";
    homepage = "https://trafficcontrol.apache.org/";
    license = licenses.asl20;
    platforms = platforms.linux;
  };
}
