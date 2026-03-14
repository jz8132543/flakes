#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[deploy-reinstall-dd] %s\n' "$*" >&2
}

die() {
  printf '[deploy-reinstall-dd] %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  deploy-reinstall-dd.sh --target-host <user@host> [options]

Options:
  --host NAME               Flake host name, e.g. can0 (required unless --image or --img-url)
  --target-host USER@HOST   Remote SSH target
  --device PATH             Remote target disk (default: /dev/vda)
  --port PORT               SSH port (default: 22)
  --reinstall-ssh-port PORT SSH port passed to reinstall.sh (default: same as --port)
  --identity-file PATH      SSH private key for Alpine login (auto-detected from public key by default)
  --public-key-file PATH    SSH public key injected into Alpine live env (default: auto-detect from ~/.ssh/*.pub)
  --public-key TEXT         SSH public key content (overrides --public-key-file)
  --password PASSWORD       Password passed to reinstall.sh (optional)
  --reinstall-script PATH   Local reinstall.sh path (default: /tmp/reinstall/reinstall.sh)
  --img-url URL             Download image to local cache first, then stream to Alpine (target has no network)
  --image PATH              Existing local image path (skip build/download)
  --target ATTR             Nix flake image target
                            (default: .#nixosConfigurations.<host>.config.system.build.diskoImages)
  --cache-dir DIR           Local cache dir for downloaded images (default: /tmp/deploy-reinstall-dd-cache)
  --zstd-level N            Local zstd compression level for streaming (default: 1)
  --zstd-threads N          Local zstd threads: 0=auto, 1..N=fixed (default: 0)
  --retry-max N             Max retries for network-sensitive SSH actions (default: 0, infinite)
  --retry-interval SEC      Retry interval seconds (default: 5)
  --no-progress             Disable local transfer progress bar (pv)
  --hold-time SEC           Wait time after dispatching reboot-to-alpine (default: 15)
  --wait-timeout SEC        Max wait for Alpine SSH to come up (default: 900)
  --skip-alpine-step        Skip stage 1 and assume target is already Alpine live
  --dd-only                 Skip stage 1 and run dd-only flow on current Alpine
  --skip-deps-check         Skip local/remote dependency checks
  --no-upload-zstd          Do not upload local zstd binary when remote zstd is missing
  -h, --help                Show help

Behavior:
  1) Stage 1: run reinstall.sh alpine --hold 1 with your SSH public key, then trigger reboot
  2) Wait for target reboot into Alpine Live OS (strictly verify ID=alpine)
  3) Build/download image locally (never require target internet)
  4) Stream image: local zstd -> SSH -> remote zstd -d -> dd of=<device>
  5) Print missing dependency list (local + remote)
  6) Show transfer progress bar when local pv is available
EOF
  exit 1
}

HOST=""
TARGET_HOST=""
DEVICE="/dev/vda"
PORT=22
REINSTALL_SSH_PORT=""
IDENTITY_FILE=""
PUBLIC_KEY_FILE=""
PUBLIC_KEY_TEXT=""
PASSWORD=""
REINSTALL_SCRIPT="/tmp/reinstall/reinstall.sh"
IMG_URL=""
IMAGE_PATH=""
FLAKE_TARGET=""
CACHE_DIR="/tmp/deploy-reinstall-dd-cache"
ZSTD_LEVEL=10
ZSTD_THREADS=0
RETRY_MAX=0
RETRY_INTERVAL=5
HOLD_TIME=15
WAIT_TIMEOUT=900
SKIP_ALPINE_STEP="no"
DD_ONLY="no"
SKIP_DEPS_CHECK="no"
REMOTE_ZSTD_PATH="/tmp/deploy-reinstall-zstd"
UPLOAD_ZSTD_IF_MISSING="yes"
SHOW_PROGRESS="yes"

SSH_OPTS=()
LOCAL_MISSING_DEPS=()
REMOTE_MISSING_DEPS=()
REMOTE_STREAM_CODEC=""
REMOTE_ZSTD_DECODER_CMD="zstd"
LOCAL_PV_CMD=""

quote_for_sh() {
  local value="$1"
  printf "'%s'" "${value//\'/\'\\\'\'}"
}

is_valid_pubkey() {
  local line="$1"
  grep -qE '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)) ' <<<"$line"
}

detect_public_key_file() {
  local candidates=()
  local c

  if [ -n "$PUBLIC_KEY_FILE" ]; then
    [ -f "$PUBLIC_KEY_FILE" ] || die "--public-key-file not found: $PUBLIC_KEY_FILE"
    return 0
  fi

  if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
    PUBLIC_KEY_FILE="$HOME/.ssh/id_ed25519.pub"
    return 0
  fi

  while IFS= read -r c; do
    candidates+=("$c")
  done < <(find "$HOME/.ssh" -maxdepth 1 -type f -name '*.pub' 2>/dev/null | sort)

  for c in "${candidates[@]}"; do
    if [ -s "$c" ]; then
      PUBLIC_KEY_FILE="$c"
      return 0
    fi
  done

  die "No public key found under ~/.ssh. Please pass --public-key-file or --public-key"
}

resolve_public_key_text() {
  if [ -n "$PUBLIC_KEY_TEXT" ]; then
    is_valid_pubkey "$PUBLIC_KEY_TEXT" || die "--public-key is not a valid SSH public key"
    return 0
  fi

  detect_public_key_file
  PUBLIC_KEY_TEXT="$(awk 'NF{print; exit}' "$PUBLIC_KEY_FILE")"
  [ -n "$PUBLIC_KEY_TEXT" ] || die "Public key file is empty: $PUBLIC_KEY_FILE"
  is_valid_pubkey "$PUBLIC_KEY_TEXT" || die "Invalid SSH public key format in: $PUBLIC_KEY_FILE"
}

resolve_identity_file() {
  if [ -n "$IDENTITY_FILE" ]; then
    [ -f "$IDENTITY_FILE" ] || die "--identity-file not found: $IDENTITY_FILE"
    return 0
  fi

  if [ -n "$PUBLIC_KEY_FILE" ]; then
    local candidate="${PUBLIC_KEY_FILE%.pub}"
    if [ -f "$candidate" ]; then
      IDENTITY_FILE="$candidate"
      return 0
    fi
  fi

  if [ -f "$HOME/.ssh/id_ed25519" ]; then
    IDENTITY_FILE="$HOME/.ssh/id_ed25519"
    return 0
  fi

  die "No private key found. Please pass --identity-file"
}

is_nonnegative_integer() {
  [[ $1 =~ ^[0-9]+$ ]]
}

is_positive_integer() {
  [[ $1 =~ ^[1-9][0-9]*$ ]]
}

retry_log_and_wait() {
  local action="$1"
  local attempt="$2"
  local rc="$3"

  if [ "$RETRY_MAX" -gt 0 ]; then
    log "$action failed (rc=$rc), retrying in ${RETRY_INTERVAL}s (attempt ${attempt}/${RETRY_MAX})"
  else
    log "$action failed (rc=$rc), retrying in ${RETRY_INTERVAL}s (attempt ${attempt}, max=infinite)"
  fi
  sleep "$RETRY_INTERVAL"
}

retry_limit_reached() {
  local attempt="$1"
  [ "$RETRY_MAX" -gt 0 ] && [ "$attempt" -ge "$RETRY_MAX" ]
}

is_retryable_ssh_rc() {
  local rc="$1"
  [ "$rc" -eq 255 ]
}

refresh_ssh_opts() {
  SSH_OPTS=(
    -p "$PORT"
    -o StrictHostKeyChecking=accept-new
    -o ControlMaster=no
    -o Compression=no
    -o IPQoS=throughput
    -o ConnectTimeout=6
    -o BatchMode=yes
    -i "$IDENTITY_FILE"
  )
}

run_ssh() {
  ssh "$@"
}

run_ssh_quiet_true() {
  run_ssh "$@" "true" >/dev/null 2>&1
}

bootstrap_pubkey_after_password_login() {
  local escaped_key
  escaped_key="${PUBLIC_KEY_TEXT//\'/\'\\\'\'}"

  log "Key auth unavailable, falling back to interactive SSH password input to install public key"
  ssh \
    -p "$PORT" \
    -o StrictHostKeyChecking=accept-new \
    -o ControlMaster=no \
    -o Compression=no \
    -o IPQoS=throughput \
    -o ConnectTimeout=6 \
    -o BatchMode=no \
    -o NumberOfPasswordPrompts=3 \
    -o PreferredAuthentications=publickey,password,keyboard-interactive \
    -i "$IDENTITY_FILE" \
    "$TARGET_HOST" \
    "set -eu; umask 077; mkdir -p ~/.ssh; touch ~/.ssh/authorized_keys; chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys; grep -Fqx -- '$escaped_key' ~/.ssh/authorized_keys || printf '%s\\n' '$escaped_key' >> ~/.ssh/authorized_keys"

  refresh_ssh_opts
  if ! run_ssh_quiet_true "${SSH_OPTS[@]}" "$TARGET_HOST"; then
    die "Public key bootstrap failed: cannot switch to key-based login"
  fi
  log "Public key installed successfully; switched to key-based auth"
}

setup_auth_mode() {
  refresh_ssh_opts

  if run_ssh_quiet_true "${SSH_OPTS[@]}" "$TARGET_HOST"; then
    log "SSH auth mode: key"
    return 0
  fi

  bootstrap_pubkey_after_password_login
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
    --host)
      HOST="$2"
      shift 2
      ;;
    --target-host)
      TARGET_HOST="$2"
      shift 2
      ;;
    --device)
      DEVICE="$2"
      shift 2
      ;;
    --port)
      PORT="$2"
      shift 2
      ;;
    --reinstall-ssh-port)
      REINSTALL_SSH_PORT="$2"
      shift 2
      ;;
    --identity-file)
      IDENTITY_FILE="$2"
      shift 2
      ;;
    --public-key-file)
      PUBLIC_KEY_FILE="$2"
      shift 2
      ;;
    --public-key)
      PUBLIC_KEY_TEXT="$2"
      shift 2
      ;;
    --password)
      PASSWORD="$2"
      shift 2
      ;;
    --reinstall-script)
      REINSTALL_SCRIPT="$2"
      shift 2
      ;;
    --img-url)
      IMG_URL="$2"
      shift 2
      ;;
    --image)
      IMAGE_PATH="$2"
      shift 2
      ;;
    --target)
      FLAKE_TARGET="$2"
      shift 2
      ;;
    --cache-dir)
      CACHE_DIR="$2"
      shift 2
      ;;
    --zstd-level)
      ZSTD_LEVEL="$2"
      shift 2
      ;;
    --zstd-threads)
      ZSTD_THREADS="$2"
      shift 2
      ;;
    --retry-max)
      RETRY_MAX="$2"
      shift 2
      ;;
    --retry-interval)
      RETRY_INTERVAL="$2"
      shift 2
      ;;
    --hold-time)
      HOLD_TIME="$2"
      shift 2
      ;;
    --wait-timeout)
      WAIT_TIMEOUT="$2"
      shift 2
      ;;
    --skip-alpine-step)
      SKIP_ALPINE_STEP="yes"
      shift
      ;;
    --dd-only)
      DD_ONLY="yes"
      SKIP_ALPINE_STEP="yes"
      shift
      ;;
    --skip-deps-check)
      SKIP_DEPS_CHECK="yes"
      shift
      ;;
    --no-upload-zstd)
      UPLOAD_ZSTD_IF_MISSING="no"
      shift
      ;;
    --no-progress)
      SHOW_PROGRESS="no"
      shift
      ;;
    -h | --help)
      usage
      ;;
    *)
      die "Unknown argument: $1"
      ;;
    esac
  done

  [ -n "$TARGET_HOST" ] || die "--target-host is required"

  case "$DEVICE" in
  /dev/*) ;;
  *) die "--device must be a /dev path, got: $DEVICE" ;;
  esac

  if [ -z "$IMAGE_PATH" ] && [ -z "$IMG_URL" ]; then
    [ -n "$HOST" ] || die "--host is required unless --image or --img-url is set"
  fi

  if [ -z "$FLAKE_TARGET" ] && [ -n "$HOST" ]; then
    FLAKE_TARGET=".#nixosConfigurations.${HOST}.config.system.build.diskoImages"
  fi

  is_positive_integer "$PORT" || die "--port must be a positive integer"
  if [ -n "$REINSTALL_SSH_PORT" ]; then
    is_positive_integer "$REINSTALL_SSH_PORT" || die "--reinstall-ssh-port must be a positive integer"
  else
    REINSTALL_SSH_PORT="$PORT"
  fi
  is_nonnegative_integer "$HOLD_TIME" || die "--hold-time must be >= 0"
  is_positive_integer "$WAIT_TIMEOUT" || die "--wait-timeout must be > 0"
  if ! is_nonnegative_integer "$ZSTD_LEVEL" || [ "$ZSTD_LEVEL" -lt 1 ] || [ "$ZSTD_LEVEL" -gt 22 ]; then
    die "--zstd-level must be between 1 and 22"
  fi
  is_nonnegative_integer "$ZSTD_THREADS" || die "--zstd-threads must be >= 0 (0 means auto)"
  is_nonnegative_integer "$RETRY_MAX" || die "--retry-max must be >= 0 (0 means infinite)"
  is_positive_integer "$RETRY_INTERVAL" || die "--retry-interval must be > 0"

  resolve_public_key_text
  resolve_identity_file
  refresh_ssh_opts
}

append_missing_dep() {
  local arr_name="$1"
  local dep="$2"
  if [ "$arr_name" = "local" ]; then
    LOCAL_MISSING_DEPS+=("$dep")
  else
    REMOTE_MISSING_DEPS+=("$dep")
  fi
}

check_local_deps() {
  local required=(ssh find awk sed mktemp basename dirname zstd)
  local c

  for c in "${required[@]}"; do
    if ! command -v "$c" >/dev/null 2>&1; then
      append_missing_dep local "$c"
    fi
  done

  if [ -z "$IMAGE_PATH" ] && [ -z "$IMG_URL" ]; then
    command -v nix >/dev/null 2>&1 || append_missing_dep local nix
  fi

  if [ -n "$IMG_URL" ]; then
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
      append_missing_dep local "curl|wget"
    fi
  fi

  if [ -n "$IMAGE_PATH" ]; then
    case "$IMAGE_PATH" in
    *.gz)
      command -v gzip >/dev/null 2>&1 || append_missing_dep local gzip
      ;;
    *.xz)
      command -v xz >/dev/null 2>&1 || append_missing_dep local xz
      ;;
    esac
  fi

}

check_remote_deps() {
  local out=""
  local attempt=0
  local rc=0

  while true; do
    if out="$(
      run_ssh "${SSH_OPTS[@]}" "$TARGET_HOST" "sh -s" <<'EOF'
set -eu
for c in dd sync; do
  command -v "$c" >/dev/null 2>&1 || echo "$c"
done

if command -v zstd >/dev/null 2>&1; then
  echo "__codec=zstd"
elif command -v gzip >/dev/null 2>&1; then
  echo "__codec=gzip"
elif command -v cat >/dev/null 2>&1; then
  echo "__codec=none"
else
  echo "cat"
fi
EOF
    )"; then
      break
    fi

    rc=$?
    if ! is_retryable_ssh_rc "$rc"; then
      die "check_remote_deps failed with non-retryable rc=$rc"
    fi
    attempt=$((attempt + 1))
    if retry_limit_reached "$attempt"; then
      die "check_remote_deps failed after ${attempt} attempts (rc=$rc)"
    fi
    retry_log_and_wait "check_remote_deps" "$attempt" "$rc"
  done

  REMOTE_STREAM_CODEC=""
  REMOTE_ZSTD_DECODER_CMD="zstd"
  if [ -n "$out" ]; then
    while IFS= read -r c; do
      [ -n "$c" ] || continue
      case "$c" in
      __codec=*)
        REMOTE_STREAM_CODEC="${c#__codec=}"
        continue
        ;;
      esac
      append_missing_dep remote "$c"
    done <<<"$out"
  fi

  if [ -z "$REMOTE_STREAM_CODEC" ]; then
    REMOTE_STREAM_CODEC="zstd"
  fi
}

upload_remote_zstd_if_needed() {
  local local_zstd
  local static_zstd
  local static_out
  local remote_tmp
  local attempt=0
  local rc=0

  [ "$UPLOAD_ZSTD_IF_MISSING" = "yes" ] || return 0
  [ "$REMOTE_STREAM_CODEC" = "zstd" ] && return 0

  static_zstd="/nix/store/mk1s23axm8cqvckk59gdrdshxj35svmc-zstd-static-x86_64-unknown-linux-musl-1.5.7-bin/bin/zstd"
  if [ -x "$static_zstd" ]; then
    local_zstd="$static_zstd"
  elif command -v nix >/dev/null 2>&1; then
    static_out="$(nix --extra-experimental-features 'nix-command flakes' build --no-link --print-out-paths nixpkgs#pkgsStatic.zstd 2>/dev/null || true)"
    local_zstd="$(printf '%s\n' "$static_out" | awk '/-bin$/ {print $0 "/bin/zstd"; exit}')"
    [ -n "$local_zstd" ] || local_zstd="$(printf '%s\n' "$static_out" | awk '{print $0 "/bin/zstd"; exit}')"
  fi

  if [ -z "$local_zstd" ] || [ ! -x "$local_zstd" ]; then
    local_zstd="$(command -v zstd || true)"
  fi

  [ -n "$local_zstd" ] || return 0

  log "Remote zstd missing, uploading local zstd binary ($local_zstd) to $REMOTE_ZSTD_PATH"
  remote_tmp="${REMOTE_ZSTD_PATH}.tmp.$$"
  while true; do
    if cat "$local_zstd" | run_ssh "${SSH_OPTS[@]}" "$TARGET_HOST" \
      "export PATH=/sbin:/bin:/usr/sbin:/usr/bin:\$PATH; rm -f $(quote_for_sh "$REMOTE_ZSTD_PATH") $(quote_for_sh "$remote_tmp"); cat >$(quote_for_sh "$remote_tmp") && chmod 0755 $(quote_for_sh "$remote_tmp") && mv -f $(quote_for_sh "$remote_tmp") $(quote_for_sh "$REMOTE_ZSTD_PATH")"; then
      break
    fi

    rc=$?
    if ! is_retryable_ssh_rc "$rc"; then
      die "upload_remote_zstd_if_needed failed with non-retryable rc=$rc"
    fi
    attempt=$((attempt + 1))
    if retry_limit_reached "$attempt"; then
      die "upload_remote_zstd_if_needed failed after ${attempt} attempts (rc=$rc)"
    fi
    retry_log_and_wait "upload_remote_zstd_if_needed" "$attempt" "$rc"
  done

  attempt=0
  while true; do
    if run_ssh "${SSH_OPTS[@]}" "$TARGET_HOST" "$(quote_for_sh "$REMOTE_ZSTD_PATH") -V >/dev/null 2>&1"; then
      REMOTE_STREAM_CODEC="zstd"
      REMOTE_ZSTD_DECODER_CMD="$REMOTE_ZSTD_PATH"
      log "Uploaded zstd works on remote; switching stream codec back to zstd"
      return 0
    fi

    rc=$?
    if ! is_retryable_ssh_rc "$rc"; then
      log "Uploaded zstd verification failed with non-retryable rc=$rc, keep fallback codec=$REMOTE_STREAM_CODEC"
      return 0
    fi
    attempt=$((attempt + 1))
    if retry_limit_reached "$attempt"; then
      log "Uploaded zstd verification failed after ${attempt} attempts (rc=$rc), keep fallback codec=$REMOTE_STREAM_CODEC"
      return 0
    fi
    retry_log_and_wait "verify_uploaded_zstd" "$attempt" "$rc"
  done
}

report_missing_deps() {
  if [ "${#LOCAL_MISSING_DEPS[@]}" -eq 0 ] && [ "${#REMOTE_MISSING_DEPS[@]}" -eq 0 ]; then
    log "Dependency check: OK"
    return 0
  fi

  log "Dependency check: missing dependencies detected"
  if [ "${#LOCAL_MISSING_DEPS[@]}" -gt 0 ]; then
    log "Missing local deps: ${LOCAL_MISSING_DEPS[*]}"
  fi
  if [ "${#REMOTE_MISSING_DEPS[@]}" -gt 0 ]; then
    log "Missing remote deps: ${REMOTE_MISSING_DEPS[*]}"
  fi
}

ensure_reinstall_script() {
  if [ -f "$REINSTALL_SCRIPT" ]; then
    return 0
  fi

  mkdir -p "$(dirname "$REINSTALL_SCRIPT")"
  if command -v curl >/dev/null 2>&1; then
    log "Downloading reinstall.sh -> $REINSTALL_SCRIPT"
    curl -fsSL https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh -o "$REINSTALL_SCRIPT" ||
      die "Failed to download reinstall.sh by curl"
  elif command -v wget >/dev/null 2>&1; then
    log "Downloading reinstall.sh -> $REINSTALL_SCRIPT"
    wget -qO "$REINSTALL_SCRIPT" https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh ||
      die "Failed to download reinstall.sh by wget"
  else
    die "reinstall.sh not found and neither curl nor wget is available"
  fi

  chmod +x "$REINSTALL_SCRIPT"
}

run_alpine_hold() {
  local attempt=0
  local rc=0

  ensure_reinstall_script

  log "Stage 1: rebooting target into Alpine Live OS (--hold 1, key login enabled)"
  while true; do
    if run_ssh "${SSH_OPTS[@]}" "$TARGET_HOST" \
      "bash -s -- alpine --hold 1 --ssh-port '$REINSTALL_SSH_PORT' --ssh-key $(quote_for_sh "$PUBLIC_KEY_TEXT") ${PASSWORD:+--password $(quote_for_sh "$PASSWORD")}" \
      <"$REINSTALL_SCRIPT"; then
      break
    fi

    rc=$?
    if ! is_retryable_ssh_rc "$rc"; then
      die "Stage 1 failed: cannot execute reinstall.sh on target (rc=$rc)"
    fi

    attempt=$((attempt + 1))
    if retry_limit_reached "$attempt"; then
      die "Stage 1 failed after ${attempt} attempts (rc=$rc)"
    fi
    retry_log_and_wait "stage1_dispatch" "$attempt" "$rc"
  done

  log "Stage 1 command dispatched, triggering reboot now"
  attempt=0
  while true; do
    if run_ssh "${SSH_OPTS[@]}" "$TARGET_HOST" "nohup sh -c 'sleep 1; reboot' >/dev/null 2>&1 &"; then
      break
    fi

    rc=$?
    if ! is_retryable_ssh_rc "$rc"; then
      die "Stage 1 failed: unable to trigger reboot (rc=$rc)"
    fi

    attempt=$((attempt + 1))
    if retry_limit_reached "$attempt"; then
      die "Stage 1 reboot trigger failed after ${attempt} attempts (rc=$rc)"
    fi
    retry_log_and_wait "stage1_reboot_trigger" "$attempt" "$rc"
  done
}

remote_os_id() {
  run_ssh "${SSH_OPTS[@]}" -o ConnectTimeout=3 "$TARGET_HOST" "awk -F= '/^ID=/{gsub(/\"/, \"\", \$2); print \$2; exit}' /etc/os-release 2>/dev/null || true" 2>/dev/null || true
}

wait_for_ssh_disconnect() {
  local timeout="$1"
  local start now elapsed

  start="$(date +%s)"
  while true; do
    if ! run_ssh "${SSH_OPTS[@]}" -o ConnectTimeout=3 "$TARGET_HOST" "true" >/dev/null 2>&1; then
      log "Target SSH disconnected, reboot in progress"
      return 0
    fi

    now="$(date +%s)"
    elapsed=$((now - start))
    if [ "$elapsed" -ge "$timeout" ]; then
      die "Timed out waiting for SSH disconnect after reboot trigger (${timeout}s)"
    fi

    sleep 2
  done
}

wait_for_alpine_online() {
  local timeout="$1"
  local start now elapsed os_id

  start="$(date +%s)"
  sleep "$HOLD_TIME"

  log "Waiting for target to reboot and come back as Alpine..."
  while true; do
    os_id="$(remote_os_id)"
    if [ "$os_id" = "alpine" ]; then
      log "Target is reachable and confirmed as Alpine (ID=alpine)"
      return 0
    fi

    now="$(date +%s)"
    elapsed=$((now - start))
    if [ "$elapsed" -ge "$timeout" ]; then
      if [ -n "$os_id" ]; then
        die "Timed out waiting for Alpine after ${timeout}s (current remote ID=$os_id)"
      fi
      die "Timed out waiting for Alpine SSH after ${timeout}s"
    fi

    sleep 3
  done
}

require_remote_alpine_now() {
  local os_id
  os_id="$(remote_os_id)"
  if [ "$os_id" != "alpine" ]; then
    die "--skip-alpine-step was set, but remote OS is not Alpine (ID=${os_id:-unknown}); refusing to run dd"
  fi
  log "Remote OS already Alpine (ID=alpine)"
}

build_image_from_nix() {
  local out image

  [ -n "$FLAKE_TARGET" ] || die "No flake target available to build image"

  log "Building image via nix: $FLAKE_TARGET"
  out="$(nix build --no-link --print-out-paths --experimental-features 'nix-command flakes' "$FLAKE_TARGET")"

  image="$(find "$out" -maxdepth 3 -type f \( -name '*.raw' -o -name '*.img' -o -name '*.qcow2' -o -name '*.vhd' -o -name '*.zst' -o -name '*.gz' -o -name '*.xz' \) | head -1)"
  [ -n "$image" ] || die "No image file found in build output: $out"

  printf '%s\n' "$image"
}

download_image_to_local() {
  local url="$1"
  local filename out

  mkdir -p "$CACHE_DIR"
  filename="${url##*/}"
  [ -n "$filename" ] || filename="downloaded-image.raw"
  out="$CACHE_DIR/$filename"

  if [ -s "$out" ]; then
    log "Using cached downloaded image: $out"
    printf '%s\n' "$out"
    return 0
  fi

  if command -v curl >/dev/null 2>&1; then
    log "Downloading image locally by curl: $url"
    curl -fL "$url" -o "$out" || die "Download failed: $url"
  elif command -v wget >/dev/null 2>&1; then
    log "Downloading image locally by wget: $url"
    wget -O "$out" "$url" || die "Download failed: $url"
  else
    die "Neither curl nor wget is available to download --img-url"
  fi

  printf '%s\n' "$out"
}

