{
  config,
  pkgs,
  lib,
  ...
}: {
  services.searx = {
    enable = true;
    settings = {
      general.debug = false; # breaks at runtime otherwise, somehow
      search.safe_search = 0;
      search.autocomplete = "qwant";
      search.default_lang = "en_US";
      server.bind_address = "0.0.0.0";
      server.port = config.ports.searx;
      server.secret_key = "87dd9e896bdb3b7cac32fd7f90867f87";
      server.image_proxy = false;
      server.default_locale = "en";
      ui.default_theme = "oscar";
      ui.theme_args.oscar_style = "logicodev-dark";
      engines = lib.mapAttrsToList (name: value:
        {
          inherit name;
        }
        // value) {
        "bitbucket".disabled = false;
        "ccc-tv".disabled = false;
        "ddg definitions".disabled = false;
        "erowid".disabled = false;
        "duckduckgo".disabled = false;
        "duckduckgo images".disabled = false;
        "fdroid".disabled = false;
        "gitlab".disabled = false;
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
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      searx = {
        rule = "Host(`searx.${config.networking.domain}`)";
        entryPoints = ["https"];
        service = "searx";
      };
    };
    services = {
      searx.loadBalancer = {
        passHostHeader = true;
        servers = [{url = "http://localhost:${toString config.ports.searx}";}];
      };
    };
  };
}
