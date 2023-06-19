{pkgs, ...}: {
  systemd.services.tuic = {
    wantedBy = ["multi-user.target"];
    after = ["network.target"];
    description = "tuic daemon";

    serviceConfig = {
      DynamicUser = true;
      Restart = "always";
      Type = "simple";
      ExecStart = "${pkgs.tuic}/bin/tuic-client -c /etc/tuic/config.json";
      AmbientCapabilities = ["CAP_NET_ADMIN" "CAP_NET_BIND_SERVICE"];
    };
  };
  environment.global-persistence = {
    directories = [
      "/etc/tuic"
    ];
  };
}
