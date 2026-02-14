{
  config,
  pkgs,
  ...
}:
{
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      doraim = {
        rule = "Host(`mta-sts.dora.im`) || (Host(`dora.im`) && PathPrefix(`/.well-known`))";
        entryPoints = [ "https" ];
        service = "doraim";
        priority = 100;
      };
    };
    services = {
      doraim.loadBalancer = {
        passHostHeader = true;
        servers = [ { url = "http://localhost:${toString config.ports.nginx}"; } ];
      };
    };
  };

  services.nginx = {
    enable = true;
    defaultHTTPListenPort = config.ports.nginx;
    virtualHosts."dora.im" = {
      # matrix
      locations."/.well-known/matrix/server".extraConfig = ''
        default_type application/json;
        return 200 '{ "m.server": "m.dora.im:443" }';
      '';
      locations."/.well-known/matrix/client".extraConfig = ''
        add_header Access-Control-Allow-Origin '*';
        default_type application/json;
        return 200 '{ "m.homeserver": { "base_url": "https://m.dora.im" } }';
      '';
      # mastodon
      locations."/.well-known/host-meta".extraConfig = ''
        return 301 https://zone.dora.im$request_uri;
      '';
      locations."/.well-known/webfinger".extraConfig = ''
        return 301 https://zone.dora.im$request_uri;
      '';
      locations."=/.well-known/autoconfig/mail/config-v1.1.xml".alias =
        pkgs.writeText "config-v1.1.xml" ''
          <?xml version="1.0" encoding="UTF-8"?>

          <clientConfig version="1.1">
            <emailProvider id="dora.im">
              <domain>dora.im</domain>
              <displayName>Doraemon Mail</displayName>
              <displayShortName>Doraemon</displayShortName>
              <incomingServer type="imap">
                <hostname>glacier.mxrouting.net</hostname>
                <port>993</port>
                <socketType>SSL</socketType>
                <authentication>password-cleartext</authentication>
                <username>%EMAILADDRESS%</username>
              </incomingServer>
              <outgoingServer type="smtp">
                <hostname>glacier.mxrouting.net</hostname>
                <port>465</port>
                <socketType>SSL</socketType>
                <authentication>password-cleartext</authentication>
                <username>%EMAILADDRESS%</username>
              </outgoingServer>
            </emailProvider>
          </clientConfig>
        '';
    };
    virtualHosts."mta-sts.dora.im".locations."=/.well-known/mta-sts.txt".alias =
      pkgs.writeText "mta-sts.txt" ''
        version: STSv1
        mode: enforce
        mx: *.dora.im
        mx: *.mxrouting.net
        max_age: 86400
      '';
  };
  # KMS
  networking.firewall.allowedTCPPorts = [ 1688 ];
  systemd.services.vlmcsd = {
    description = "vlmcsd server";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      # Type = "forking";
      Restart = "always";
      RestartSec = "3";
      ExecStart = "${pkgs.nur.repos.linyinfeng.vlmcsd}/bin/vlmcsd -D -v";
      DynamicUser = true;
    };
  };
}
