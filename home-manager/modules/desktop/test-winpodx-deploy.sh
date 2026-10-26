#!/usr/bin/env bash
set -euo pipefail
root=$(mktemp -d /tmp/kilo/winpodx-test.XXXXXX)
trap 'rm -rf "$root"' EXIT
here=$(dirname "$(realpath "$0")")
guard=$here/../../../nixos/modules/desktop/winpodx/podman-guard.sh
export XDG_CONFIG_HOME=$root/config WINPODX_STORAGE=$root/storage
export WINPODX_SEED=$root/seed.toml WINPODX_SETTINGS=$root/settings.json
export WINPODX_INITIAL_DEPLOYMENT=1 WINPODX_CLI=$root/cli WINPODX_REAL_PODMAN=$root/podman
mkdir -p "$root/bin"
printf '[rdp]\npassword = ""\npassword_updated = ""\n' >"$WINPODX_SEED"
printf '{"generation":"test-generation"}\n' >"$WINPODX_SETTINGS"
cat >"$root/podman" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  inspect) printf '%s\n' running ;;
  container|pod) exit 0 ;;
  pause)
    # The guarded operation must retain the shared lock, not merely check it.
    if flock -n "$XDG_CONFIG_HOME/winpodx/deployment.guard.lock" true; then exit 90; fi
    ;;
esac
STUB
cat >"$WINPODX_CLI" <<'STUB'
#!/usr/bin/env bash
[[ ! -e /proc/$$/fd/8 && ! -e /proc/$$/fd/9 ]] || exit 91
printf '%s\n' "$*" >> "$XDG_CONFIG_HOME/calls"
if [[ $* == 'pod start' && ${TEST_GUEST_COMPLETE:-0} == 1 ]]; then
  printf '{"generation":"test-generation","complete":true}\n' > "$WINPODX_STORAGE/shared/winpodx-deployment.json"
fi
if [[ $* == 'host-open refresh --json' ]]; then printf '{"sync_error":null}\n'; fi
STUB
cat >"$root/bin/systemd-run" <<'STUB'
#!/usr/bin/env bash
while [[ ${1:-} == --* ]]; do shift; done
exec "$@"
STUB
chmod +x "$root/podman" "$WINPODX_CLI" "$root/bin/systemd-run"
ln -s "$root/podman" "$root/bin/podman"
ln -s "$root/podman" "$root/bin/systemctl"
export PATH=$root/bin:$PATH
deploy=$here/winpodx-deploy.sh
bash "$deploy" init
grep -qE '^password = "[0-9a-f]{48}"$' "$XDG_CONFIG_HOME/winpodx/winpodx.toml"
pending=$XDG_CONFIG_HOME/winpodx/deployment.pending
[[ -f $pending ]]
printf '# changed by WinPodX\n' >>"$XDG_CONFIG_HOME/winpodx/winpodx.toml"
before=$(sha256sum "$XDG_CONFIG_HOME/winpodx/winpodx.toml")
bash "$deploy" init
[[ $before == "$(sha256sum "$XDG_CONFIG_HOME/winpodx/winpodx.toml")" ]]
exec 7>"$XDG_CONFIG_HOME/winpodx/deployment.run.lock"
flock 7
timeout 1 bash "$deploy" init
flock -u 7
for command in pause stop restart rm; do
  set +e
  bash "$guard" "$command" winpodx-windows >/dev/null 2>&1
  rc=$?
  set -e
  [[ $rc == 75 ]]
done
bash "$guard" unpause winpodx-windows
set +e
bash "$guard" run --replace --name winpodx-windows image >/dev/null 2>&1
rc=$?
set -e
[[ $rc == 75 ]]
set +e
timeout 1 bash "$deploy" >/dev/null
rc=$?
set -e
[[ $rc == 124 && -f $pending && ! -f $XDG_CONFIG_HOME/winpodx/deployment.done ]]
export TEST_GUEST_COMPLETE=1
bash "$deploy" >/dev/null
[[ ! -e $pending && -f $XDG_CONFIG_HOME/winpodx/deployment.done ]]
before=$(sha256sum "$XDG_CONFIG_HOME/calls")
bash "$deploy"
[[ $before == "$(sha256sum "$XDG_CONFIG_HOME/calls")" ]]
bash "$guard" pause winpodx-windows
printf '%s\n' 'PASS: copy-once config, manual pause protection, interrupted deployment, resume and no wake after completion'
