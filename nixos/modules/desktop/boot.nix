{
  config,
  lib,
  ...
}:
{
  # Keep verified boot generations during the experimental desktop rollout.
  nix.gc.automatic = lib.mkForce false;

  boot = {
    # Allow time to select diagnostics, Windows, or an older generation.
    loader.timeout = lib.mkForce 5;
  };

  # no-clone marks children as specialisations; capture only the normal parent's parameters.
  specialisation = lib.mkIf (!config.isSpecialisation) {
    no-animation-diagnostic.configuration = {
      boot = {
        plymouth.enable = lib.mkForce false;
        consoleLogLevel = lib.mkForce 7;
        loader.grub.configurationName = "No animation boot diagnostics";
        kernelParams = lib.mkForce (
          lib.filter (
            param:
            !lib.elem (builtins.head (lib.splitString "=" param)) [
              "quiet"
              "splash"
              "loglevel"
              "panic"
              "plymouth.enable"
              "systemd.show_status"
              "rd.systemd.show_status"
            ]
          ) config.boot.kernelParams
          ++ [
            "panic=0"
            "loglevel=7"
            "plymouth.enable=0"
            "systemd.show_status=1"
            "rd.systemd.show_status=1"
          ]
        );
      };
    };
  };
}
