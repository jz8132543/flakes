{lib, ...}:
with lib; {
  options.environment.domains = lib.mkOption {
    type = types.listOf types.str;
    default = ["ts.dora.im" "users.dora.im"];
    description = ''
      tailscale search domains.
    '';
  };
}
