{
  pkgs,
  lib,
  ...
}:
lib.mkMerge [
  {
    virtualisation.podman = {
      enable = true;
      dockerCompat = true;
      autoPrune.enable = true;
      defaultNetwork.settings = {
        network_interface = "podman0";
        dns_enabled = true;
      };
    };
    virtualisation.oci-containers.backend = "podman";
  }
  {
    networking.firewall = {
  # 信任 Podman 的虛擬網卡介面
  trustedInterfaces = [ "podman0" ];

  # 如果你使用的是 Rootless 模式，或者自定義了 Podman 網絡，
  # 建議直接放行 Podman 的常用網段（例如 10.88.0.0/16 或 10.89.0.0/16）：
  # extraCommands = ''
  #   iptables -A INPUT -s 10.88.0.0/13 -j ACCEPT
  # '';
};
    environment.systemPackages = with pkgs; [
      podman-compose
      distrobox
    ];
    environment.global-persistence.user = {
      directories = [
        ".local/share/containers"
      ];
    };
  }
]
