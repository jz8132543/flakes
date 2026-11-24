{
  config,
  lib,
  pkgs,
  ...
}:
let
  enable = config.networking.hostName == "arx8";
in
{
  users.groups.corplink-rs = { };
  users.users.corplink-rs = {
    isSystemUser = true;
    group = "corplink-rs";
    uid = 997;
  };

  environment.systemPackages = [ pkgs.corplink-rs ];

  sops.secrets = lib.mkIf enable {
    "corplink-rs/username".sopsFile = config.sops-file.get "common.yaml";
    "corplink-rs/password".sopsFile = config.sops-file.get "common.yaml";
    "corplink-rs/username".restartUnits = [ "corplink-rs.service" ];
    "corplink-rs/password".restartUnits = [ "corplink-rs.service" ];
  };

  systemd.services.corplink-rs = lib.mkIf enable {
    description = "Nankai University Feilian VPN client";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "mihomo-loop-prevention.service"
      "sops-install-secrets.service"
    ];
    requires = [ "sops-install-secrets.service" ];
    path = [ pkgs.jq ];
    startLimitIntervalSec = 0;
    startLimitBurst = 0;
    restartIfChanged = true;
    serviceConfig = {
      Type = "simple";
      User = "corplink-rs";
      Group = "corplink-rs";
      StateDirectory = "corplink-rs";
      StateDirectoryMode = "0700";
      UMask = "0077";
      LoadCredential = [
        "username:${config.sops.secrets."corplink-rs/username".path}"
        "password:${config.sops.secrets."corplink-rs/password".path}"
      ];
      ExecStartPre = pkgs.writeShellScript "corplink-rs-config" ''
        config=/var/lib/corplink-rs/config.json
        config_tmp="$config.tmp"
        if [ -f "$config" ]; then
          ${pkgs.jq}/bin/jq \
            --rawfile username "$CREDENTIALS_DIRECTORY/username" \
            --rawfile password "$CREDENTIALS_DIRECTORY/password" \
            '. + {username: ($username | rtrimstr("\n")),
                  password: ($password | rtrimstr("\n"))}' \
            "$config" > "$config_tmp"
        else
          ${pkgs.jq}/bin/jq -n \
            --rawfile username "$CREDENTIALS_DIRECTORY/username" \
            --rawfile password "$CREDENTIALS_DIRECTORY/password" \
            '{company_name: "nankai", username: ($username | rtrimstr("\n")),
              password: ($password | rtrimstr("\n")),
              platform: "feilian_v1", route_mode: "split", auto_setup_routes: false,
              socks5_listen: "127.0.0.1:1080", use_vpn_dns: false}' > "$config_tmp"
        fi
        chmod 0600 "$config_tmp"
        mv -f "$config_tmp" "$config"
      '';
      ExecStart = "${lib.getExe pkgs.corplink-rs} /var/lib/corplink-rs/config.json";
      Restart = "on-failure";
      RestartSec = "15s";
      TimeoutStopSec = "20s";
      KillSignal = "SIGINT";
    };
  };

  environment.global-persistence.directories = lib.mkIf enable [ "/var/lib/corplink-rs" ];
}
