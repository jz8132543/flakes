{ ... }:
{
  systemd.services.nix-daemon.environment = {
    all_proxy = "socks5://127.0.0.1:1080";
    http_proxy = "socks5://127.0.0.1:1080";
    https_proxy = "socks5://127.0.0.1:1080";
  };
}

