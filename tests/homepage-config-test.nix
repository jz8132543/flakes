{ pkgs, configurations }:
let
  inherit (pkgs) lib;
  results = lib.genAttrs [ "arx8" "surface" ] (
    name:
    let
      cfg = configurations.${name}.config;
      homepage = cfg.services.homepage-dashboard;
      router = cfg.services.traefik.dynamicConfigOptions.http.routers.homepage;
      dashboard = cfg.services.traefik.dynamicConfigOptions.http.routers.traefik-dashboard;
      tcpConfig = cfg.services.traefik.dynamicConfigOptions.tcp or { };
      fixture =
        (configurations.${name}.extendModules {
          modules = [
            {
              services.traefik.proxies = {
                homepage-test-app = {
                  rule = "Host(`test.${cfg.networking.domain}`)";
                  target = "http://127.0.0.1:12345";
                  homepage = {
                    category = "Test";
                    title = "Test App";
                    widget = {
                      type = "customapi";
                      url = "http://127.0.0.1:12345";
                    };
                  };
                };
                homepage-test-path = {
                  rule = "Host(`${cfg.networking.fqdn}`) && PathPrefix(`/test-app`)";
                  target = "http://127.0.0.1:12346";
                  homepage = {
                    category = "Test";
                    title = "Path App";
                    href = "https://${cfg.networking.fqdn}/test-app/";
                  };
                };
                homepage-test-hidden = {
                  rule = "Host(`hidden.${cfg.networking.domain}`)";
                  target = "http://127.0.0.1:12347";
                  homepage = {
                    enable = false;
                    title = "Hidden App";
                  };
                };
                homepage-test-api = {
                  rule = "Host(`api.${cfg.networking.domain}`)";
                  target = "http://127.0.0.1:12348";
                };
              };
            }
          ];
        }).config;
      cards = lib.concatMap lib.attrValues fixture.services.homepage-dashboard.services;
      flatCards = lib.concatLists cards;
      findCard =
        title: (builtins.head (lib.filter (card: builtins.hasAttr title card) flatCards)).${title};
    in
    assert homepage.enable;
    assert cfg.systemd.services ? homepage-dashboard;
    assert cfg.environment.etc ? "homepage-dashboard/services.yaml";
    assert homepage.listenPort == cfg.ports.homepage;
    assert !homepage.openFirewall;
    assert !(lib.elem cfg.ports.homepage cfg.networking.firewall.allowedTCPPorts);
    assert homepage.allowedHosts != "*";
    assert router.rule == "Host(`${cfg.networking.fqdn}`)";
    assert router.entryPoints == [ "https" ];
    assert router.tls.certResolver == "zerossl";
    assert
      cfg.services.traefik.staticConfigOptions.certificatesResolvers.zerossl.acme.dnsChallenge.provider
      == "cloudflare";
    assert lib.elem "${cfg.networking.fqdn},127.0.0.1,::1" cfg.services.dnsmasq.settings.host-record;
    assert ((tcpConfig.routers or { }) == { } -> !(cfg.services.traefik.dynamicConfigOptions ? tcp));
    assert ((tcpConfig.routers or { }) != { } -> cfg.services.traefik.dynamicConfigOptions ? tcp);
    assert lib.elem cfg.networking.fqdn cfg.networking.hosts."::1";
    assert router.priority < (dashboard.priority or builtins.stringLength dashboard.rule);
    assert cfg.security.acme.certs.main.domain == "*.dora.im";
    assert (
      !(cfg.services.traefik.proxies ? open-webui)
      || cfg.services.traefik.proxies.open-webui.homepage.category == "AI"
    );
    assert (
      !(cfg.services.traefik.proxies ? mihomo-dashboard)
      || cfg.services.traefik.proxies.mihomo-dashboard.homepage.category == "Network"
    );
    assert cfg.services.traefik.proxies.mihomo-dashboard.target == "http://127.0.0.1:9090/ui/";
    assert
      cfg.services.traefik.proxies.mihomo-dashboard.rule == "Host(`mihomo.${cfg.networking.domain}`)";
    assert cfg.services.traefik.proxies.mihomo-dashboard.middlewares == [ "auth" ];
    assert (
      !(cfg.services.traefik.proxies ? strata)
      || (
        cfg.services.traefik.proxies.strata.middlewares == [ "auth" ]
        && cfg.services.traefik.proxies.strata.homepage.category == "AI"
      )
    );
    assert (findCard "Test App").href == "https://test.${cfg.networking.domain}";
    assert (findCard "Test App").widget.type == "customapi";
    assert (findCard "Mihomo Dashboard").href == "http://${cfg.networking.hostName}.ts:9090/ui/";
    assert (findCard "Linyaps").href == "https://store.linyaps.org.cn/";
    assert (
      name != "arx8"
      || (findCard "Paseo").href == "http://${cfg.networking.hostName}.ts:${toString cfg.ports.paseo}"
    );
    assert (
      !(cfg.services.traefik.proxies ? open-webui)
      ||
        (findCard "Open WebUI").href
        == "http://${cfg.networking.hostName}.ts:${toString cfg.ports.open-webui}"
    );
    assert (name != "arx8" || cfg.services.open-webui.host == "0.0.0.0");
    assert (
      name != "arx8"
      ||
        (findCard "llama-swap").href
        == "http://${cfg.networking.hostName}.ts:${toString cfg.services.llama-swap.port}"
    );
    assert (name != "arx8" || cfg.services.llama-swap.listenAddress == "0.0.0.0");
    assert (
      name != "arx8"
      ||
        cfg.systemd.services.llama-swap.serviceConfig.IPAddressAllow == [
          "localhost"
          "100.64.0.0/10"
          "fd7a:115c:a1e0::/48"
        ]
    );
    assert (
      !(cfg.services.keycloak.enable or false) || (findCard "Keycloak").href == "https://sso.dora.im"
    );
    assert (
      !(cfg.services.traefik.proxies ? strata)
      || (findCard "Strata").href == "http://${cfg.networking.hostName}.ts:${toString cfg.ports.strata}"
    );
    assert (
      name != "arx8"
      ||
        cfg.systemd.services.strata.serviceConfig.IPAddressAllow == [
          "localhost"
          "100.64.0.0/10"
          "fd7a:115c:a1e0::/48"
        ]
    );
    assert (findCard "Path App").href == "https://${cfg.networking.fqdn}/test-app/";
    assert
      !lib.any (card: card ? homepage || card ? "Hidden App" || card ? "homepage-test-api") flatCards;
    {
      inherit (homepage) listenPort;
      inherit (router) rule priority;
    }
  );
  keycloakConfig = configurations.fra0.config;
  keycloakTraefik = keycloakConfig.services.traefik;
in
assert builtins.hasAttr "ldaps" keycloakTraefik.staticConfigOptions.entryPoints;
assert
  keycloakTraefik.staticConfigOptions.entryPoints.ldaps.address
  == ":${toString keycloakConfig.ports.ldaps}";
assert
  keycloakTraefik.dynamicConfigOptions.tcp.routers.ldaps.rule
  == "HostSNI(`ldap.${keycloakConfig.networking.domain}`)";
assert keycloakTraefik.dynamicConfigOptions.tcp.routers.ldaps.tls.certResolver == "zerossl";
assert
  !builtins.hasAttr "ldaps" configurations.arx8.config.services.traefik.staticConfigOptions.entryPoints;
assert !(keycloakConfig.ports ? ldap);
pkgs.runCommand "homepage-config-test" { result = builtins.toJSON results; } ''
  printf '%s\n' "$result" > "$out"
''