prepare_local_image() {
  local src

  if [ -n "$IMAGE_PATH" ]; then
    [ -f "$IMAGE_PATH" ] || die "--image not found: $IMAGE_PATH"
    src="$IMAGE_PATH"
  elif [ -n "$IMG_URL" ]; then
    src="$(download_image_to_local "$IMG_URL")"
  else
    src="$(build_image_from_nix)"
  fi

  [ -f "$src" ] || die "Prepared local image not found: $src"

  printf '%s\n' "$src"
}

emit_local_raw_stream() {
  local src="$1"

  case "$src" in
  *.zst)
    command -v zstd >/dev/null 2>&1 || die "zstd is required to read $src"
    zstd -q -d -c "$src"
    ;;
  *.gz)
    command -v gzip >/dev/null 2>&1 || die "gzip is required to read $src"
    gzip -dc "$src"
    ;;
  *.xz)
    command -v xz >/dev/null 2>&1 || die "xz is required to read $src"
    xz -dc "$src"
    ;;
  *.tar | *.tar.gz | *.tar.xz | *.tar.zst)
    die "Tar archives are not supported by this script: $src"
    ;;
  *)
    cat "$src"
    ;;
  esac
}

stream_local_with_progress() {
  local src="$1"
  local total=""

  if [ "$SHOW_PROGRESS" = "yes" ] && [ -n "$LOCAL_PV_CMD" ]; then
    case "$src" in
    *.raw | *.img | *.qcow2 | *.vhd)
      total="$(wc -c <"$src" | tr -d ' ')"
      emit_local_raw_stream "$src" | "$LOCAL_PV_CMD" -p -t -e -r -b -s "$total"
      ;;
    *)
      emit_local_raw_stream "$src" | "$LOCAL_PV_CMD" -p -t -e -r -b
      ;;
    esac
  else
    emit_local_raw_stream "$src"
  fi
}

