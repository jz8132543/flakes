{lib, ...}:
with lib; {
  options.environment.isCN = lib.mkOption {
    type = types.bool;
    default = false;
    description = ''
      Whether to enable CN mode.
    '';
  };
}
