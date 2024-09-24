{
  config,
  lib,
  pkgs,
  ...
}:
let
  url = "searx.${config.networking.domain}";
  morty_url = "morty.${config.networking.domain}";
in
{
  sops.secrets."searx/SEARX_SECRET_KEY" = { };
  sops.templates.searx-env.content = ''
    SEARX_SECRET_KEY=${config.sops.placeholder."searx/SEARX_SECRET_KEY"}
  '';
  services.searx = {
    enable = true;
    package = pkgs.searxng;
    environmentFile = config.sops.templates.searx-env.path;
    # services.searx.runInUwsgi = true;
    # services.searx.uwsgiConfig = let
    #   inherit (config.services.searx) settings;
    # in {
    #   socket = "${lib.quoteListenAddr settings.server.bind_address}:${toString settings.server.port}";
    # };
    settings = {
      use_default_settings = true;
      general = {
        debug = false; # breaks at runtime otherwise, somehow
        instance_name = "SearXNG";
        privacypolicy_url = false;
        donation_url = false;
        contact_url = "mailto:i@dora.im";
        enable_metrics = true;
      };
      search = {
        safe_search = 0;
        autocomplete = "google"; # Existing autocomplete backends: "dbpedia", "duckduckgo", "google", "startpage", "swisscows", "qwant", "wikipedia" - leave blank to turn it off by default
        default_lang = "zh-CN";
        formats = [
          "html"
          "json"
        ];
      };
      server = {
        base_url = "https://${url}";
        bind_address = "::1";
        port = config.ports.searx;
        secret_key = "@SEARX_SECRET_KEY@";
        image_proxy = true;
        default_locale = "en";
      };
      outgoing = {
        # request_timeout = 10.0;
        useragent_suffix = "sx";
        pool_connections = 100;
        pool_maxsize = 10;
      };
      result_proxy = {
        url = "https://morty.${config.networking.domain}/";
      };
      engines =
        lib.mapAttrsToList
          (
            name: value:
            {
              inherit name;
            }
            // value
          )
          {
            "bitbucket".disabled = false;
            "ccc-tv".disabled = false;
            "ddg definitions".disabled = false;
            "erowid".disabled = false;
            "duckduckgo".disabled = false;
            "duckduckgo images".disabled = false;
            "fdroid".disabled = false;
            "gitlab".disabled = false;
            "google".disabled = false;
            "google play apps".disabled = false;
            "nyaa".disabled = false;
            "openrepos".disabled = false;
            "qwant".disabled = false;
            "reddit".disabled = false;
            "searchcode code".disabled = false;
            "framalibre".disabled = false;
            "wikibooks".disabled = false;
            "wikinews".disabled = false;
            "wikiquote".disabled = false;
            "wikisource".disabled = false;
            "wiktionary".disabled = false;
          };
    };
  };
  services.morty = {
    enable = true;
    port = config.ports.morty;
    timeout = 10;
  };

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      searx = {
        rule = "Host(`${url}`)";
        entryPoints = [ "https" ];
        service = "searx";
      };
      morty = {
        rule = "Host(`${morty_url}`)";
        entryPoints = [ "https" ];
        service = "morty";
      };
    };
    services = {
      searx.loadBalancer = {
        passHostHeader = true;
        servers = [ { url = "http://localhost:${toString config.ports.searx}"; } ];
      };
      morty.loadBalancer = {
        passHostHeader = true;
        servers = [ { url = "http://localhost:${toString config.ports.morty}"; } ];
      };
    };
  };
}