resolve_local_pv_cmd() {
  local static_pv
  local static_out

  LOCAL_PV_CMD=""

  [ "$SHOW_PROGRESS" = "yes" ] || return 0

  if command -v pv >/dev/null 2>&1; then
    LOCAL_PV_CMD="$(command -v pv)"
    return 0
  fi

  static_pv="/nix/store/9yvh8jlwmz6kpr2ifj5w07j6m4kwyxby-pv-static-x86_64-unknown-linux-musl-1.9.34-bin/bin/pv"
  if [ -x "$static_pv" ]; then
    LOCAL_PV_CMD="$static_pv"
    log "Using bundled static pv: $LOCAL_PV_CMD"
    return 0
  fi

  if command -v nix >/dev/null 2>&1; then
    static_out="$(nix --extra-experimental-features 'nix-command flakes' build --no-link --print-out-paths nixpkgs#pkgsStatic.pv 2>/dev/null || true)"
    LOCAL_PV_CMD="$(printf '%s\n' "$static_out" | awk '/-bin$/ {print $0 "/bin/pv"; exit}')"
    [ -n "$LOCAL_PV_CMD" ] || LOCAL_PV_CMD="$(printf '%s\n' "$static_out" | awk '{print $0 "/bin/pv"; exit}')"
    if [ -n "$LOCAL_PV_CMD" ] && [ -x "$LOCAL_PV_CMD" ]; then
      log "Using fetched static pv: $LOCAL_PV_CMD"
      return 0
    fi
  fi

  log "Progress bar disabled: local pv not found and static pv unavailable"
  SHOW_PROGRESS="no"
}

