#!/usr/bin/env bash
set -euo pipefail

SCRIPTDIR=$(dirname "$0")
# shellcheck disable=SC1091
. "$SCRIPTDIR/_img_deploy_common.sh"

FLAKE_TARGET=""
TARGET_HOST=""
PORT=22
DEVICE=""
ONLY_BUILD=no
ONLY_STREAM=no
LIVE_OVERWRITE=no
LAST_BUILT_IMAGE_FILE=".last_built_image"
CONTROL_PATH=""
IMG=""
REMOTE_BUSYBOX=""
TEMP_DIR=""
SSH_CMD=()
SSH_AUTH_OPTS=()
SSH_LOGIN_DESC=""
SSH_IDENTITY_FILE=""
LIVE_SSH_IDENTITY_FILE=""
LIVE_SSH_PUBLIC_KEY_FILE=""
LIVE_SSH_HOSTKEY_OPTS=(-o UserKnownHostsFile=/dev/null -o GlobalKnownHostsFile=/dev/null -o StrictHostKeyChecking=no)
LIVE_SSH_PORT=""
LIVE_SSH_INTERNAL_PORT=""
LIVE_SSH_REDIRECT_PORT=""
LIVE_SSH_EXTERNAL_PORT=""
LIVE_SSH_WINDOW_SIZE="${LIVE_SSH_WINDOW_SIZE:-4194304}"
LIVE_STREAM_PORT="${LIVE_STREAM_PORT:-2223}"
REMOTE_LIVE_DIR=""
STATIC_BUSYBOX_LOCAL=""
STATIC_DROPBEAR_LOCAL=""
STATIC_DROPBEARKEY_LOCAL=""
STATIC_ZSTD_LOCAL=""
LIVE_SSH_AUTHORIZED_KEYS_FILE=""

usage() {
  cat <<'EOF'
Usage:
  deploy-raw-image.sh --target FLAKE_ATTR --only-build
  deploy-raw-image.sh --target FLAKE_ATTR --target-host user@host --device /dev/sdX [--port PORT] [--only-stream|--live-overwrite]

Arguments:
  --target       Nix flake build target, usually .#nixosConfigurations.<host>.config.system.build.diskoImages
  --target-host  Remote SSH target in user@host form
  --device       Remote block device to overwrite
  --port         Remote SSH port, defaults to 22
  --identity-file
                 SSH private key to use for both the initial connection and the in-memory live SSH
  --live-ssh-port
                 Run the in-memory live SSH server directly on this port instead of redirecting the original SSH port
  --live-ssh-window-size
                 Dropbear receive window size in bytes for the in-memory live SSH server, defaults to 4194304
  --live-stream-port
                 Direct TCP port used to stream image data during live overwrite, defaults to 2223
  --only-build   Build image locally and stop
  --only-stream  Skip the build step and stream the last built image
  --live-overwrite
                 Overwrite the currently running Linux system and force reboot after dd
EOF
  exit 1
}

is_true() {
  case "${1:-}" in
  yes | true | TRUE | 1 | on | ON) return 0 ;;
  *) return 1 ;;
  esac
}

quote_for_sh() {
  local value="$1"
  printf "'%s'" "${value//\'/\'\\\'\'}"
}

log_file_preview() {
  local path="$1"
  local limit="${2:-5}"

  if [ ! -f "$path" ]; then
    return
  fi

  awk -v limit="$limit" 'NF { print; count++; if (count >= limit) exit }' "$path"
}

fingerprint_public_key_file() {
  local path="$1"
  ssh-keygen -lf "$path" 2>/dev/null || true
}

fingerprint_public_key_text() {
  ssh-keygen -lf /dev/stdin 2>/dev/null || true
}

