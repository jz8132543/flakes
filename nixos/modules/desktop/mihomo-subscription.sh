# shellcheck shell=bash
set -euo pipefail
umask 077

# Only the subscription is managed here. GeoIP/GeoSite/ASN and the LightGBM
# model come from nixpkgs or mihomo-smart's own geo/lgbm auto-update, so this
# script must not touch them.

download() {
        local url="$1" output="$2"
        # curl reads the URL on stdin so the token never appears in process arguments.
        printf 'url = "%s"\n' "$url" | curl -q --config - \
                --fail --silent --location --noproxy '*' \
                --proto '=https' --proto-redir '=https' \
                --connect-timeout 15 --max-time 60 --max-filesize 10485760 \
                --output "$output"
}

case "$1" in
fetch)
        url="$(<"$CREDENTIALS_DIRECTORY/url")"
        if [[ ! $url =~ ^https://[^[:space:]\"\\]+$ ]]; then
                echo "Invalid Mihomo subscription URL" >&2
                exit 1
        fi

        # A non-2xx response or transport error aborts before anything is touched.
        temporary="$(mktemp "$RUNTIME_DIRECTORY/.subscription.XXXXXX")"
        if ! download "$url" "$temporary" 2>/dev/null; then
                rm -f "$temporary"
                echo "Mihomo subscription download failed; keeping the current configuration" >&2
                exit 1
        fi
        mv -f "$temporary" "$RUNTIME_DIRECTORY/subscription.yaml"
        ;;

install)
        destination="$2"
        staged="$RUNTIME_DIRECTORY/subscription.yaml"
        [ -e "$staged" ] || {
                echo "No staged Mihomo subscription to install" >&2
                exit 1
        }

        if [ -e "$destination" ] && cmp -s "$staged" "$destination"; then
                rm -f "$staged"
                echo "Mihomo subscription is unchanged"
                exit 0
        fi

        directory="$(dirname "$destination")"
        temporary="$(mktemp "$directory/.subscription.XXXXXX")"
        backup="$(mktemp "$directory/.previous.XXXXXX")"
        trap 'rm -f "$temporary" "$backup"' EXIT

        had_previous=false
        if [ -e "$destination" ]; then
                cp -p "$destination" "$backup"
                had_previous=true
        fi

        install -m 0600 "$staged" "$temporary"
        mv -f "$temporary" "$destination"

        # Restore the previous bytes if the daemon rejects the new subscription.
        if ! systemctl try-restart mihomo.service >/dev/null 2>&1; then
                if "$had_previous"; then
                        mv -f "$backup" "$destination"
                else
                        rm -f "$destination"
                fi
                systemctl try-restart mihomo.service >/dev/null 2>&1 || true
                echo "Mihomo restart failed; restored the previous configuration" >&2
                exit 1
        fi

        rm -f "$staged"
        echo "Mihomo subscription updated"
        ;;

*)
        echo "Invalid Mihomo subscription update action" >&2
        exit 1
        ;;
esac