stream_dd_once() {
  local local_img="$1"

  case "$REMOTE_STREAM_CODEC" in
  zstd)
    log "Stage 2: using remote zstd decoder ($REMOTE_ZSTD_DECODER_CMD); local zstd -$ZSTD_LEVEL -T$ZSTD_THREADS"
    stream_local_with_progress "$local_img" |
      zstd -q -"$ZSTD_LEVEL" -T"$ZSTD_THREADS" -c |
      run_ssh "${SSH_OPTS[@]}" "$TARGET_HOST" "export PATH=/sbin:/bin:/usr/sbin:/usr/bin:\$PATH; set -eu; [ -b $(quote_for_sh "$DEVICE") ] || { echo 'target block device missing: $DEVICE' >&2; exit 1; }; $(quote_for_sh "$REMOTE_ZSTD_DECODER_CMD") -q -d -c | dd of=$(quote_for_sh "$DEVICE") bs=16M conv=fsync; sync"
    ;;
  gzip)
    log "Stage 2: remote zstd missing, fallback to gzip stream"
    stream_local_with_progress "$local_img" |
      gzip -1 -c |
      run_ssh "${SSH_OPTS[@]}" "$TARGET_HOST" "export PATH=/sbin:/bin:/usr/sbin:/usr/bin:\$PATH; set -eu; [ -b $(quote_for_sh "$DEVICE") ] || { echo 'target block device missing: $DEVICE' >&2; exit 1; }; gzip -d -c | dd of=$(quote_for_sh "$DEVICE") bs=16M conv=fsync; sync"
    ;;
  none)
    log "Stage 2: remote zstd/gzip missing, fallback to raw stream"
    stream_local_with_progress "$local_img" |
      run_ssh "${SSH_OPTS[@]}" "$TARGET_HOST" "export PATH=/sbin:/bin:/usr/sbin:/usr/bin:\$PATH; set -eu; [ -b $(quote_for_sh "$DEVICE") ] || { echo 'target block device missing: $DEVICE' >&2; exit 1; }; dd of=$(quote_for_sh "$DEVICE") bs=16M conv=fsync; sync"
    ;;
  *)
    die "Unsupported REMOTE_STREAM_CODEC: $REMOTE_STREAM_CODEC"
    ;;
  esac

  return 0
}

