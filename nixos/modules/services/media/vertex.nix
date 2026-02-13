{
  config,
  ...
}:
{
  config = {
    sops.templates."vertex-env" = {
      content = ''
        PASSWORD=${config.sops.placeholder.password}
      '';
    };

    virtualisation.oci-containers.containers.vertex = {
      image = "docker://lswl/vertex:latest";
      volumes = [
        "/data/.state/vertex:/vertex"
        "/data/downloads/torrents:/data/downloads/torrents"
      ];
      environment = {
        TZ = "Asia/Shanghai";
        PORT = toString config.ports.vertex;
        BASE_PATH = "/vertex";
        USERNAME = "i";
        HOST = "0.0.0.0";
      };
      environmentFiles = [ config.sops.templates."vertex-env".path ];
      extraOptions = [ "--network=host" ];
    };

    services.nginx.virtualHosts.localhost.locations."/vertex/" = {
      proxyPass = "http://127.0.0.1:${toString config.ports.vertex}/";
      proxyWebsockets = true;
      extraConfig = ''
        gunzip on;
        proxy_set_header Accept-Encoding "";

        sub_filter_types *;
        sub_filter_once off;

        # 1. Inject Base URL to fix Vue Router routing issues (White screen fix)
        sub_filter '<head>' '<head><base href="/vertex/">';

        # 2. Fix Service Worker and Manifest paths (Prevent 404 errors)
        sub_filter '"/service-worker.js"' '"/vertex/service-worker.js"';
        sub_filter "'/service-worker.js'" "'/vertex/service-worker.js'";
        sub_filter '"start_url":"/"' '"scope":"/vertex/","start_url":"/vertex/"';
        sub_filter '"scope":"/"' '"scope":"/vertex/"';

        # 3. Rewrite asset paths
        sub_filter 'src="/assets/' 'src="/vertex/assets/';
        sub_filter 'href="/assets/' 'href="/vertex/assets/';
        sub_filter 'content="/assets/' 'content="/vertex/assets/';
        sub_filter 'url("/assets/' 'url("/vertex/assets/';
        sub_filter '"src": "/assets/' '"src": "/vertex/assets/';
        sub_filter '"/assets/' '"/vertex/assets/';
        sub_filter "'/assets/" "'/vertex/assets/";

        # 4. Inject API Path Rewriter (Monkey Patching fetch/XHR)
        sub_filter '</head>' '<script>(function(){var f=window.fetch;window.fetch=function(u,o){if(typeof u==="string"&&u.startsWith("/api/"))u="/vertex"+u;return f(u,o);};var x=XMLHttpRequest.prototype.open;XMLHttpRequest.prototype.open=function(m,u){if(typeof u==="string"&&u.startsWith("/api/"))u="/vertex"+u;return x.apply(this,arguments);};})();</script></head>';

        proxy_redirect / /vertex/;
        proxy_set_header X-Forwarded-Prefix /vertex;
      '';
    };
    services.nginx.virtualHosts.localhost.locations."/vertex" = {
      return = "301 /vertex/";
    };

    services.traefik.proxies.nixflix-apps-vertex = {
      rule = "(Host(`tv.dora.im`) || Host(`${config.networking.fqdn}`)) && PathPrefix(`/vertex`)";
      target = "http://127.0.0.1:${toString config.ports.nginx}";
    };

    services.restic.backups.borgbase.paths = [
      "/data/.state/vertex/db/sql.db"
    ];
  };
}
