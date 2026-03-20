#!/usr/bin/env bash

set -eu

echo "== Before =="
surface-display-auto status || true
echo

has_external="$(
  busctl --user get-property \
    org.gnome.Mutter.DisplayConfig \
    /org/gnome/Mutter/DisplayConfig \
    org.gnome.Mutter.DisplayConfig \
    HasExternalMonitor | awk '{print $2}'
)"

dp1_status="$(cat /sys/class/drm/card1-DP-1/status 2>/dev/null || echo disconnected)"
dp1_enabled="$(cat /sys/class/drm/card1-DP-1/enabled 2>/dev/null || echo disabled)"
dp1_edid_bytes="$(wc -c </sys/class/drm/card1-DP-1/edid 2>/dev/null || echo 0)"

printf 'dp1_status=%s\n' "$dp1_status"
printf 'dp1_enabled=%s\n' "$dp1_enabled"
printf 'dp1_edid_bytes=%s\n' "$dp1_edid_bytes"
printf 'has_external_monitor=%s\n' "$has_external"
echo

if [ "$has_external" = "true" ] || [ "$dp1_status" = "connected" ]; then
  echo "== Re-apply external-only =="
  surface-display-auto external-only
  echo
  echo "== After =="
  surface-display-auto status || true
  exit 0
fi

echo "External monitor is not detected at all."
echo "The issue is likely still in USB-C / hub / cable / DP Alt Mode negotiation."
echo
surface-display-diagnose
