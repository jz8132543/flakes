{ ... }:
{
  nix.settings.substituters = [
    "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
    "https://mirrors.bfsu.edu.cn/nix-channels/store"
    "https://mirrors.ustc.edu.cn/nix-channels/store"

    "https://cache.nixos.org/"
  ];
  systemd.services.nix-daemon.environment = {
    all_proxy = "socks5://127.0.0.1:1080";
    http_proxy = "socks5://127.0.0.1:1080";
    https_proxy = "socks5://127.0.0.1:1080";
  };

}