detect_identity_file() {
  local candidate

  if [ -n "$SSH_IDENTITY_FILE" ]; then
    return 0
  fi

  while IFS= read -r candidate; do
    case "$candidate" in
    none | "")
      continue
      ;;
    "~/"*)
      candidate="${HOME}/${candidate#~/}"
      ;;
    esac

    if [ -f "$candidate" ] && [ -f "${candidate}.pub" ]; then
      SSH_IDENTITY_FILE="$candidate"
      return 0
    fi
  done < <(ssh -G -p "$PORT" "$TARGET_HOST" | awk '/^identityfile / { print $2 }')

  if [ -f "${HOME}/.ssh/id_ed25519" ] && [ -f "${HOME}/.ssh/id_ed25519.pub" ]; then
    SSH_IDENTITY_FILE="${HOME}/.ssh/id_ed25519"
    return 0
  fi

  die "Could not determine an SSH identity file for ${TARGET_HOST}; pass --identity-file explicitly"
}

collect_live_authorized_keys() {
  local auth_keys_file
  local candidate

  prepare_temp_dir
  auth_keys_file="${TEMP_DIR}/live-authorized_keys"
  : >"$auth_keys_file"

  if [ -n "$SSH_IDENTITY_FILE" ] && [ -f "${SSH_IDENTITY_FILE}.pub" ]; then
    cat "${SSH_IDENTITY_FILE}.pub" >>"$auth_keys_file"
    printf '\n' >>"$auth_keys_file"
  fi

  while IFS= read -r candidate; do
    case "$candidate" in
    none | "")
      continue
      ;;
    "~/"*)
      candidate="${HOME}/${candidate#~/}"
      ;;
    esac

    if [ -f "${candidate}.pub" ]; then
      cat "${candidate}.pub" >>"$auth_keys_file"
      printf '\n' >>"$auth_keys_file"
    fi
  done < <(ssh -G -p "$PORT" "$TARGET_HOST" | awk '/^identityfile / { print $2 }')

  if command -v ssh-add >/dev/null 2>&1; then
    ssh-add -L 2>/dev/null >>"$auth_keys_file" || true
    printf '\n' >>"$auth_keys_file"
  fi

  awk 'NF && !seen[$0]++' "$auth_keys_file" >"${auth_keys_file}.dedup"
  mv "${auth_keys_file}.dedup" "$auth_keys_file"

  [ -s "$auth_keys_file" ] || die "No public keys available for live SSH authorization"
  LIVE_SSH_AUTHORIZED_KEYS_FILE="$auth_keys_file"
}

log_live_ssh_inputs() {
  log "Live SSH identity file: ${LIVE_SSH_IDENTITY_FILE:-<none>}"
  if [ -n "${LIVE_SSH_PUBLIC_KEY_FILE}" ] && [ -f "${LIVE_SSH_PUBLIC_KEY_FILE}" ]; then
    log "Live SSH identity fingerprint:"
    fingerprint_public_key_file "${LIVE_SSH_PUBLIC_KEY_FILE}"
  fi

  if command -v ssh-add >/dev/null 2>&1; then
    log "ssh-agent public keys:"
    ssh-add -L 2>/dev/null | while IFS= read -r line; do
      [ -n "$line" ] || continue
      printf '%s\n' "$line" | fingerprint_public_key_text
    done
  fi

  log "Live SSH authorized_keys preview:"
  log_file_preview "${LIVE_SSH_AUTHORIZED_KEYS_FILE}" 10
}

setup_ssh_command() {
  if [ -n "${SSH_PASSWORD:-}" ] && [ -z "${SSHPASS:-}" ]; then
    export SSHPASS="${SSH_PASSWORD}"
  fi

  detect_identity_file
  LIVE_SSH_IDENTITY_FILE="$SSH_IDENTITY_FILE"
  LIVE_SSH_PUBLIC_KEY_FILE="${SSH_IDENTITY_FILE}.pub"
  collect_live_authorized_keys
  log_live_ssh_inputs

  SSH_CMD=()
  if [ -n "${SSHPASS:-}" ]; then
    if command -v sshpass >/dev/null 2>&1; then
      SSH_CMD=(sshpass -e ssh)
    else
      die "SSHPASS is set but sshpass is not available in PATH"
    fi
  else
    SSH_CMD=(ssh)
  fi
  SSH_AUTH_OPTS=()
  if [ -n "$SSH_IDENTITY_FILE" ] && [ -f "$SSH_IDENTITY_FILE" ]; then
    SSH_AUTH_OPTS+=(-i "$SSH_IDENTITY_FILE")
    SSH_LOGIN_DESC="$SSH_IDENTITY_FILE + agent/default keys"
  else
    SSH_LOGIN_DESC="agent/default keys"
  fi
}

