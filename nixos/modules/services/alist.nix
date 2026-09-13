{
  PG ? "postgres.mag",
  ...
}:
{
  pkgs,
  config,
  nixosModules,
  ...
}:
{
  imports = [ nixosModules.services.aria2 ];
  users = {
    users.alist = {
      isSystemUser = true;
      createHome = false;
      home = "/var/lib/alist";
      group = "alist";
      description = "alist service";
      extraGroups = [
        "media"
        "video"
        "render"
      ];
    };

    groups.alist = { };
  };
  systemd.tmpfiles.rules = [
    "d '${config.users.users.alist.home}' 0777 alist alist - -"
    "d '${config.users.users.alist.home}/temp' 0777 alist alist - -"
    "d '${config.users.users.alist.home}/temp/aria2' 0777 aria2 aria2 - -"
  ];

  systemd.services.alist = {
    description = "alist service";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      User = "alist";
      Group = "alist";
      Restart = "on-failure";
      ExecStart = "${pkgs.openlist}/bin/OpenList server --data /var/lib/alist";
      AmbientCapabilities = "cap_net_bind_service";
    };
  };

  sops.templates."alist-config" = {
    mode = "0644";
    owner = "alist";
    path = "/var/lib/alist/config.json";
    content = builtins.toJSON {
      site_url = "https://alist.${config.networking.domain}";
      jwt_secret = "${config.sops.placeholder."alist/JWT"}";
      database = {
        type = "postgres";
        host = PG;
        port = 5432;
        user = "alist";
        password = "";
        name = "alist";
        ssl_mode = "prefer";
        db_file = "";
        table_prefix = "x_";
      };
      email = {
        enable = true;
        host = "${config.environment.smtp_host}";
        port = config.environment.smtp_port;
        user = "services@dora.im";
        password = "${config.sops.placeholder."mail/services"}";
        from = "services@dora.im";
      };
    };
  };
  sops.secrets = {
    "alist/JWT" = { };
    "mail/services" = { };
    "password" = { };
  };

  systemd.services.alist-init-dav = {
    description = "Ensure alist dav user password matches sops password";
    after = [
      "alist.service"
      "postgresql.service"
    ];
    wants = [ "alist.service" ];
    wantedBy = [ "multi-user.target" ];
    path = with pkgs; [
      postgresql
      openssl
      coreutils
      gawk
      util-linux
    ];
    script = ''
      pw="$(cat ${config.sops.secrets."password".path})"
      salt="$(runuser -u postgres -- psql -d alist -t -A -c "SELECT salt FROM x_users WHERE username = 'dav';" 2>/dev/null || true)"
      if [ -z "$salt" ]; then
        salt="$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 16)"
        static_hash="$(echo -n "$pw-https://github.com/alist-org/alist" | sha256sum | awk '{print $1}')"
        two_hash="$(echo -n "$static_hash-$salt" | sha256sum | awk '{print $1}')"
        runuser -u postgres -- psql -d alist -c "INSERT INTO x_users (username, pwd_hash, pwd_ts, salt, base_path, role, disabled, permission) VALUES ('dav', '$two_hash', EXTRACT(EPOCH FROM NOW())::bigint, '$salt', '/', 0, false, 1023) ON CONFLICT (username) DO UPDATE SET pwd_hash = EXCLUDED.pwd_hash, salt = EXCLUDED.salt, pwd_ts = EXCLUDED.pwd_ts;"
      else
        static_hash="$(echo -n "$pw-https://github.com/alist-org/alist" | sha256sum | awk '{print $1}')"
        two_hash="$(echo -n "$static_hash-$salt" | sha256sum | awk '{print $1}')"
        runuser -u postgres -- psql -d alist -c "UPDATE x_users SET pwd_hash = '$two_hash', pwd_ts = EXTRACT(EPOCH FROM NOW())::bigint WHERE username = 'dav';"
      fi
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      RemainAfterExit = true;
    };
  };

  services.traefik.proxies.alist = {
    rule = "Host(`alist.${config.networking.domain}`)";
    target = "http://localhost:${toString config.ports.alist}";
  };
}
