{
  ...
}:
{
  nix.settings = {
    # 减少重试次数
    download-attempts = 1;
    # 降低连接超时时间（秒）
    connect-timeout = 5;
    # 降低下载过程中卡住的等待时间（秒）
    stalled-download-timeout = 30;

    substituters = [
      "https://cache.nixos.org"
      "https://cache.lix.systems"
      "https://nix-community.cachix.org"
      "https://surface.cachix.org"
      "https://cache.dora.im?priority=100"
    ];
    max-substitution-jobs = 128;
    http-connections = 128;
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "cache.lix.systems:aBnZUw8zA7H35Cz2RyKFVs3H4PlGTLawyY5KRbvJR8o="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "surface.cachix.org-1:7Oto7CH99nJ40NI6I7Fz6YVfH46R0yUvXJvM56Y0lW4="
      "cache.dora.im:nKFQ0OlJFn2vgvnFkP2yps+ju5NypzeojrmbHEGzZ64="
    ];
  };
}
