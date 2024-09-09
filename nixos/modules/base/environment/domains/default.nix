{lib, ...}:
with lib; {
  options.environment.domains = lib.mkOption {
    type = types.listOf types.str;
    default = ["mag"];
    description = ''
      tailscale search domains.
    '';
  };
}
