{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.environment.networkOmnitt;

  clampFloat =
    lo: hi: value:
    if value < lo then
      lo
    else if value > hi then
      hi
    else
      value;

  toInt = value: builtins.floor value;
  toFloat = value: value * 1.0;

  sqrt =
    value:
    let
      abs = x: if x < 0 then -x else x;
      next = guess: (guess + value / guess) / 2.0;
      loop = guess: if abs (guess * guess - value) < 0.000001 then guess else loop (next guess);
    in
    if value <= 0 then 0 else loop (if value > 1 then value / 2.0 else 1.0);

  bdpBytes = mbps: latencyMs: toInt (((mbps * 1024 * 1024 / 8) * latencyMs) / 1000.0);

  initWindowValues =
    let
      bandwidthRatio = toFloat cfg.bandwith / toFloat cfg.realbandwith;
      bandwidthFactor = clampFloat 1.0 2.0 (1.5 * sqrt bandwidthRatio);
      effectiveBandwidth = lib.min (cfg.bandwith * bandwidthFactor) cfg.realbandwith;
      bdp = bdpBytes effectiveBandwidth cfg.latencyMs;
      packetBudget = toInt (clampFloat 12.0 96.0 ((toFloat bdp / 1460.0) / 48.0 * cfg.rampUpRate));
      initCwnd =
        if cfg.aggressiveMode then lib.max 16 packetBudget else lib.max 10 (toInt (packetBudget / 2));
      initRwnd =
        if cfg.aggressiveMode then
          lib.max initCwnd (toInt (initCwnd * 2))
        else
          lib.max initCwnd (toInt (initCwnd * 3 / 2));
    in
    {
      inherit initCwnd initRwnd;
    };

  initWindows = initWindowValues;
in
{
  imports = [ ../optimize/network-old.nix ];

  config = {
    environment.networkOmnitt.latencyMs = lib.mkDefault 200;
    environment.networkOmnitt.rampUpRate = lib.mkDefault 0.99;

    systemd.services.set-initcwnd = {
      description = "Tune default route initcwnd/initrwnd";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "60s";
      };
      path = [
        pkgs.coreutils
        pkgs.gawk
        pkgs.gnugrep
        pkgs.iproute2
      ];
      script = lib.mkForce ''
        INITCWND=${toString initWindows.initCwnd}
        INITRWND=${toString initWindows.initRwnd}

        TARGET="1.1.1.1"
        GW_INFO=$(ip -4 route get "$TARGET" 2>/dev/null | head -n 1)
        IFACE=$(echo "$GW_INFO" | awk '{for(i=1;i<NF;i++) if($i=="dev") print $(i+1)}')
        [ -z "$IFACE" ] && exit 0

        DEF4=$(ip -4 route show default dev "$IFACE" 2>/dev/null | head -n 1)
        if [ -n "$DEF4" ] && ! echo "$DEF4" | grep -q "initcwnd"; then
          ip route change $DEF4 initcwnd $INITCWND initrwnd $INITRWND || true
        fi

        TARGET6="2606:4700:4700::1111"
        GW6_INFO=$(ip -6 route get "$TARGET6" 2>/dev/null | head -n 1)
        IFACE6=$(echo "$GW6_INFO" | awk '{for(i=1;i<NF;i++) if($i=="dev") print $(i+1)}')
        if [ -n "$IFACE6" ]; then
          DEF6=$(ip -6 route show default dev "$IFACE6" 2>/dev/null | head -n 1)
          [ -n "$DEF6" ] && ! echo "$DEF6" | grep -q "initcwnd" && ip -6 route change $DEF6 initcwnd $INITCWND initrwnd $INITRWND || true
        fi
      '';
    };
  };
}
