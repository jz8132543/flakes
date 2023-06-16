{
  pkgs,
  lib,
  config,
  ...
}:
with lib; let
  wrapFile = name: path: (pkgs.runCommand name {inherit path;} ''
    cp -r "$path" "$out"
  '');
in {
  astral.custom-nginx-errors.virtualHosts = ["fedi.astrid.tech"];

  services.akkoma = {
    enable = true;
    extraStatic = {
      "static/terms-of-service.html" =
        wrapFile "terms-of-service.html" ./terms-of-service.html;
      "favicon.png" = wrapFile "favicon.png" ./favicon.png;
      "robots.txt" = wrapFile "robots.txt" ./robots.txt;
    };

    frontends = {
      primary = {
        package = patched-akkoma-fe;
        name = "akkoma-fe";
        ref = "stable";
      };
      admin = {
        package = pkgs.akkoma-frontends.admin-fe;
        name = "admin-fe";
        ref = "stable";
      };
    };

    config = let
      inherit ((pkgs.formats.elixirConf {}).lib) mkRaw mkMap;
    in {
      # ":pleroma"."Pleroma.Web.Endpoint".url.host = "zone.${config.networking.domain}";
      ":pleroma"."Pleroma.Web.Endpoint".http.ip = "localhost";
      ":pleroma".":media_proxy".enabled = false;
      ":pleroma".":instance" = {
        name = "Akkoma";
        description = "Doraemon's akkoma server";
        email = "i@dora.im";
        notify_email = "i@dora.im";

        registrations_open = false;
        invites_enabled = true;

        limit = 69420;
        remote_limit = 100000;
        max_pinned_statuses = 10;
        max_account_fields = 100;

        limit_to_local_content = mkRaw ":unauthenticated";
        healthcheck = true;
        cleanup_attachments = true;
        allow_relay = true;
      };
      ":pleroma".":mrf" = {
        policies = map mkRaw ["Pleroma.Web.ActivityPub.MRF.SimplePolicy"];
        transparency = false;
      };

      ":pleroma"."Pleroma.Repo" = {
        adapter = mkRaw "Ecto.Adapters.Postgres";
        hostname = "postgres.dora.im";
        username = "pleroma";
        database = "pleroma";

        prepare = mkRaw ":named";
        parameters.plan_cache_mode = "force_custom_plan";
      };

      # S3 setup
      ":pleroma"."Pleroma.Upload" = {
        uploader = mkRaw "Pleroma.Uploaders.S3";
        proxy_remote = true;
      };
      ":pleroma"."Pleroma.Uploaders.S3".bucket = config.lib.self.data.pleroma.media.name;
      ":ex_aws".":s3" = {
        access_key_id._secret = config.sops.secrets."b2_pleroma_media_key_id".path;
        secret_access_key._secret = config.sops.secrets."b2_pleroma_media_access_key".path;
        host = config.lib.self.data.pleroma.media.host;
      };

      # Automated moderation settings
      # Borrowed from https://github.com/chaossocial/about/blob/master/blocked_instances.md
      ":pleroma".":mrf_simple" = {
        media_nsfw = mkMap blocklist.media_nsfw;
        reject = mkMap blocklist.reject;
        followers_only = mkMap blocklist.followers_only;
      };

      # Less outgoing retries to improve performance
      ":pleroma".":workers".retries = {
        federator_incoming = 5;
        federator_outgoing = 2;
      };

      # Biggify the pools and pray it works
      ":connections_pool".":max_connections" = 500;
      ":pleroma".":http".pool_size = 150;
      ":pools".":federation".max_connections = 300;
    };
  };

  # Auto-prune objects in the database.
  systemd.timers.akkoma-prune-objects = {
    wantedBy = ["multi-user.service"];
    timerConfig.OnCalendar = "*-*-* 00:00:00";
  };
  systemd.services.akkoma-prune-objects = {
    requisite = ["akkoma.service"];
    path = with pkgs; [akkoma];
    script = ''
      pleroma_ctl database prune_objects
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "akkoma";
    };
  };

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      akkoma = {
        rule = "Host(`zone.dora.im`)";
        entryPoints = ["https"];
        service = "akkoma";
      };
    };
    services = {
      akkoma.loadBalancer = {
        passHostHeader = true;
        servers = [{url = "http://localhost:${toString config.ports.vaultwarden-http}";}];
      };
    };
  };
}
