{ config, lib, ... }:

let
  domain = "dora.im";
  netbirdDomain = "ts.${domain}";
  clientId = "oqIs4P6rDTNzr1q7gFiaMuvZsil8XIQ3JhyBCKUE";
in
{
  services.netbird = {
    enable = true;

    server = {
      enableNginx = lib.mkForce true;
      domain = netbirdDomain;
      management = {
        enable = true;
        # metricsPort = cfg.server.metrics-port;
        # port = cfg.server.management-port;
        enableNginx = lib.mkForce true;
        oidcConfigEndpoint = "https://sso.${domain}/application/o/netbird/.well-known/openid-configuration";
        domain = netbirdDomain;
        turnDomain = "turn.${domain}";
        dnsDomain = "dns.${domain}";
        singleAccountModeDomain = domain;

        settings = {
          TURNConfig = {
            Turns = [
              {
                Proto = "udp";
                URI = "turn:turn.${domain}:${toString config.ports.turn-port}";
                Username = "netbird";
                Password._secret = config.sops.secrets."netbird/Password".path;
              }
            ];

            Secret._secret = config.sops.secrets."netbird/Password".path;
          };

          DataStoreEncryptionKey = null;
          # TODO: Change to Postgres
          # StoreConfig = { Engine = "sqlite"; };

          HttpConfig = {
            AuthAudience = clientId;
            AuthUserIDClaim = "sub";
            AuthIssuer = "https://sso.${domain}/application/o/netbird/";
            AuthKeysLocation = "https://sso.${domain}/application/o/netbird/jwks/";
          };

          IdpManagerConfig = {
            ManagerType = "authentik";
            ClientConfig = {
              Issuer = "https://sso.${domain}/application/o/netbird/";
              ClientID = clientId;
              TokenEndpoint = "https://sso.${domain}/application/o/token/";
              ClientSecret = "";
            };
            ExtraConfig = {
              Password._secret = config.sops.secrets."netbird/IDPPassword".path;
              Username = "netbird";
            };
          };
          PKCEAuthorizationFlow.ProviderConfig = {
            Audience = clientId;
            ClientID = clientId;
            ClientSecret = "";
            Scope = "openid profile email offline_access api";
            AuthorizationEndpoint = "https://sso.${domain}/application/o/authorize/";
            TokenEndpoint = "https://sso.${domain}/application/o/token/";
            RedirectURLs = [
              "https://${netbirdDomain}"
              "http://localhost:53000"
            ];
          };
        };
      };

      signal = {
        enable = true;
        # port = cfg.server.signal-port;
        domain = netbirdDomain;
        enableNginx = lib.mkForce true;
      };

      dashboard = {
        enable = true;
        enableNginx = true;
        domain = netbirdDomain;
        managementServer = "https://${netbirdDomain}";
        settings = {
          AUTH_AUTHORITY = "https://sso.${domain}/application/o/netbird/";
          AUTH_SUPPORTED_SCOPES = "openid profile email offline_access api";
          AUTH_AUDIENCE = clientId;
          AUTH_CLIENT_ID = clientId;
          USE_AUTH0 = "false";
        };
      };

      coturn = {
        enable = true;
        passwordFile = config.sops.secrets."netbird/Password".path;
        domain = netbirdDomain;
      };
    };
  };
  sops.secrets = {
    "netbird/Password" = { };
    "netbird/IDPPassword" = { };
  };
  # Make the env available to the systemd service
  systemd.services.netbird-management.serviceConfig = {
    EnvironmentFile = config.sops.templates."netbird-env".path;
  };
  sops.templates."netbird-env".content = ''
    # NETBIRD_AUTH_OIDC_CONFIGURATION_ENDPOINT="https://sso.dora.im/application/o/netbird/.well-known/openid-configuration"
    # NETBIRD_USE_AUTH0=false
    # NETBIRD_AUTH_CLIENT_ID="oqIs4P6rDTNzr1q7gFiaMuvZsil8XIQ3JhyBCKUE"
    # NETBIRD_AUTH_SUPPORTED_SCOPES="openid profile email offline_access api"
    # NETBIRD_AUTH_AUDIENCE="oqIs4P6rDTNzr1q7gFiaMuvZsil8XIQ3JhyBCKUE"
    # NETBIRD_AUTH_DEVICE_AUTH_CLIENT_ID="oqIs4P6rDTNzr1q7gFiaMuvZsil8XIQ3JhyBCKUE"
    # NETBIRD_AUTH_DEVICE_AUTH_AUDIENCE="oqIs4P6rDTNzr1q7gFiaMuvZsil8XIQ3JhyBCKUE"
    # NETBIRD_MGMT_IDP="authentik"
    # NETBIRD_IDP_MGMT_CLIENT_ID="oqIs4P6rDTNzr1q7gFiaMuvZsil8XIQ3JhyBCKUE"
    # NETBIRD_IDP_MGMT_EXTRA_USERNAME="netbird"
    # NETBIRD_IDP_MGMT_EXTRA_PASSWORD="dlmZlBnLKFgmNc4qjnb5BoNEvNzsUZHiMjOSltAE316DULRGXB1yKrrzm8es"
    # NETBIRD_AUTH_REDIRECT_URI="/auth"
    # NETBIRD_AUTH_SILENT_REDIRECT_URI="/silent-auth"
    # # needs disabling due to issue with IdP. Learn more at https://github.com/netbirdio/netbird/issues/3654
    # NETBIRD_AUTH_PKCE_DISABLE_PROMPT_LOGIN=true

    # # OIDC 配置端点
    # NETBIRD_AUTH_OIDC_CONFIGURATION_ENDPOINT="https://sso.dora.im/application/o/netbird/.well-known/openid-configuration"
    # NETBIRD_USE_AUTH0=false
    #
    # # Client / Audience
    # NETBIRD_AUTH_CLIENT_ID="netbird"
    # NETBIRD_AUTH_SUPPORTED_SCOPES="openid profile email offline_access api"
    # NETBIRD_AUTH_AUDIENCE="netbird"
    #
    # # 设备授权
    # NETBIRD_AUTH_DEVICE_AUTH_CLIENT_ID="netbird"
    # NETBIRD_AUTH_DEVICE_AUTH_AUDIENCE="netbird"
    #
    # # 回调
    # NETBIRD_AUTH_REDIRECT_URI="/auth"
    # NETBIRD_AUTH_SILENT_REDIRECT_URI="/silent-auth"
    #
    # # 管理端对接 Authentik
    # NETBIRD_MGMT_IDP="authentik"
    # NETBIRD_IDP_MGMT_CLIENT_ID="netbird"
    # NETBIRD_IDP_MGMT_EXTRA_USERNAME="Netbird"
    # NETBIRD_IDP_MGMT_EXTRA_PASSWORD="eA7DvG2ZwWFiOqxXblBgRO1s8SWa45rC5GcpZA3aCxo3d1hyW4M1mfNSxYpaezrhp2vu1u07PvzdYxhRY4ijTOCq5cY3rdG2Q9pMxEGAvnINyoBgVbNYLVnCgHmM7pQT"
    #
    # # 已知问题：禁用 PKCE 的 login 提示（参考 issue #3654）
    # NETBIRD_AUTH_PKCE_DISABLE_PROMPT_LOGIN=true
  '';

  services.traefik.proxies.netbird = {
    rule = "Host(`${netbirdDomain}`)";
    target = "http://${netbirdDomain}:${toString config.ports.nginx}";
  };

  networking.firewall.allowedTCPPorts = [
    80
    443
    3478
    10000
    33080
  ];
  networking.firewall.allowedUDPPorts = [
    3478
    5349
    33080
  ];
  networking.firewall.allowedUDPPortRanges = [
    {
      from = 40000;
      to = 40050;
    }
  ]; # TURN ports
}
