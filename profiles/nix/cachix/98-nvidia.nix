{ config, lib, ... }:

lib.mkIf (config.environment.China.enable) {
  nix = {
    settings.substituters = [ "cuda-maintainers.cachix.org" ];
    settings.trusted-public-keys = [
      "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
    ];
  };
}
