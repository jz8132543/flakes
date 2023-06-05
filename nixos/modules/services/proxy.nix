{pkgs, ...}: {
  networking.firewall.allowedTCPPorts = [8443 8444];
  networking.firewall.allowedUDPPorts = [8443 8444];
  systemd.services.sing-box = {
    wantedBy = ["multi-user.target"];
    after = ["network.target" "traefik.service"];
    serviceConfig = {
      DynamicUser = true;
      Restart = "always";
      ExecStart = "${pkgs.sing-box}/bin/sing-box run -c \${CREDENTIALS_DIRECTORY}/config.json";
      LoadCredential = [
        "config.json:/etc/sing-box/config.json"
      ];
    };
  };
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
  environment.persistence."/nix/persist" = {
    directories = [
      "/etc/sing-box"
      # "/etc/xray"
    ];
  };
}
