# shellcheck shell=bash
export PATH="@procps@/bin:@gnugrep@/bin:@gawk@/bin:@coreutils@/bin:@iproute2@/bin:@gnused@/bin:$PATH"

pane_pid=$1

COLOR_ICON_BG="#b4befe"
COLOR_ICON_FG="#11111b"
COLOR_TEXT_BG="#313244"
COLOR_TEXT_FG="#cdd6f4"

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

  printf '%s\n' "$destination"
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

get_socket_info_by_pid() {
  local pid="$1"
  local prev="" line peer rtt
  while IFS= read -r line; do
    case "$line" in
    *"pid=$pid,"*)
      peer=$(printf '%s\n' "$prev" | awk '{print $5}')
      rtt=$(printf '%s\n' "$line" | sed -nE 's/.*rtt:([0-9.]+)\/.*/\1/p')
      if [ -n "$peer" ]; then
        parse_peer "$peer"
        printf '%s\t%s\t%s\n' "$PEER_HOST" "$PEER_PORT" "$rtt"
        return 0
      fi
      ;;
    esac
    prev="$line"
  done <<EOF
$(ss -Hntpi state established 2>/dev/null)
EOF
  return 1
}

ssh_pid=$(find_ssh_pid "$pane_pid")

if [ -n "$ssh_pid" ]; then
  ICON="  "
  load_ssh_args "$ssh_pid"
  destination=$(extract_ssh_target)

  if [ -n "$destination" ]; then
    target_label="${destination##*@}"
  else
    target_label=""
  fi

  ssh_config=$(@ssh@ -G "${SSH_CONFIG_ARGS[@]}" 2>/dev/null)
  parse_ssh_config "$ssh_config"

  final_host="$CONFIG_HOST"
  final_port="$CONFIG_PORT"
  if [ -z "$target_label" ]; then
    target_label="$final_host"
  fi

  display_text="$target_label"

  socket_info=$(get_socket_info_by_pid "$ssh_pid")
  socket_host=$(printf '%s\n' "$socket_info" | awk -F '\t' 'NR==1 {print $1}')
  socket_port=$(printf '%s\n' "$socket_info" | awk -F '\t' 'NR==1 {print $2}')
  socket_rtt=$(printf '%s\n' "$socket_info" | awk -F '\t' 'NR==1 {print $3}')

  if [ -z "$final_host" ]; then
    final_host="$socket_host"
  fi
  if [ -z "$final_port" ]; then
    final_port="$socket_port"
  fi
  if [ -z "$target_label" ]; then
    target_label="$socket_host"
    display_text="$target_label"
  fi

  latency=$(printf '%s\n' "$socket_rtt" | sed -nE 's/^([0-9]+)(\.[0-9]+)?$/\1/p' | head -n 1)
  if [ -n "$latency" ]; then
    display_text="$target_label $latency"
  fi
fi

echo "#[fg=${COLOR_ICON_BG}]#{E:@catppuccin_status_left_separator}#[fg=${COLOR_ICON_FG},bg=${COLOR_ICON_BG}]${ICON}#{E:@catppuccin_status_middle_separator}#[fg=${COLOR_TEXT_FG},bg=${COLOR_TEXT_BG}] $display_text#[fg=${COLOR_TEXT_BG}]#{E:@catppuccin_status_right_separator}"
