# shellcheck shell=bash
# Shared by the controller and agent. Callers provide jq, flock and coreutils.
sdwan_state_validate() {
  jq -se --arg action validate --arg mode "${2:-merge}" \
    --argjson now 0 --argjson ttl "$DN42_SDWAN_LEASE_SECONDS" \
    -f "$DN42_SDWAN_FILTER" <<<"$1" >/dev/null
}

sdwan_state_update() (
  set -euo pipefail
  state="$1"
  mode="$2"
  case "$mode" in init | merge | register) ;; *) return 1 ;; esac
  mkdir -p "$(dirname "$state")" || return 1
  exec 200>"$state.lock" || return 1
  flock -x 200 || return 1

  now="${DN42_SDWAN_NOW:-$(date +%s)}"
  trap 'rm -f "${tmp:-}" "${input:-}" "${old:-}" "${seeds:-}" "${draft:-}"' EXIT
  tmp=$(mktemp "$state.XXXXXX") || return 1
  input=$(mktemp "$state.input.XXXXXX") || return 1
  old=$(mktemp "$state.old.XXXXXX") || return 1
  seeds=$(mktemp "$state.seeds.XXXXXX") || return 1
  draft=$(mktemp "$state.draft.XXXXXX") || return 1

  if [ "$#" -ge 3 ]; then
    printf '%s\n' "$3" >"$input" || return 1
  elif [ "$mode" = init ]; then
    printf '{}\n' >"$input" || return 1
  else
    cat >"$input" || return 1
  fi
  jq -se --arg action validate --arg mode "$mode" \
    --argjson now "$now" --argjson ttl "$DN42_SDWAN_LEASE_SECONDS" \
    -f "$DN42_SDWAN_FILTER" "$input" >/dev/null || return 1

  printf '{}\n' >"$old" || return 1
  if [ -s "$state" ]; then
    if sdwan_state_validate "$(cat "$state")"; then
      cp "$state" "$old" || return 1
    else
      printf 'Ignoring invalid SD-WAN state: %s; rebuilding from bootstrap\n' "$state" >&2
    fi
  fi
  printf '{}\n' >"$seeds" || return 1
  if [ -s "$state.bootstrap.json" ]; then
    # Never renew bootstrap leases just because a process or host restarted.
    sdwan_state_validate "$(cat "$state.bootstrap.json")" || return 1
    cp "$state.bootstrap.json" "$seeds" || return 1
  fi
  sdwan_state_validate "$(cat "$DN42_SDWAN_BOOTSTRAP_FILE")" || return 1

  jq -s --arg action update --arg mode "$mode" \
    --argjson now "$now" --argjson ttl "$DN42_SDWAN_LEASE_SECONDS" \
    -f "$DN42_SDWAN_FILTER" "$old" "$DN42_SDWAN_BOOTSTRAP_FILE" "$seeds" "$input" >"$draft" || return 1
  jq -S '.seeds' "$draft" >"$seeds" || return 1
  jq -S '.state' "$draft" >"$tmp" || return 1
  chmod 600 "$seeds" "$tmp" || return 1
  mv -f "$seeds" "$state.bootstrap.json" || return 1
  mv -f "$tmp" "$state" || return 1
  # Emit the snapshot while holding the same lock as every writer.
  cat "$state"
)