detect_target_system() {
  local flake_host

  if [[ $FLAKE_TARGET =~ ^\.#nixosConfigurations\.([^.]+)\.config\.system\.build\..+$ ]]; then
    flake_host="${BASH_REMATCH[1]}"
    nix eval --raw --experimental-features 'nix-command flakes' \
      ".#nixosConfigurations.${flake_host}.pkgs.stdenv.hostPlatform.system"
    return
  fi

  nix eval --impure --raw --expr builtins.currentSystem
}

build_static_live_tools() {
  local target_system="$1"
  local dropbear_path
  local busybox_path
  local zstd_path

  log "Building static live SSH tools for ${target_system}"
  dropbear_path="$(nix build --no-link --print-out-paths "nixpkgs#legacyPackages.${target_system}.pkgsStatic.dropbear")"
  busybox_path="$(nix build --no-link --print-out-paths "nixpkgs#legacyPackages.${target_system}.pkgsStatic.busybox")"
  zstd_path="$(
    nix build --no-link --print-out-paths "nixpkgs#legacyPackages.${target_system}.pkgsStatic.zstd" |
      while IFS= read -r path; do
        if [ -x "${path}/bin/zstd" ]; then
          printf '%s\n' "$path"
          break
        fi
      done
  )"

  STATIC_DROPBEAR_LOCAL="${dropbear_path}/bin/dropbear"
  STATIC_DROPBEARKEY_LOCAL="${dropbear_path}/bin/dropbearkey"
  STATIC_BUSYBOX_LOCAL="${busybox_path}/bin/busybox"
  STATIC_ZSTD_LOCAL="${zstd_path}/bin/zstd"

  [ -x "$STATIC_DROPBEAR_LOCAL" ] || die "Missing static dropbear binary: ${STATIC_DROPBEAR_LOCAL}"
  [ -x "$STATIC_DROPBEARKEY_LOCAL" ] || die "Missing static dropbearkey binary: ${STATIC_DROPBEARKEY_LOCAL}"
  [ -x "$STATIC_BUSYBOX_LOCAL" ] || die "Missing static busybox binary: ${STATIC_BUSYBOX_LOCAL}"
  [ -x "$STATIC_ZSTD_LOCAL" ] || die "Missing static zstd binary: ${STATIC_ZSTD_LOCAL}"
}

remote_shell_prefix() {
  if [ -n "$REMOTE_BUSYBOX" ]; then
    printf "env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin %s sh -c" "$(quote_for_sh "$REMOTE_BUSYBOX")"
  else
    printf '%s' "env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin /bin/sh -c"
  fi
}

prepare_temp_dir() {
  if [ -z "$TEMP_DIR" ]; then
    TEMP_DIR="$(mktemp -d)"
  fi
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
    --target)
      FLAKE_TARGET="$2"
      shift 2
      ;;
    --target-host | --host)
      TARGET_HOST="$2"
      shift 2
      ;;
    --port)
      PORT="$2"
      shift 2
      ;;
    --identity-file)
      SSH_IDENTITY_FILE="$2"
      shift 2
      ;;
    --device)
      DEVICE="$2"
      shift 2
      ;;
    --live-ssh-port)
      LIVE_SSH_PORT="$2"
      shift 2
      ;;
    --live-ssh-window-size)
      LIVE_SSH_WINDOW_SIZE="$2"
      shift 2
      ;;
    --live-stream-port)
      LIVE_STREAM_PORT="$2"
      shift 2
      ;;
    --only-build)
      ONLY_BUILD=yes
      shift 1
      ;;
    --only-stream)
      ONLY_STREAM=yes
      shift 1
      ;;
    --live-overwrite)
      LIVE_OVERWRITE=yes
      shift 1
      ;;
    -h | --help)
      usage
      ;;
    *)
      die "Unknown arg: $1"
      ;;
    esac
  done

  [ -n "$FLAKE_TARGET" ] || die "--target is required"

  if is_true "$ONLY_BUILD"; then
    return
  fi

  [ -n "$TARGET_HOST" ] || die "--target-host is required unless --only-build is set"
  [ -n "$DEVICE" ] || die "--device is required unless --only-build is set"
}

