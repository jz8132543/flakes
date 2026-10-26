# shellcheck shell=bash
set -euo pipefail
umask 077
dir=${XDG_CONFIG_HOME:-$HOME/.config}/winpodx
mode=${1:-deploy}
case "$mode" in init | deploy | status) ;; *)
  printf '%s\n' 'Usage: winpodx-deploy [init|deploy|status]' >&2
  exit 2
  ;;
esac
status=$WINPODX_STORAGE/shared/winpodx-deployment.json
if [[ $mode == status ]]; then
  if [[ -f $status ]]; then jq . "$status"; else printf '%s\n' 'Windows/Office deployment not completed yet'; fi
  exit 0
fi
mkdir -p "$dir" "$WINPODX_STORAGE/shared"
exec 9>"$dir/deployment.run.lock"
if [[ $mode == init ]]; then
  # A running deployment has already initialized its state. Never block a
  # system rebuild behind the long-lived deployment lock.
  flock -n 9 || exit 0
else
  flock 9
fi

if [[ ! -f $dir/winpodx.toml ]]; then
  tmp=$(mktemp "$dir/config.XXXXXX")
  trap 'rm -f "$tmp"' EXIT
  if [[ -n ${WINPODX_PASSWORD_FILE:-} ]]; then
    password=$(jq -Rs 'rtrimstr("\n") | rtrimstr("\r")' <"$WINPODX_PASSWORD_FILE")
    [[ $password != '""' ]] || {
      printf '%s\n' 'Empty guest password file' >&2
      exit 1
    }
  else
    password="\"$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')\""
  fi
  while IFS= read -r line; do
    case "$line" in
    'password = ""') printf 'password = %s\n' "$password" ;;
    'password_updated = ""') printf 'password_updated = "%s"\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" ;;
    *) printf '%s\n' "$line" ;;
    esac
  done <"$WINPODX_SEED" >"$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$dir/winpodx.toml"
  trap - EXIT
fi
if [[ $WINPODX_INITIAL_DEPLOYMENT != 1 ]]; then exit 0; fi
if [[ ! -f $dir/initial-deployment.json ]]; then
  install -m 600 "$WINPODX_SETTINGS" "$dir/initial-deployment.json"
fi
generation=$(jq -er .generation "$dir/initial-deployment.json")
complete() { [[ -f $dir/deployment.done ]] && [[ $(<"$dir/deployment.done") == "$generation" ]]; }
if complete; then exit 0; fi
exec 8>"$dir/deployment.guard.lock"
flock 8
printf '%s\n' "$generation" >"$dir/deployment.pending"
flock -u 8
if [[ $mode == init ]]; then exit 0; fi

# Secrets are runtime-only; the native compose staging preserves extra files.
mkdir -p "$dir/oem"
for kind in WINDOWS OFFICE; do
  variable=WINPODX_${kind}_KEY_FILE
  keyfile=${!variable:-}
  if [[ -n $keyfile ]]; then
    install -m 600 "$keyfile" "$dir/oem/${kind,,}.key"
  fi
done
export WINPODX_NO_TRAY_SPAWN=1
export WINPODX_DECLARATIVE_SHORTCUTS=1
# Starting an existing paused container must not replace it.
if [[ $(podman inspect --format '{{.State.Status}}' winpodx-windows 2>/dev/null || true) == paused ]]; then podman unpause winpodx-windows; fi
# The native backend owns the startup scope for CLI, GUI and tray callers.
# Long-lived native children must not inherit the deployment locks.
"$WINPODX_CLI" pod start 8>&- 9>&-
"$WINPODX_CLI" pod wait-ready 8>&- 9>&-
printf '%s\n' 'Waiting for the persistent Windows Office/activation task...'
until [[ -f $status ]] && jq -e --arg generation "$generation" '.generation == $generation and .complete == true' "$status" >/dev/null; do
  sleep 30
done
"$WINPODX_CLI" provision --require-agent --verbose 8>&- 9>&-
result=$("$WINPODX_CLI" host-open refresh --json 8>&- 9>&-)
jq -e '.sync_error == null' <<<"$result" >/dev/null
flock 8
tmp=$(mktemp "$dir/done.XXXXXX")
printf '%s\n' "$generation" >"$tmp"
mv "$tmp" "$dir/deployment.done"
rm -f "$dir/deployment.pending"
flock -u 8
systemctl --user --no-block start winpodx-tray.service
jq . "$status"
