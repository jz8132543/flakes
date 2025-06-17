{
  ...
}:
{
  pkgs,
  ...
}:
{
  users = {
    users.ebook-sender = {
      isSystemUser = true;
      createHome = false;
      home = "/var/lib/ebook-sender";
      group = "ebook-sender";
      description = "ebook-sender service";
    };

    groups.ebook-sender = { };
  };
  # systemd.tmpfiles.rules = [
  #   "d '${config.users.users.ebook-sender.home}/temp/aria2' 0777 aria2 aria2 - -"
  #   "d '${config.users.users.ebook-sender.home}/' 0777 alist alist - -"
  # ];

  systemd.services.ebook-sender = {
    description = "alist service";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      User = "ebook-sender";
      Group = "ebook-sender";
      Restart = "on-failure";
      ExecStart = "python3 ${pkgs.ebook-sender-bot}/main.py";
      # script = builtins.concatStringsSep " " [
      #   "python3 ${pkgs.ebook-sender-bot}/main.py"
      # ];
      AmbientCapabilities = "cap_net_bind_service";
    };
  };

  #sops.templates."alist-config" = {
  #  mode = "0644";
  #  owner = "alist";
  #  path = "/var/lib/alist/config.json";
  #  content = builtins.toJSON {
  #    site_url = "https://alist.${config.networking.domain}";
  #    jwt_secret = "${config.sops.placeholder."alist/JWT"}";
  #    database = {
  #      type = "postgres";
  #      host = PG;
  #      port = 5432;
  #      user = "alist";
  #      password = "";
  #      name = "alist";
  #      ssl_mode = "prefer";
  #      db_file = "";
  #      table_prefix = "x_";
  #    };
  #  };
  #};
  #sops.secrets."alist/JWT" = { };
}