build_image() {
  log "Phase 1: Building image..."
  IMG=$(get_nix_image_path "$FLAKE_TARGET")
  printf '%s' "$IMG" >"$LAST_BUILT_IMAGE_FILE"
  log "Build result: $IMG"
}

resolve_cached_image() {
  if [ -f "$LAST_BUILT_IMAGE_FILE" ]; then
    IMG=$(cat "$LAST_BUILT_IMAGE_FILE")
    if [ -e "$IMG" ]; then
      log "Using cached image path: $IMG"
      return
    fi
  fi

  log "Cached image not found or invalid. Rebuilding path from Nix..."
  build_image
}

cleanup() {
  if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
  fi

  if [ -n "$CONTROL_PATH" ] && [ -n "$TARGET_HOST" ]; then
    log "Closing master SSH connection..."
    "${SSH_CMD[@]}" -p "$PORT" -o StrictHostKeyChecking=accept-new -o ControlPath="$CONTROL_PATH" -O exit "$TARGET_HOST" >/dev/null 2>&1 || true
    rm -f "$CONTROL_PATH"
  fi
}

setup_ssh_mux() {
  CONTROL_PATH="/tmp/ssh-control-$(printf '%s' "$TARGET_HOST" | tr '@:/' '---')"
  log "Establishing master SSH connection using ${SSH_LOGIN_DESC}..."
  "${SSH_CMD[@]}" -p "$PORT" -M -f -N \
    "${SSH_AUTH_OPTS[@]}" \
    -o StrictHostKeyChecking=accept-new \
    -o ControlPath="$CONTROL_PATH" \
    -o ControlPersist=600 \
    "$TARGET_HOST" ||
    die "Failed to establish master SSH connection"
  trap cleanup EXIT INT TERM
}

remote_ssh() {
  local cmd="$1"
  "${SSH_CMD[@]}" -T \
    "${SSH_AUTH_OPTS[@]}" \
    -o RequestTTY=no \
    -o StrictHostKeyChecking=accept-new \
    -o ControlPath="$CONTROL_PATH" \
    -p "$PORT" \
    "$TARGET_HOST" \
    "$(remote_shell_prefix) $(quote_for_sh "$cmd")"
}

remote_ssh_quiet() {
  local cmd="$1"
  "${SSH_CMD[@]}" -T \
    "${SSH_AUTH_OPTS[@]}" \
    -o RequestTTY=no \
    -o StrictHostKeyChecking=accept-new \
    -o ControlPath="$CONTROL_PATH" \
    -p "$PORT" \
    "$TARGET_HOST" \
    "$(remote_shell_prefix) $(quote_for_sh "$cmd")" >/dev/null 2>&1
}

upload_remote_file() {
  local local_path="$1"
  local remote_path="$2"
  local mode="${3:-0600}"

  "${SSH_CMD[@]}" -T \
    "${SSH_AUTH_OPTS[@]}" \
    -o RequestTTY=no \
    -o StrictHostKeyChecking=accept-new \
    -o ControlPath="$CONTROL_PATH" \
    -p "$PORT" \
    "$TARGET_HOST" \
    "cat > $(quote_for_sh "$remote_path") && chmod ${mode} $(quote_for_sh "$remote_path")" <"$local_path"
}

wait_for_live_ssh() {
  local attempts="${1:-30}"
  local delay="${2:-1}"
  local live_port="$3"
  local i

  for ((i = 1; i <= attempts; i++)); do
    if ssh \
      -T \
      -o BatchMode=yes \
      -o ControlMaster=no \
      -o ControlPath=none \
      -o RequestTTY=no \
      "${SSH_AUTH_OPTS[@]}" \
      "${LIVE_SSH_HOSTKEY_OPTS[@]}" \
      -p "$live_port" \
      "$TARGET_HOST" \
      true >/dev/null 2>&1; then
      return 0
    fi
    sleep "$delay"
  done

  return 1
}

