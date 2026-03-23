#!/usr/bin/env bash
set -euo pipefail

if ! command -v deploy-rs >/dev/null 2>&1; then
  echo "deploy-rs is not available in PATH" >&2
  exit 127
fi

hostname_override=""
hostname_suffix=""
expect_hostname=0
expect_suffix=0
collect_targets=0
seen_double_dash=0

targets=()
forward_args=()

normalize_suffix() {
  local suffix="$1"
  if [[ -z $suffix ]]; then
    printf '%s' ""
  elif [[ $suffix == .* ]]; then
    printf '%s' "$suffix"
  else
    printf '.%s' "$suffix"
  fi
}

infer_node_name() {
  local ref="$1"
  local selector="${ref#*#}"

  if [[ $selector == "$ref" || -z $selector ]]; then
    return 1
  fi

  selector="${selector%%.*}"
  if [[ -z $selector ]]; then
    return 1
  fi

  printf '%s' "$selector"
}

for arg in "$@"; do
  if ((expect_hostname)); then
    hostname_override="$arg"
    forward_args+=("$arg")
    expect_hostname=0
    continue
  fi

  if ((expect_suffix)); then
    hostname_suffix="$arg"
    expect_suffix=0
    continue
  fi

  if ((collect_targets)); then
    if [[ $arg == "--" ]]; then
      seen_double_dash=1
      collect_targets=0
      forward_args+=("$arg")
      continue
    fi

    if [[ $arg == -* ]]; then
      collect_targets=0
    else
      targets+=("$arg")
      forward_args+=("$arg")
      continue
    fi
  fi

  case "$arg" in
  --hostname)
    forward_args+=("$arg")
    expect_hostname=1
    ;;
  --hostname-suffix)
    expect_suffix=1
    ;;
  --targets)
    forward_args+=("$arg")
    collect_targets=1
    ;;
  --)
    seen_double_dash=1
    forward_args+=("$arg")
    ;;
  -*)
    forward_args+=("$arg")
    ;;
  *)
    if ((seen_double_dash == 0)) && ((${#targets[@]} == 0)); then
      targets+=("$arg")
    fi
    forward_args+=("$arg")
    ;;
  esac
done

if ((expect_hostname)); then
  echo "--hostname requires a value" >&2
  exit 2
fi

if ((expect_suffix)); then
  echo "--hostname-suffix requires a value" >&2
  exit 2
fi

if [[ -z $hostname_override && -n $hostname_suffix ]]; then
  if ((${#targets[@]} != 1)); then
    echo "--hostname-suffix requires exactly one deploy target unless --hostname is provided explicitly" >&2
    exit 2
  fi

  if ! node_name="$(infer_node_name "${targets[0]}")"; then
    echo "failed to infer node name from target: ${targets[0]}" >&2
    exit 2
  fi

  hostname_override="${node_name}$(normalize_suffix "$hostname_suffix")"
  forward_args+=("--hostname" "$hostname_override")
fi

exec deploy-rs "${forward_args[@]}"
