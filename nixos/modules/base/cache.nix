{
  ...
}:
{
  nix.settings = {
    # 适当放宽重试次数，防止跨境短暂网络抖动导致 Nix 误判二进制缓存不可用而 fallback 到本地编译
    download-attempts = 3;

    substituters = [
      "https://cache.nixos.org"
      "https://cache.lix.systems"
      "https://nix-community.cachix.org"
      "https://surface.cachix.org"
      "https://chaotic-nyx.cachix.org"
      "https://ezkea.cachix.org"
      "https://nix-gaming.cachix.org"
      "https://linyinfeng.cachix.org"
      "https://cache.dora.im?priority=100"
    ];
    max-substitution-jobs = 128;
    http-connections = 128;
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "cache.lix.systems:aBnZUw8zA7H35Cz2RyKFVs3H4PlGTLawyY5KRbvJR8o="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "surface.cachix.org-1:7Oto7CH99nJ40NI6I7Fz6YVfH46R0yUvXJvM56Y0lW4="
      "chaotic-nyx.cachix.org-1:HfnXSw4pj95iI/nAj72MWULnvBYcPk/NY9spUZOQBqI="
      "ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI="
      "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
      "linyinfeng.cachix.org-1:sPYcLBycxOwXzS95VdgE+TrUYMO8WOHUmrwI2gvaSg0="
      "cache.dora.im:nKFQ0OlJFn2vgvnFkP2yps+ju5NypzeojrmbHEGzZ64="
    ];
  };
}