switch_to_live_ssh() {
  log "Switching deployment traffic to in-memory SSH on port ${LIVE_SSH_EXTERNAL_PORT}"
  cleanup
  PORT="$LIVE_SSH_EXTERNAL_PORT"
  SSH_CMD=(ssh)
  if [ -n "$LIVE_SSH_IDENTITY_FILE" ] && [ -f "$LIVE_SSH_IDENTITY_FILE" ]; then
    SSH_AUTH_OPTS=(-i "$LIVE_SSH_IDENTITY_FILE")
  else
    SSH_AUTH_OPTS=()
  fi
  SSH_AUTH_OPTS+=(-o BatchMode=yes "${LIVE_SSH_HOSTKEY_OPTS[@]}")
  setup_ssh_mux
}

print_live_ssh_debug() {
  if [ -z "${REMOTE_LIVE_DIR}" ]; then
    return
  fi

  log "Collecting live SSH debug information from target..."
  remote_ssh "
    set -eu
    echo '== live dir =='
    ls -la $(quote_for_sh "$REMOTE_LIVE_DIR") 2>/dev/null || true
    echo '== dropbear pid =='
    cat $(quote_for_sh "$REMOTE_LIVE_DIR/dropbear.pid") 2>/dev/null || true
    echo '== dropbear log =='
    cat $(quote_for_sh "$REMOTE_LIVE_DIR/dropbear.log") 2>/dev/null || true
    echo '== authorized_keys =='
    sed -n '1,20p' $(quote_for_sh "$REMOTE_LIVE_DIR/auth/authorized_keys") 2>/dev/null || true
    echo '== hostkey fingerprint =='
    if command -v ssh-keygen >/dev/null 2>&1; then
      ssh-keygen -lf $(quote_for_sh "$REMOTE_LIVE_DIR/hostkey.pub") 2>/dev/null || true
    fi
    echo '== listeners =='
    if command -v ss >/dev/null 2>&1; then
      ss -ltnp || true
    elif command -v netstat >/dev/null 2>&1; then
      netstat -ltnp || true
    fi
    echo '== nft =='
    if command -v nft >/dev/null 2>&1; then
      nft list table ip nixos_live_ssh 2>/dev/null || true
    fi
    echo '== iptables nat prerouting =='
    if command -v iptables >/dev/null 2>&1; then
      iptables -t nat -S PREROUTING 2>/dev/null || true
    fi
  " || true
}

probe_live_ssh_port() {
  local probe_port="$1"
  local label="$2"

  log "Probing ${label} on ${TARGET_HOST}:${probe_port}"
  if ssh \
    -T \
    -o BatchMode=yes \
    -o ControlMaster=no \
    -o ControlPath=none \
    -o RequestTTY=no \
    "${SSH_AUTH_OPTS[@]}" \
    "${LIVE_SSH_HOSTKEY_OPTS[@]}" \
    -p "$probe_port" \
    "$TARGET_HOST" \
    'echo live-ssh-ok' 2>&1; then
    log "Probe succeeded for ${label} on ${TARGET_HOST}:${probe_port}"
    return 0
  fi

  log "Probe failed for ${label} on ${TARGET_HOST}:${probe_port}"
  return 1
}

detect_local_tool() {
  local nix_attr="$1"
  local fallback="$2"
  local tool_path

  tool_path="$(nix build --no-link --print-out-paths "nixpkgs#${nix_attr}" 2>/dev/null || true)"
  if [ -n "$tool_path" ] && [ -x "${tool_path}/bin/${nix_attr}" ]; then
    printf '%s\n' "${tool_path}/bin/${nix_attr}"
    return
  fi

  printf '%s\n' "$fallback"
}

prepare_pipeline_tools() {
  PV_BIN="$(detect_local_tool pv pv)"
  ZSTD_BIN="$(detect_local_tool zstd zstd)"
  SIZE_BYTES=$(stat -c%s "$IMG")

  log "Detecting remote decompressor..."
  REMOTE_COMP="$(remote_ssh '
    if command -v zstd >/dev/null 2>&1; then
      echo zstd
    elif command -v gzip >/dev/null 2>&1; then
      echo gzip
    else
      echo none
    fi
  ')"
  log "Remote decompressor: $REMOTE_COMP"

  case "$REMOTE_COMP" in
  zstd)
    COMPRESS_CMD=("$ZSTD_BIN" -1 -c -T0)
    DECOMPRESS_CMD='zstd -dc'
    ;;
  gzip)
    COMPRESS_CMD=(gzip -1 -c)
    DECOMPRESS_CMD='gzip -dc'
    ;;
  *)
    COMPRESS_CMD=(cat)
    DECOMPRESS_CMD='cat'
    ;;
  esac

  if [[ $IMG == *.zst ]]; then
    READ_CMD=("$ZSTD_BIN" -dc "$IMG")
  else
    READ_CMD=(cat "$IMG")
  fi
}

