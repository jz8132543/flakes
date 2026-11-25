{
  config,
  lib,
  nixosModules,
  options,
  ...
}:
let
  proxyServices = lib.filterAttrs (
    name: proxy:
    name != "homepage"
    && proxy.homepage.enable
    && proxy.homepage.category != null
    && (lib.hasInfix "Host(`" proxy.rule)
    && (!(lib.hasInfix "Path" proxy.rule) || proxy.homepage.href != null)
  ) config.services.traefik.proxies;

  hostFromRule =
    rule:
    let
      fragments = lib.splitString "Host(`" rule;
      candidate = if builtins.length fragments > 1 then builtins.elemAt fragments 1 else "";
    in
    builtins.head (lib.splitString "`)" candidate);

  homepageCard =
    name: proxy:
    let
      metadata = proxy.homepage;
      host = hostFromRule proxy.rule;
      card = {
        href = if metadata.href != null then metadata.href else "https://${host}";
        inherit (metadata) icon;
        inherit (metadata) description;
      }
      // lib.optionalAttrs (metadata.widget != null) {
        inherit (metadata) widget;
      };
    in
    {
      ${
        if metadata.title != null then metadata.title else lib.replaceStrings [ "-" "_" ] [ " " " " ] name
      } =
        lib.filterAttrs (_: value: value != null) card;
    };

  categories = lib.unique (lib.mapAttrsToList (_: proxy: proxy.homepage.category) proxyServices);
  homepageServices = map (category: {
    ${category} =
      lib.mapAttrsToList homepageCard (
        lib.filterAttrs (_: proxy: proxy.homepage.category == category) proxyServices
      )
      ++ lib.optionals (category == "AI" && options.services ? paseo && config.services.paseo.enable) [
        {
          Paseo = {
            href = "http://127.0.0.1:${toString config.ports.paseo}";
            icon = "si-codeium";
            description = "Local AI agent workbench";
          };
        }
      ];
  }) categories;

  headscaleCard = {
    Tailscale = {
      href = "https://ts.${config.networking.domain}";
      icon = "tailscale.png";
      description = "Tailscale network management";
    };
  };
in
{
  imports = [ nixosModules.services.traefik ];

  # Local browsers must not follow stale public AAAA records for this laptop.
  networking.hosts."::1" = [ config.networking.fqdn ];
  services.dnsmasq.settings.host-record = [ "${config.networking.fqdn},127.0.0.1,::1" ];

  services.homepage-dashboard = {
    enable = true;
    listenPort = config.ports.homepage;
    allowedHosts = "${config.networking.fqdn},localhost:${toString config.ports.homepage},127.0.0.1:${toString config.ports.homepage}";
    services = homepageServices ++ [ { Network = [ headscaleCard ]; } ];
    widgets = [
      { search.provider = "duckduckgo"; }
      {
        resources = {
          cpu = true;
          disk = "/";
          memory = true;
          uptime = true;
        };
      }
      { datetime.format.timeStyle = "short"; }
    ];
    settings = {
      title = "${config.networking.hostName} Services";
      language = "zh-Hans";
      headerStyle = "clean";
      hideVersion = true;
      layout = lib.genAttrs categories (_: {
        style = "row";
        columns = 3;
      });
    };
  };

  services.traefik.proxies.homepage = {
    rule = "Host(`${config.networking.fqdn}`)";
    target = "http://127.0.0.1:${toString config.ports.homepage}";
    entryPoints = [ "https" ];
    # More specific routes on the same FQDN, such as /dashboard/, must win.
    priority = lib.mkDefault 1;
    homepage.enable = false;
  };
}
