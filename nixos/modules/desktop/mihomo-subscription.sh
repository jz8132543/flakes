# shellcheck shell=bash
set -euo pipefail
umask 077

case "$1" in
fetch)
  url="$(<"$CREDENTIALS_DIRECTORY/url")"
  # curl reads the URL on stdin so the token never appears in process arguments.
  if [[ ! $url =~ ^https://[^[:space:]\"\\]+$ ]]; then
    echo "Invalid Mihomo subscription URL" >&2
    exit 1
  fi
  work="$(mktemp -d "$RUNTIME_DIRECTORY/validate.XXXXXX")"
  trap 'rm -rf "$work"' EXIT
  if ! printf 'url = "%s"\n' "$url" | curl -q --config - \
    --fail --silent --location --noproxy '*' \
    --proto '=https' --proto-redir '=https' \
    --connect-timeout 15 --max-time 60 --max-filesize 10485760 \
    --retry 2 --retry-delay 5 --output "$work/source.yaml" >/dev/null 2>&1; then
    echo "Mihomo subscription download failed; keeping the current configuration" >&2
    exit 1
  fi
  ln -s "$MIHOMO_GEOIP" "$work/GeoIP.dat"
  ln -s "$MIHOMO_GEOSITE" "$work/GeoSite.dat"
  ln -s "$MIHOMO_MMDB" "$work/Country.mmdb"
  if [ -n "$MIHOMO_POLICY_FILE" ]; then
    if ! "$MIHOMO_PYTHON" "$MIHOMO_POLICY_SCRIPT" \
      "$work/source.yaml" "$work/config.yaml" "$MIHOMO_POLICY_FILE" >/dev/null 2>&1; then
      echo "Mihomo subscription policy preparation failed; keeping the current configuration" >&2
      exit 1
    fi
  else
    cp "$work/source.yaml" "$work/config.yaml"
  fi
  # Validate the effective host policy in an isolated cache, not the live daemon's state.
  if ! mihomo -t -d "$work" -f "$work/config.yaml" >/dev/null 2>&1; then
    echo "Mihomo subscription validation failed; keeping the current configuration" >&2
    exit 1
  fi
  mv "$work/source.yaml" "$RUNTIME_DIRECTORY/config.yaml"
  ;;
install)
  destination="$2"
  if cmp -s "$RUNTIME_DIRECTORY/config.yaml" "$destination"; then
    echo "Mihomo subscription is unchanged"
    exit 0
  fi
  directory="$(dirname "$destination")"
  temporary="$(mktemp "$directory/.subscription.XXXXXX")"
  backup="$(mktemp "$directory/.previous.XXXXXX")"
  trap 'rm -f "$temporary" "$backup"' EXIT
  previous=false
  if [ -e "$destination" ]; then
    cp -p "$destination" "$backup"
    previous=true
  fi
  install -m 0600 "$RUNTIME_DIRECTORY/config.yaml" "$temporary"
  mv -f "$temporary" "$destination"
  if ! systemctl try-restart mihomo.service >/dev/null 2>&1; then
    if "$previous"; then
      mv -f "$backup" "$destination"
    else
      rm -f "$destination"
    fi
    systemctl try-restart mihomo.service >/dev/null 2>&1 || true
    echo "Mihomo restart failed; restored the previous configuration" >&2
    exit 1
  fi
  echo "Mihomo subscription updated"
  ;;
*)
  echo "Invalid Mihomo subscription update action" >&2
  exit 1
  ;;
esac