prepare_live_overwrite() {
  local target_system
  local force_shell_local

  log "LIVE OVERWRITE MODE: Preparing remote system..."
  [ -f "$LIVE_SSH_IDENTITY_FILE" ] || die "Missing live SSH private key: ${LIVE_SSH_IDENTITY_FILE}"
  [ -f "$LIVE_SSH_AUTHORIZED_KEYS_FILE" ] || die "Missing live SSH authorized keys file: ${LIVE_SSH_AUTHORIZED_KEYS_FILE}"

  prepare_temp_dir
  target_system="$(detect_target_system)"
  build_static_live_tools "$target_system"

  LIVE_SSH_REDIRECT_PORT="$(
    remote_ssh '
      set -- ${SSH_CLIENT:-}
      if [ $# -ge 3 ]; then
        printf "%s" "$3"
      else
        printf "22"
      fi
    '
  )"
  LIVE_SSH_INTERNAL_PORT="${LIVE_SSH_INTERNAL_PORT:-2222}"
  LIVE_SSH_EXTERNAL_PORT="${LIVE_SSH_PORT:-$PORT}"

  if [ -n "$LIVE_SSH_PORT" ]; then
    LIVE_SSH_INTERNAL_PORT="$LIVE_SSH_PORT"
  elif [ "$LIVE_SSH_INTERNAL_PORT" = "$LIVE_SSH_REDIRECT_PORT" ]; then
    LIVE_SSH_INTERNAL_PORT=22022
  fi

  REMOTE_LIVE_DIR="$(
    remote_ssh '
      if [ -d /run ] && [ -w /run ]; then
        printf "%s" "/run/nixos-live-ssh"
      elif [ -d /root ] && [ -w /root ]; then
        printf "%s" "/root/.nixos-live-ssh"
      else
        printf "%s" "/tmp/nixos-live-ssh"
      fi
    '
  )"
  force_shell_local="${TEMP_DIR}/live-force-shell.sh"
  cat >"$force_shell_local" <<EOF
#!/bin/sh
set -eu
BUSYBOX='${REMOTE_LIVE_DIR}/busybox'
if [ -n "\${SSH_ORIGINAL_COMMAND:-}" ]; then
  exec "\$BUSYBOX" sh -c "\$SSH_ORIGINAL_COMMAND"
