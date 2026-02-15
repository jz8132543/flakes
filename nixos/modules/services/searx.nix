{
  config,
  lib,
  pkgs,
  ...
}:
let
  url = "searx.${config.networking.domain}";
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
        # default_lang = "zh-CN";
        autocomplete = "duckduckgo";
        favicon_resolver = "duckduckgo";
        suspend_on_unavailable = false;
        result_extras = {
          favicon = true; # Enable website icons
          thumbnail = true; # Enable result thumbnails
          thumbnail_proxy = true; # Use a proxy for thumbnails
        };
        formats = [
          "rss"
          "csv"
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
      ui = {
        default_theme = "simple";
        query_in_title = true;
        infinite_scroll = true;
        engine_shortcuts = true; # Show engine icons
        expand_results = true; # Show result thumbnails
        theme_args = {
          style = "auto"; # Supports dark/light mode
        };
      };
      plugins =
        let
          mkPlugin = name: active: { ${name} = { inherit active; }; };
          activePlugins = map (name: mkPlugin name true) [
            "searx.plugins.calculator.SXNGPlugin"
            "searx.plugins.hash_plugin.SXNGPlugin"
            "searx.plugins.self_info.SXNGPlugin"
            "searx.plugins.tracker_url_remover.SXNGPlugin"
            "searx.plugins.unit_converter.SXNGPlugin"
            "searx.plugins.ahmia_filter.SXNGPlugin"
            "searx.plugins.hostnames.SXNGPlugin"
            "searx.plugins.oa_doi_rewrite.SXNGPlugin"
            "searx.plugins.tor_check.SXNGPlugin"
          ];
          inactivePlugins = map (name: mkPlugin name false) [
          ];
        in
        lib.foldr lib.mergeAttrs { } (activePlugins ++ inactivePlugins);
      outgoing = {
        # request_timeout = 10.0;
        useragent_suffix = "sx";
        pool_connections = 100;
        pool_maxsize = 20;
        request_timeout = 10.0;
        max_request_timeout = 15.0;
      };
      engines = [
        {
          name = "bing";
          engine = "bing";
          disabled = false;
          timeout = 6.0;
        }
        {
          name = "brave";
          engine = "brave";
          disabled = false;
          timeout = 6.0;
        }
        {
          name = "google";
          engine = "google";
          disabled = false;
          timeout = 6.0;
        }
        {
          name = "wikipedia";
          engine = "wikipedia";
          disabled = false;
          timeout = 6.0;
        }
        {
          name = "duckduckgo";
          engine = "duckduckgo";
          disabled = false;
          timeout = 6.0;
        }
      ];
      cache = {
        cache_max_age = 1440; # Cache for 24 hours
        cache_disabled_plugins = [ ];
        cache_dir = "/var/cache/searxng";
      };
      privacy = {
        preferences = {
          disable_map_search = true;
          disable_web_search = false;
          disable_image_search = false;
        };
        http_header_anonymization = true;
      };
    };
  };

  services.traefik.proxies.searx = {
    rule = "Host(`${url}`)";
    target = "http://localhost:${toString config.ports.searx}";
  };
}
