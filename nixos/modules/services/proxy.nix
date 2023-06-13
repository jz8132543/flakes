{pkgs, ...}: {
  networking.firewall.allowedTCPPorts = [8443 8444];
  networking.firewall.allowedUDPPorts = [8443 8444];
  systemd.services.sing-box = {
    wantedBy = ["multi-user.target"];
    after = ["network.target" "traefik.service"];
    serviceConfig = {
      DynamicUser = true;
      Restart = "always";
      ExecStart = "${pkgs.sing-box}/bin/sing-box run -C /etc/sing-box";
    };
  };
  environment.etc."sing-box/geoip.db".source = "${pkgs.sing-geoip}/share/sing-box/geoip.db";
  environment.etc."sing-box/geosite.db".source = "${pkgs.sing-geosite}/share/sing-box/geosite.db";
  # systemd.services.xray = {
  #   description = "xray Daemon";
  #   after = ["network.target"];
  #   wantedBy = ["multi-user.target"];
  #   serviceConfig = {
  #     DynamicUser = true;
  #     LoadCredential = ["config.json:/etc/xray/config.json"];
  #     ExecStart = "${pkgs.xray}/bin/xray -config \${CREDENTIALS_DIRECTORY}/config.json";
  #   };
  # };
  environment.global-persistence = {
    directories = [
      "/etc/sing-box"
      # "/etc/xray"
    ];
  };
}