fi
exec "\$BUSYBOX" sh
EOF

  remote_ssh "
    set -eu
    rm -rf $(quote_for_sh "$REMOTE_LIVE_DIR")
    mkdir -p $(quote_for_sh "$REMOTE_LIVE_DIR/auth")
    chmod 700 $(quote_for_sh "$REMOTE_LIVE_DIR") $(quote_for_sh "$REMOTE_LIVE_DIR/auth")
  "
  upload_remote_file "$STATIC_BUSYBOX_LOCAL" "${REMOTE_LIVE_DIR}/busybox" 0755
  upload_remote_file "$STATIC_DROPBEAR_LOCAL" "${REMOTE_LIVE_DIR}/dropbear" 0755
  upload_remote_file "$STATIC_DROPBEARKEY_LOCAL" "${REMOTE_LIVE_DIR}/dropbearkey" 0755
  upload_remote_file "$STATIC_ZSTD_LOCAL" "${REMOTE_LIVE_DIR}/zstd" 0755
  upload_remote_file "$LIVE_SSH_AUTHORIZED_KEYS_FILE" "${REMOTE_LIVE_DIR}/auth/authorized_keys" 0600
  upload_remote_file "$force_shell_local" "${REMOTE_LIVE_DIR}/force-shell.sh" 0755

  remote_ssh "
    set -eu
    rm -f $(quote_for_sh "$REMOTE_LIVE_DIR/hostkey")
    $(quote_for_sh "$REMOTE_LIVE_DIR/dropbearkey") -t ed25519 -f $(quote_for_sh "$REMOTE_LIVE_DIR/hostkey") >/dev/null
    chmod 600 $(quote_for_sh "$REMOTE_LIVE_DIR/hostkey")
  "

  remote_ssh "
    set -eu

    if [ -f $(quote_for_sh "$REMOTE_LIVE_DIR/dropbear.pid") ]; then
      pid=\$(cat $(quote_for_sh "$REMOTE_LIVE_DIR/dropbear.pid") 2>/dev/null || true)
      if [ -n \"\${pid:-}\" ]; then
        kill \"\$pid\" 2>/dev/null || true
      fi
    fi

    $(quote_for_sh "$REMOTE_LIVE_DIR/dropbear") -E -m -s -g -j -k \
      -p $(quote_for_sh "$LIVE_SSH_INTERNAL_PORT") \
      -P $(quote_for_sh "$REMOTE_LIVE_DIR/dropbear.pid") \
      -r $(quote_for_sh "$REMOTE_LIVE_DIR/hostkey") \
      -D $(quote_for_sh "$REMOTE_LIVE_DIR/auth") \
      -W $(quote_for_sh "$LIVE_SSH_WINDOW_SIZE") \
      -c $(quote_for_sh "$REMOTE_LIVE_DIR/force-shell.sh") \
      >$(quote_for_sh "$REMOTE_LIVE_DIR/dropbear.log") 2>&1 &

    if [ -z $(quote_for_sh "$LIVE_SSH_PORT") ]; then
      if command -v nft >/dev/null 2>&1; then
        nft list table ip nixos_live_ssh >/dev/null 2>&1 || nft add table ip nixos_live_ssh
        nft list chain ip nixos_live_ssh prerouting >/dev/null 2>&1 \
          || nft 'add chain ip nixos_live_ssh prerouting { type nat hook prerouting priority dstnat; policy accept; }'
        nft flush chain ip nixos_live_ssh prerouting
        nft add rule ip nixos_live_ssh prerouting tcp dport $(quote_for_sh "$LIVE_SSH_REDIRECT_PORT") redirect to :$(quote_for_sh "$LIVE_SSH_INTERNAL_PORT")
      elif command -v iptables >/dev/null 2>&1; then
        iptables -t nat -D PREROUTING -p tcp --dport $(quote_for_sh "$LIVE_SSH_REDIRECT_PORT") -j REDIRECT --to-ports $(quote_for_sh "$LIVE_SSH_INTERNAL_PORT") 2>/dev/null || true
        iptables -t nat -A PREROUTING -p tcp --dport $(quote_for_sh "$LIVE_SSH_REDIRECT_PORT") -j REDIRECT --to-ports $(quote_for_sh "$LIVE_SSH_INTERNAL_PORT")
      else
        exit 1
      fi
    fi
  "

  probe_live_ssh_port "$LIVE_SSH_INTERNAL_PORT" "direct live SSH" || true
  if [ "$LIVE_SSH_EXTERNAL_PORT" != "$LIVE_SSH_INTERNAL_PORT" ]; then
    probe_live_ssh_port "$LIVE_SSH_EXTERNAL_PORT" "external live SSH" || true
  fi

  if ! wait_for_live_ssh 60 1 "$LIVE_SSH_EXTERNAL_PORT"; then
    print_live_ssh_debug
    die "Timed out waiting for in-memory live SSH on ${TARGET_HOST}:${LIVE_SSH_EXTERNAL_PORT}"
  fi

  switch_to_live_ssh
  REMOTE_BUSYBOX="${REMOTE_LIVE_DIR}/busybox"
  log "In-memory live SSH is ready on ${TARGET_HOST}:${PORT}"
}