stream_dd_to_remote() {
  local local_img="$1"
  local attempt=0
  local rc=0

  while true; do
    check_remote_deps
    upload_remote_zstd_if_needed

    if stream_dd_once "$local_img"; then
      log "DD completed"
      return 0
    fi

    rc=$?
    if ! is_retryable_ssh_rc "$rc"; then
      die "Stage 2 failed with non-retryable rc=$rc"
    fi

    attempt=$((attempt + 1))
    if retry_limit_reached "$attempt"; then
      die "Stage 2 failed after ${attempt} retry attempts (rc=$rc)"
    fi

    retry_log_and_wait "stage2_stream_dd" "$attempt" "$rc"
    log "Retrying Stage 2 from beginning (full stream retransmit)"
  done
}

main() {
  parse_args "$@"
  setup_auth_mode

  if [ "$SKIP_DEPS_CHECK" != "yes" ]; then
    check_local_deps
    if [ "${#LOCAL_MISSING_DEPS[@]}" -gt 0 ]; then
      report_missing_deps
      die "Please install missing local dependencies first"
    fi
  fi

  if [ "$SKIP_ALPINE_STEP" != "yes" ]; then
    run_alpine_hold
    wait_for_ssh_disconnect 180
    wait_for_alpine_online "$WAIT_TIMEOUT"
  else
    if [ "$DD_ONLY" = "yes" ]; then
      log "DD-only mode: skipping stage 1 and running direct dd flow"
    else
      log "Skipping stage 1 as requested (--skip-alpine-step)"
    fi
    require_remote_alpine_now
  fi

  if [ "$SKIP_DEPS_CHECK" != "yes" ]; then
    check_remote_deps
    report_missing_deps
    if [ "${#REMOTE_MISSING_DEPS[@]}" -gt 0 ]; then
      die "Please install missing remote dependencies in Alpine and rerun"
    fi
  fi

  local local_img
  local_img="$(prepare_local_image)"
  resolve_local_pv_cmd
  stream_dd_to_remote "$local_img"

  log "All done. Image was downloaded/built locally and streamed to target with immediate dd."
}

main "$@"
