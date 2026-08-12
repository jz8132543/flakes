# shellcheck shell=bash
export PATH="@procps@/bin:@gnugrep@/bin:@gawk@/bin:@coreutils@/bin:@iproute2@/bin:@gnused@/bin:@tcping@:$PATH"

pane_pid=$1

COLOR_FG="#e5e5e5"
COLOR_SEP="#545454"

ICON="  "
display_text=$(hostname)

find_ssh_pid() {
  local pid="$1"
  local child found cmdline exe

  [ -n "$pid" ] || return 1
  [ -r "/proc/$pid/cmdline" ] || return 1

  cmdline=$(tr '\0' '\n' <"/proc/$pid/cmdline" 2>/dev/null | head -n 1)
  exe=${cmdline##*/}
  if [ "$exe" = "ssh" ]; then
    printf '%s\n' "$pid"
    return 0
  fi

  for child in $(cat "/proc/$pid/task/$pid/children" 2>/dev/null); do
    found=$(find_ssh_pid "$child")
    if [ -n "$found" ]; then
      printf '%s\n' "$found"
      return 0
    fi
  done

  return 1
}

load_ssh_args() {
  local pid="$1"
  SSH_ARGS=()
  while IFS= read -r -d '' arg; do
    SSH_ARGS+=("$arg")
  done <"/proc/$pid/cmdline"
}

is_ssh_flag_with_value() {
  case "$1" in
  -B | -b | -c | -D | -E | -e | -F | -I | -i | -J | -L | -l | -m | -O | -o | -p | -Q | -R | -S | -W | -w)
    return 0
    ;;
  *)
    return 1
    ;;
  esac
}

extract_ssh_target() {
  local i arg skip_next=0 destination=""
  SSH_CONFIG_ARGS=()

  for ((i = 1; i < ${#SSH_ARGS[@]}; i++)); do
    arg="${SSH_ARGS[$i]}"

    if [ "$skip_next" -eq 1 ]; then
      SSH_CONFIG_ARGS+=("$arg")
      skip_next=0
      continue
    fi

    case "$arg" in
    --)
      break
      ;;
    -*)
      SSH_CONFIG_ARGS+=("$arg")
      if is_ssh_flag_with_value "$arg"; then
        skip_next=1
      elif [ "${#arg}" -gt 2 ] && is_ssh_flag_with_value "${arg:0:2}"; then
        :
      fi
      ;;
    *)
      destination="$arg"
      SSH_CONFIG_ARGS+=("$arg")
      break
      ;;
    esac
  done

  DESTINATION="$destination"
}

parse_ssh_config() {
  local config_text="$1"
  CONFIG_HOST=$(printf '%s\n' "$config_text" | awk '/^hostname / {print $2; exit}')
  CONFIG_PORT=$(printf '%s\n' "$config_text" | awk '/^port / {print $2; exit}')
  CONFIG_PROXYJUMP=$(printf '%s\n' "$config_text" | awk '/^proxyjump / {print $2; exit}')
  CONFIG_PROXYCOMMAND=$(printf '%s\n' "$config_text" | sed -n 's/^proxycommand //p' | head -n 1)
}

parse_peer() {
  local peer="$1"
  if [ "${peer#\[}" != "$peer" ]; then
    PEER_HOST="${peer#\[}"
    PEER_HOST="${PEER_HOST%%]*}"
    PEER_PORT="${peer##*]:}"
  else
    PEER_HOST="${peer%:*}"
    PEER_PORT="${peer##*:}"
  fi
}

get_latency() {
  local host="$1" port="$2"
  [ -n "$host" ] && [ -n "$port" ] || return 1

  local tcp_ms
  tcp_ms=$(tcping -c 1 -o json "${host}:${port}" 2>/dev/null |
    grep '"record":"probe"' |
    grep '"success":true' |
    grep -oE '"duration_ms":[0-9]+(\.[0-9]+)?' |
    grep -oE '[0-9]+(\.[0-9]+)?$')

  local try_ping=0
  if [ -z "$tcp_ms" ]; then
    try_ping=1
  else
    local is_low
    is_low=$(echo "$tcp_ms" | awk '{if ($1 < 5) print 1; else print 0}')
    [ "$is_low" -eq 1 ] && try_ping=1
  fi

  if [ "$try_ping" -eq 1 ]; then
    local ping_out ms
    if ping_out=$(ping -c 1 -W 1 "$host" 2>/dev/null); then
      ms=$(echo "$ping_out" | grep -oE 'time=[0-9]+(\.[0-9]+)?' | cut -d= -f2 | head -n 1)
      if [ -n "$ms" ]; then
        echo "$ms"
        return 0
      fi
    fi
  fi

  if [ -n "$tcp_ms" ]; then
    echo "$tcp_ms"
    return 0
  fi

  return 1
}

ssh_pid=$(find_ssh_pid "$pane_pid")

if [ -n "$ssh_pid" ]; then
  ICON="󰒋  "
  load_ssh_args "$ssh_pid"
  # Call without $() so SSH_CONFIG_ARGS mutations survive in this shell
  DESTINATION=""
  extract_ssh_target
  destination="$DESTINATION"

  if [ -n "$destination" ]; then
    # Strip user@, then strip everything after the first dot (domain suffix)
    raw_label="${destination##*@}"
    target_label="${raw_label%%.*}"
  else
    target_label=""
  fi

  ssh_config=$(@ssh@ -G "${SSH_CONFIG_ARGS[@]}" 2>/dev/null)
  parse_ssh_config "$ssh_config"

  final_host="$CONFIG_HOST"
  final_port="$CONFIG_PORT"

  # Use the short hostname (first label) as display label if not already set
  if [ -z "$target_label" ] && [ -n "$final_host" ]; then
    target_label="${final_host%%.*}"
  fi

  display_text="${target_label:-$(hostname)}"

  # Get latency via ICMP ping or tcping using the authoritative host:port from ssh -G
  if [ -n "$final_host" ] && [ -n "$final_port" ]; then
    latency_ms=$(get_latency "$final_host" "$final_port")
    if [ -n "$latency_ms" ]; then
      latency_fmt=$(printf '%s\n' "$latency_ms" | awk '{
        if ($1 < 1) printf "%.1fms", $1
        else printf "%dms", int($1 + 0.5)
      }')
      display_text="$target_label ${latency_fmt}"
    fi
  fi
fi

echo "#[fg=${COLOR_SEP}]│ #[fg=${COLOR_FG}]${ICON}$display_text "
