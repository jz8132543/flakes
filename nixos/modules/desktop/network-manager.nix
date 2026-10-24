{
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    iw
    iwd
  ];

  networking.networkmanager = {
    enable = true;
    wifi.powersave = false;
    dns = "none";

    # 黑名单排除专网与虚拟隧道网卡：NetworkManager 坚决不纳管、不轮询、不等待它们
    # 彻底杜绝 strongswan / DN42 / Tailscale 等自管网卡被 NetworkManager 错误干预或导致 wait-online 挂起 60 秒
    unmanaged = [
      "interface-name:dn42*"
      "interface-name:xfrm*"
      "interface-name:Meta"
      "interface-name:tailscale*"
      "interface-name:easytier*"
    ];
  };

  # services.dnscrypt-proxy.enable = true;
  environment.global-persistence.directories = [
    "/etc/NetworkManager/system-connections"
    "/var/lib/NetworkManager"
  ];
}
