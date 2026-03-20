#!/usr/bin/env bash

set -eu

echo "== Time =="
date --iso-8601=seconds
echo

echo "== Kernel =="
uname -r
echo

echo "== GPU =="
lspci -nnk | rg -A3 'VGA compatible controller|3D controller|Display controller' || true
echo
nvidia-smi || true
echo

echo "== USB =="
lsusb
echo

echo "== DRM Connectors =="
for status in /sys/class/drm/*/status; do
  connector_dir="$(dirname "$status")"
  connector="$(basename "$connector_dir")"
  enabled="$(cat "$connector_dir/enabled" 2>/dev/null || echo unknown)"
  dpms="$(cat "$connector_dir/device/power_state" 2>/dev/null || echo unknown)"
  edid_bytes="$(wc -c <"$connector_dir/edid" 2>/dev/null || echo 0)"
  printf '%s status=%s enabled=%s power=%s edid_bytes=%s\n' \
    "$connector" "$(cat "$status")" "$enabled" "$dpms" "$edid_bytes"
done
echo

echo "== Mutter Display State =="
surface-display-auto status || true
echo

echo "== Recent Display Logs =="
journalctl -b --no-pager -k -n 200 | rg -i 'drm|i915|nvidia|typec|usb-c|displayport|billboard|alt mode|dp-' || true