stream_image() {
  local bs="4M"
  local direct_host
  local remote_stream_pid_file
  local remote_stream_log
  local remote_stream_cmd

  if is_true "$LIVE_OVERWRITE" && [ -n "$REMOTE_BUSYBOX" ] && [ -n "$REMOTE_LIVE_DIR" ]; then
    direct_host="${TARGET_HOST#*@}"
    remote_stream_pid_file="${REMOTE_LIVE_DIR}/stream.pid"
    remote_stream_log="${REMOTE_LIVE_DIR}/stream.log"
    remote_stream_cmd="exec $(quote_for_sh "$REMOTE_BUSYBOX") nc -l -p $(quote_for_sh "$LIVE_STREAM_PORT") | $(quote_for_sh "$REMOTE_LIVE_DIR/zstd") -d --stdout | dd of=$(quote_for_sh "$DEVICE") bs=$bs conv=fsync status=none"

    log "Phase 2: Streaming image to ${direct_host}:${LIVE_STREAM_PORT} -> ${DEVICE} ..."
    remote_ssh "
      set -eu
      rm -f $(quote_for_sh "$remote_stream_pid_file") $(quote_for_sh "$remote_stream_log")
      $(quote_for_sh "$REMOTE_BUSYBOX") sh -c $(quote_for_sh "$remote_stream_cmd") >$(quote_for_sh "$remote_stream_log") 2>&1 &
      echo \$! >$(quote_for_sh "$remote_stream_pid_file")
    "

    sleep 1

    "${READ_CMD[@]}" |
      "$PV_BIN" -N Read -s "$SIZE_BYTES" |
      zstd -1 -T0 |
      "$PV_BIN" -N Transfer |
      nc -N "$direct_host" "$LIVE_STREAM_PORT" ||
      die "Direct live stream failed"

    for _ in $(seq 1 300); do
      if remote_ssh_quiet "
        pid=\$(cat $(quote_for_sh "$remote_stream_pid_file") 2>/dev/null || true)
        [ -n \"\${pid:-}\" ] && kill -0 \"\$pid\" 2>/dev/null
      "; then
        sleep 1
      else
        break
      fi
    done

    if remote_ssh_quiet "
      pid=\$(cat $(quote_for_sh "$remote_stream_pid_file") 2>/dev/null || true)
      [ -n \"\${pid:-}\" ] && kill -0 \"\$pid\" 2>/dev/null
    "; then
      print_live_ssh_debug
      remote_ssh "cat $(quote_for_sh "$remote_stream_log") 2>/dev/null || true" || true
      die "Timed out waiting for remote live stream receiver to finish"
    fi
    return
  fi

  log "Phase 2: Streaming image to ${TARGET_HOST}:${DEVICE} ..."
  "${READ_CMD[@]}" |
    "$PV_BIN" -N Read -s "$SIZE_BYTES" |
    "${COMPRESS_CMD[@]}" |
    "$PV_BIN" -N Transfer |
    remote_ssh "$DECOMPRESS_CMD | dd of=$DEVICE bs=$bs conv=fsync status=none" ||
    die "Remote dd failed"
}

finish_deployment() {
  log "Syncing remote disk..."
  if is_true "$LIVE_OVERWRITE"; then
    log "LIVE OVERWRITE: Sending forced reboot signal..."
    if [ -n "$REMOTE_BUSYBOX" ]; then
      remote_ssh_quiet "$REMOTE_BUSYBOX sync && $REMOTE_BUSYBOX reboot -f" ||
        log "Busybox reboot dispatched (connection loss is expected)"
    else
      remote_ssh_quiet "echo b >/proc/sysrq-trigger" ||
        log "Sysrq reboot dispatched (connection loss is expected)"
    fi
    log "Deployment finished. Target should be rebooting into NixOS now."
    return
  fi

  remote_ssh "sync"
  log "Deployment finished successfully. You may now reboot the target manually."
}

main() {
  parse_args "$@"

  if ! is_true "$ONLY_STREAM"; then
    build_image
  fi

  if is_true "$ONLY_BUILD"; then
    log "Build complete. Run with --only-stream to deploy."
    exit 0
  fi

  if is_true "$ONLY_STREAM"; then
    resolve_cached_image
  fi

  setup_ssh_command
  setup_ssh_mux
  prepare_pipeline_tools

  if is_true "$LIVE_OVERWRITE"; then
    prepare_live_overwrite
  fi

  stream_image
  finish_deployment
}

main "$@"
