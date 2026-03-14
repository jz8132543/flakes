#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: deploy-live-kexec.sh --host NAME --target-host user@host --device /dev/sdX [options]

Options:
  --port PORT                  SSH port for the initial host (default: 22)
  --identity-file PATH         SSH private key for the initial connection
  --remote-path-prefix PATHS   Colon-separated PATH entries prepended for remote non-login shells
  --device PATH                Target block device to overwrite
  --alpine-release NAME        Alpine release path (default: latest-stable)
  --alpine-mirror URL          Alpine mirror root (default: https://dl-cdn.alpinelinux.org/alpine)
  --alpine-flavor NAME         Alpine netboot flavor (default: virt)
  --trampoline-port PORT       SSH port exposed by the in-memory trampoline (default: same as --port)

Behavior:
1. Build or reuse the target raw image locally.
2. Download Alpine netboot kernel/initramfs locally.
3. Build a tiny SSH trampoline initramfs and kexec into it on the target.
4. Reconnect automatically to the in-memory trampoline.
5. Reuse deploy-raw-image.sh --only-stream to write the image safely from RAM.
EOF
  exit 1
}

log() {
  printf '[deploy-live-kexec] %s\n' "$*"
}

die() {
  printf '[deploy-live-kexec] %s\n' "$*" >&2
  exit 1
}

HOST=""
TARGET_HOST=""
PORT=22
DEVICE=""
IDENTITY_FILE=""
REMOTE_PATH_PREFIX=""
ALPINE_RELEASE="latest-stable"
ALPINE_MIRROR="https://dl-cdn.alpinelinux.org/alpine"
ALPINE_FLAVOR="virt"
TRAMPOLINE_PORT=""

TARGET_SYSTEM=""
ALPINE_ARCH=""
TEMP_DIR=""
INITIAL_AUTH_MODE=""
REMOTE_ROOT="/run/nixos-kexec"
REMOTE_BUSYBOX="${REMOTE_ROOT}/busybox"
REMOTE_KEXEC="${REMOTE_ROOT}/kexec"
REMOTE_KERNEL="${REMOTE_ROOT}/vmlinuz"
REMOTE_INITRAMFS="${REMOTE_ROOT}/initramfs"
TRAMPOLINE_IDENTITY_FILE=""
INITIAL_AUTHORIZED_KEYS_FILE=""
LOCAL_BUSYBOX=""
LOCAL_DROPBEAR=""
LOCAL_DROPBEARKEY=""
LOCAL_KEXEC=""
LOCAL_KERNEL=""
LOCAL_INITRAMFS=""
LOCAL_OVERLAY=""
NETWORK_CONFIG_SCRIPT="" # 网络配置脚本，会注入到init中

SSH_CMD=()
SSH_BASE_OPTS=()
INITIAL_AUTH_OPTS=()
TRAMPOLINE_AUTH_OPTS=()

cleanup() {
  if [ -n "${TEMP_DIR}" ] && [ -d "${TEMP_DIR}" ]; then
    rm -rf "${TEMP_DIR}"
  fi
}

# 通用重试辅助函数
# 用法: retry_with_timeout 30 3 "操作描述" command args...
# 参数: timeout_per_attempt(s) max_attempts description command...
retry_with_timeout() {
  local timeout_sec="$1"
  local max_attempts="$2"
  local description="$3"
  shift 3

  local attempt=1
  local last_exit=0

  while [ $attempt -le "$max_attempts" ]; do
    log "[${description}] 尝试 ${attempt}/${max_attempts}... (timeout: ${timeout_sec}s)"

    last_exit=0
    if timeout "$timeout_sec" "$@" 2>&1; then
      log "[${description}] ✓ 成功"
      return 0
    else
      last_exit=$?

      if [ $last_exit -eq 124 ]; then
        log "[${description}] ✗ 超时（${timeout_sec}s），尝试 ${attempt}/${max_attempts}"
      else
        log "[${description}] ✗ 失败（exit code: $last_exit），尝试 ${attempt}/${max_attempts}"
      fi

      if [ $attempt -lt "$max_attempts" ]; then
        local backoff=$((attempt * 5))
        log "[${description}] 在 ${backoff}s 后重试..."
        sleep "$backoff"
      fi
    fi

    attempt=$((attempt + 1))
  done

  log "[${description}] ✗ 最终失败：已达到最大重试次数（$max_attempts）"
  return 1
}

cleanup_remote() {
  log "Cleaning up stale remote state from previous runs"
  initial_ssh '
    # Kill leftover kexec / dropbear from a previous trampoline attempt.
    # We deliberately do NOT kill sshd (the current session carrier).
    for proc in kexec dropbear; do
      pids=$(pgrep -x "$proc" 2>/dev/null || true)
      [ -n "$pids" ] && kill -9 $pids 2>/dev/null || true
    done
    # Remove stale work directory (under /run so always a plain tmpfs dir).
    rm -rf /run/nixos-kexec
    # Also clean up the old /tmp location in case it is accessible.
    rm -rf /tmp/nixos-kexec 2>/dev/null || true
  ' || log "Warning: remote cleanup encountered errors (continuing)"
}

trap cleanup EXIT

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
    --host | --hostname)
      HOST="$2"
      shift 2
      ;;
    --target-host | --target)
      TARGET_HOST="$2"
      shift 2
      ;;
    --port)
      PORT="$2"
      shift 2
      ;;
    --identity-file)
      IDENTITY_FILE="$2"
      shift 2
      ;;
    --remote-path-prefix)
      REMOTE_PATH_PREFIX="$2"
      shift 2
      ;;
    --device)
      DEVICE="$2"
      shift 2
      ;;
    --alpine-release)
      ALPINE_RELEASE="$2"
      shift 2
      ;;
    --alpine-mirror)
      ALPINE_MIRROR="$2"
      shift 2
      ;;
    --alpine-flavor)
      ALPINE_FLAVOR="$2"
      shift 2
      ;;
    --trampoline-port)
      TRAMPOLINE_PORT="$2"
      shift 2
      ;;
    -h | --help)
      usage
      ;;
    *)
      die "Unknown arg: $1"
      ;;
    esac
  done

  [ -n "$HOST" ] || die "--host is required"
  [ -n "$TARGET_HOST" ] || die "--target-host is required"
  [ -n "$DEVICE" ] || die "--device is required"

  if [ -z "$TRAMPOLINE_PORT" ]; then
    TRAMPOLINE_PORT="$PORT"
  fi
}

prepare_temp_dir() {
  if [ -z "${TEMP_DIR}" ]; then
    TEMP_DIR="$(mktemp -d)"
  fi
}

resolve_identity_file() {
  local candidate

  if [ -n "$IDENTITY_FILE" ]; then
    [ -f "$IDENTITY_FILE" ] || die "Identity file not found: $IDENTITY_FILE"
    return
  fi

  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    if [ -f "$candidate" ]; then
      IDENTITY_FILE="$candidate"
      return
    fi
  done < <(ssh -G -p "$PORT" "$TARGET_HOST" 2>/dev/null | awk '/^identityfile / { print $2 }')

  if [ -f "${HOME}/.ssh/id_ed25519" ]; then
    IDENTITY_FILE="${HOME}/.ssh/id_ed25519"
  fi
}

setup_initial_ssh() {
  SSH_BASE_OPTS=(
    -o StrictHostKeyChecking=accept-new
    -o ServerAliveInterval=15
    -o ServerAliveCountMax=4
    -o ControlMaster=no
    -p "$PORT"
  )

  # Always attempt key auth first.
  INITIAL_AUTH_MODE="key"
  INITIAL_AUTH_OPTS=()
  [ -n "$IDENTITY_FILE" ] && INITIAL_AUTH_OPTS=(-i "$IDENTITY_FILE")
  SSH_CMD=(ssh)
}

install_pubkey_via_password() {
  # Use ssh-copy-id which prompts for password interactively – no sshpass needed.
  local key_opt=()
  [ -n "$IDENTITY_FILE" ] && key_opt=(-i "${IDENTITY_FILE}.pub")

  log "Key auth failed – running ssh-copy-id to install public key (password prompt follows)"
  ssh-copy-id "${SSH_BASE_OPTS[@]}" "${key_opt[@]}" "$TARGET_HOST" ||
    die "ssh-copy-id failed for ${TARGET_HOST}"
  log "Public key installed via ssh-copy-id"
}

initial_ssh() {
  if [ -n "$REMOTE_PATH_PREFIX" ] && [ "$#" -gt 0 ]; then
    local prefix_quoted first_cmd
    prefix_quoted="$(printf '%q' "$REMOTE_PATH_PREFIX")"
    first_cmd="$1"
    shift
    "${SSH_CMD[@]}" "${SSH_BASE_OPTS[@]}" "${INITIAL_AUTH_OPTS[@]}" "$TARGET_HOST" "export PATH=${prefix_quoted}:\$PATH; ${first_cmd}" "$@"
    return
  fi

  "${SSH_CMD[@]}" "${SSH_BASE_OPTS[@]}" "${INITIAL_AUTH_OPTS[@]}" "$TARGET_HOST" "$@"
}

upload_initial_file() {
  local local_path="$1"
  local remote_path="$2"
  local file_size description attempt max_attempts=3 timeout_sec=30
  local remote_dir local_hash

  file_size=$(wc -c <"$local_path" 2>/dev/null || echo "0")
  description="上传 ${local_path##*/}"
  remote_dir=$(dirname "$remote_path")

  # 本地hash校验
  local_hash=$(md5sum <"$local_path" 2>/dev/null | awk '{print $1}')

  log "[${description}] 开始上传 (~$(((file_size + 1048575) / 1048576))MiB, hash: ${local_hash:0:8}...)"

  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    log "[${description}] 尝试 ${attempt}/${max_attempts}... (timeout: ${timeout_sec}s)"

    # 步骤1: 确保远程目录存在
    if ! initial_ssh "mkdir -p $(printf '%q' "$remote_dir") && ls -ld $(printf '%q' "$remote_dir") > /dev/null 2>&1" >/dev/null 2>&1; then
      log "[${description}] ✗ [步骤1/5] 无法创建或访问远程目录: $remote_dir"
      sleep $((attempt * 3))
      continue
    fi

    # 步骤2: 上传文件
    log "[${description}] [步骤2/5] 文件上传中..."
    if ! timeout "$timeout_sec" cat "$local_path" | initial_ssh "cat > $(printf '%q' "$remote_path") && sync" >/dev/null 2>&1; then
      log "[${description}] ✗ [步骤2/5] 上传失败或超时"
      sleep $((attempt * 3))
      continue
    fi

    # 步骤3: 验证文件存在性
    log "[${description}] [步骤3/5] 检查文件是否存在..."
    if ! initial_ssh "test -f $(printf '%q' "$remote_path") && echo EXISTS" 2>/dev/null | grep -q EXISTS; then
      log "[${description}] ✗ [步骤3/5] 文件不存在于目标路径"
      sleep $((attempt * 3))
      continue
    fi

    # 步骤4: 验证文件大小
    log "[${description}] [步骤4/5] 验证文件大小..."
    local remote_size
    remote_size=$(initial_ssh "wc -c < $(printf '%q' "$remote_path")" 2>/dev/null)

    if [ "$remote_size" != "$file_size" ]; then
      log "[${description}] ✗ [步骤4/5] 大小不匹配: 本地=$file_size 远程=$remote_size"
      initial_ssh "rm -f $(printf '%q' "$remote_path")" 2>/dev/null || true
      sleep $((attempt * 3))
      continue
    fi
    log "[${description}] ✓ [步骤4/5] 大小验证通过 ($remote_size 字节)"

    # 步骤5: 验证hash和权限
    log "[${description}] [步骤5/5] 验证hash和设置权限..."
    local remote_hash
    remote_hash=$(initial_ssh "md5sum $(printf '%q' "$remote_path")" 2>/dev/null | awk '{print $1}')

    if [ "$remote_hash" != "$local_hash" ]; then
      log "[${description}] ✗ [步骤5/5] Hash不匹配: 本地=$local_hash 远程=$remote_hash"
      initial_ssh "rm -f $(printf '%q' "$remote_path")" 2>/dev/null || true
      sleep $((attempt * 3))
      continue
    fi
    log "[${description}] ✓ [步骤5/5] Hash验证通过"

    # 设置可执行权限（对于可执行文件）
    if [[ $remote_path == *"kexec" ]] || [[ $remote_path == *"busybox" ]]; then
      initial_ssh "chmod 0755 $(printf '%q' "$remote_path")" 2>/dev/null
      log "[${description}] ✓ 设置执行权限 (755)"
    fi

    # 最后验证权限和可访问性
    local perms
    perms=$(initial_ssh "ls -l $(printf '%q' "$remote_path") | awk '{print \$1}'" 2>/dev/null || true)
    [ -n "$perms" ] || perms="unknown"
    log "[${description}] ✓ 上传完成！(权限: $perms, 大小: $remote_size, hash: ${remote_hash:0:8}...)"

    return 0
  done

  log "[${description}] ✗ 最终失败：已达到最大重试次数($max_attempts)"
  return 1
}

ensure_initial_access() {
  # Fast path: key auth works already (with retry for MaxStartups transients).
  local retries=10 delay=8 i
  local key_ok=no
  for ((i = 1; i <= retries; i++)); do
    if "${SSH_CMD[@]}" "${SSH_BASE_OPTS[@]}" "${INITIAL_AUTH_OPTS[@]}" -o BatchMode=yes "$TARGET_HOST" true >/dev/null 2>&1; then
      key_ok=yes
      break
    fi
    log "SSH attempt ${i}/${retries} to ${TARGET_HOST} failed; retrying in ${delay}s"
    sleep "$delay"
  done

  if [ "$key_ok" = "no" ]; then
    # Key auth failed – install the public key via ssh-copy-id (interactive password).
    install_pubkey_via_password
    # Retry key auth after key installation.
    for ((i = 1; i <= retries; i++)); do
      if "${SSH_CMD[@]}" "${SSH_BASE_OPTS[@]}" "${INITIAL_AUTH_OPTS[@]}" -o BatchMode=yes "$TARGET_HOST" true >/dev/null 2>&1; then
        key_ok=yes
        break
      fi
      log "Post-install SSH attempt ${i}/${retries} failed; retrying in ${delay}s"
      sleep "$delay"
    done
    [ "$key_ok" = "yes" ] ||
      die "SSH key auth still failing after ssh-copy-id for ${TARGET_HOST}"
  fi

  log "Key-based SSH to ${TARGET_HOST} succeeded"

  # Idempotently ensure our pubkey is present (defensive).
  local pub_key=""
  if [ -n "$IDENTITY_FILE" ] && [ -f "${IDENTITY_FILE}.pub" ]; then
    pub_key="$(cat "${IDENTITY_FILE}.pub")"
  elif command -v ssh-add >/dev/null 2>&1; then
    pub_key="$(ssh-add -L 2>/dev/null | head -1 || true)"
  fi
  if [ -n "$pub_key" ]; then
    initial_ssh "
      mkdir -p ~/.ssh && chmod 700 ~/.ssh
      touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
      grep -qxF $(printf '%q' "$pub_key") ~/.ssh/authorized_keys 2>/dev/null \
        || printf '%s\n' $(printf '%q' "$pub_key") >> ~/.ssh/authorized_keys
    " >/dev/null 2>&1 && log "Public key ensured on ${TARGET_HOST}" || true
  fi
}

detect_remote_path_prefix() {
  local detected_prefix

  [ -n "$REMOTE_PATH_PREFIX" ] && return 0

  set +e
  detected_prefix="$(
    "${SSH_CMD[@]}" "${SSH_BASE_OPTS[@]}" "${INITIAL_AUTH_OPTS[@]}" "$TARGET_HOST" '
      set -eu

      add_path() {
        local candidate
        candidate="$1"
        [ -d "$candidate" ] || return 0
        case ":${AUTO_PATH}:" in
          *":${candidate}:"*) ;;
          *) AUTO_PATH="${AUTO_PATH:+${AUTO_PATH}:}${candidate}" ;;
        esac
      }

      AUTO_PATH=""

      for candidate in \
        /run/current-system/sw/bin \
        /run/current-system/sw/sbin \
        /usr/bin /usr/sbin /bin /sbin; do
        add_path "$candidate"
      done

      for candidate in \
        /nix/store/*-coreutils-*/bin \
        /nix/store/*-procps-*/bin \
        /nix/store/*-util-linux-*/bin \
        /nix/store/*-util-linux-*/sbin \
        /nix/store/*-util-linux-minimal-*/bin \
        /nix/store/*-kmod-*/bin \
        /nix/store/*-iproute2-*/bin; do
        add_path "$candidate"
      done

      if [ -n "$AUTO_PATH" ]; then
        PATH="$AUTO_PATH:$PATH"
      fi

      missing=""
      for cmd in rm mkdir cat chmod dd sync sleep pgrep; do
        command -v "$cmd" >/dev/null 2>&1 || missing="${missing} ${cmd}"
      done

      [ -n "$AUTO_PATH" ] && printf "%s\n" "$AUTO_PATH"

      if [ -n "$missing" ]; then
        printf "missing:%s\n" "$missing" >&2
        exit 42
      fi
    '
  )"
  local rc=$?
  set -e

  if [ "$rc" -eq 0 ] && [ -n "$detected_prefix" ]; then
    REMOTE_PATH_PREFIX="$detected_prefix"
    log "Using detected remote PATH prefix: ${REMOTE_PATH_PREFIX}"
    return 0
  fi

  if [ "$rc" -eq 42 ]; then
    die "Remote shell is missing required tools. Pass --remote-path-prefix with usable /nix/store paths, or include core userland in the base image."
  fi

  log "Warning: failed to auto-detect remote PATH prefix (continuing with remote default PATH)"
}

collect_initial_authorized_keys() {
  local auth_keys_file
  local candidate

  prepare_temp_dir
  auth_keys_file="${TEMP_DIR}/initial-authorized_keys"
  : >"$auth_keys_file"

  if [ -n "$IDENTITY_FILE" ] && [ -f "${IDENTITY_FILE}.pub" ]; then
    cat "${IDENTITY_FILE}.pub" >>"$auth_keys_file"
    printf '\n' >>"$auth_keys_file"
  fi

  while IFS= read -r candidate; do
    case "$candidate" in
    "" | none)
      continue
      ;;
    \~/*)
      candidate="${HOME}/${candidate#~/}"
      ;;
    esac

    if [ -f "${candidate}.pub" ]; then
      cat "${candidate}.pub" >>"$auth_keys_file"
      printf '\n' >>"$auth_keys_file"
    fi
  done < <(ssh -G -p "$PORT" "$TARGET_HOST" 2>/dev/null | awk '/^identityfile / { print $2 }')

  while IFS= read -r candidate; do
    [ -f "$candidate" ] || continue
    cat "$candidate" >>"$auth_keys_file"
    printf '\n' >>"$auth_keys_file"
  done < <(find "${HOME}/.ssh" -maxdepth 1 -type f -name '*.pub' 2>/dev/null | LC_ALL=C sort)

  if command -v ssh-add >/dev/null 2>&1; then
    ssh-add -L 2>/dev/null >>"$auth_keys_file" || true
    printf '\n' >>"$auth_keys_file"
  fi

  awk 'NF && !seen[$0]++' "$auth_keys_file" >"${auth_keys_file}.dedup"
  mv "${auth_keys_file}.dedup" "$auth_keys_file"

  [ -s "$auth_keys_file" ] || die "No public keys available to seed ${TARGET_HOST}"
  INITIAL_AUTHORIZED_KEYS_FILE="$auth_keys_file"
}

determine_target_system() {
  TARGET_SYSTEM="$(nix eval --raw --experimental-features 'nix-command flakes' ".#nixosConfigurations.${HOST}.pkgs.stdenv.hostPlatform.system")"
  case "$TARGET_SYSTEM" in
  x86_64-linux)
    ALPINE_ARCH="x86_64"
    ;;
  *)
    die "Unsupported target system for Alpine trampoline: ${TARGET_SYSTEM}"
    ;;
  esac
}

collect_network_configuration() {
  log "采集远程系统的网络配置..."

  prepare_temp_dir
  local net_config_file="${TEMP_DIR}/network-config"
  local net_config_raw="${TEMP_DIR}/network-config.raw"
  : >"$net_config_file"
  : >"$net_config_raw"

  # 从远程系统获取网络信息
  initial_ssh '
    set -eu
    
    # 获取主要网络接口
    PRIMARY_IFACE=$(ip link show | grep -E "^[0-9]+:" | grep -v "lo" | awk -F": " "{print \$2}" | head -1)
    [ -z "$PRIMARY_IFACE" ] && PRIMARY_IFACE="eth0"
    
    echo "PRIMARY_IFACE=\"$PRIMARY_IFACE\""
    
    # 获取IP地址配置（CIDR格式）
    IP_CONFIG=$(ip addr show dev "$PRIMARY_IFACE" 2>/dev/null | grep "inet " | awk "{print \$2}" | head -1 || echo "")
    if [ -n "$IP_CONFIG" ]; then
      echo "STATIC_IP=\"$IP_CONFIG\""
      
      # 获取网关
      GATEWAY=$(ip route show | grep "default via" | awk "{print \$3}" | head -1 || echo "")
      [ -n "$GATEWAY" ] && echo "STATIC_GATEWAY=\"$GATEWAY\""
    fi
    
    # 采集DNS配置（最多采集前两个）
    DNS1=$(grep "nameserver" /etc/resolv.conf 2>/dev/null | awk "{print \$2}" | head -1 || echo "")
    DNS2=$(grep "nameserver" /etc/resolv.conf 2>/dev/null | awk "{print \$2}" | tail -1 || echo "")
    [ -n "$DNS1" ] && echo "DNS1=\"$DNS1\""
    [ -n "$DNS2" ] && [ "$DNS2" != "$DNS1" ] && echo "DNS2=\"$DNS2\""
  ' >"$net_config_raw" 2>/dev/null || log "Warning: 网络配置采集失败，将使用DHCP回退"

  grep -E '^[A-Z_]+="?[^"]*"?$' "$net_config_raw" >"$net_config_file" 2>/dev/null || true

  # 如果采集到配置，显示它
  if [ -s "$net_config_file" ]; then
    log "✓ 成功采集网络配置："
    cat "$net_config_file" | grep -E "^[A-Z_]+=" | sed 's/^/  /'
    NETWORK_CONFIG_SCRIPT="$net_config_file"
  else
    log "⚠ 未能采集到有效的网络配置，将使用DHCP"
    NETWORK_CONFIG_SCRIPT=""
  fi
}

prepare_remote_bootstrap() {
  log "Bootstrapping static tools to target"
  initial_ssh "mkdir -p $(printf '%q' "$REMOTE_ROOT")"
  upload_initial_file "$LOCAL_BUSYBOX" "$REMOTE_BUSYBOX"
  upload_initial_file "$LOCAL_KEXEC" "$REMOTE_KEXEC"
  initial_ssh "chmod 0755 $(printf '%q' "$REMOTE_BUSYBOX") $(printf '%q' "$REMOTE_KEXEC")"
}

prepare_local_artifacts() {
  local kernel_url
  local initramfs_url
  local overlay_root
  local hostkey_file
  local init_script_file
  local udhcpc_script_file
  local alpine_dir
  local alpine_cache_dir
  local cache_kernel
  local cache_initramfs
  local symlink
  local dropbear_prefix

  prepare_temp_dir

  log "Building static trampoline tools"
  LOCAL_BUSYBOX="$(nix build --no-link --print-out-paths --experimental-features 'nix-command flakes' nixpkgs#pkgsStatic.busybox)/bin/busybox"
  dropbear_prefix="$(nix build --no-link --print-out-paths --experimental-features 'nix-command flakes' nixpkgs#pkgsStatic.dropbear)"
  LOCAL_DROPBEAR="${dropbear_prefix}/bin/dropbear"
  LOCAL_DROPBEARKEY="${dropbear_prefix}/bin/dropbearkey"
  LOCAL_KEXEC="$(nix build --no-link --print-out-paths --experimental-features 'nix-command flakes' nixpkgs#pkgsStatic.kexec-tools)/bin/kexec"

  kernel_url="${ALPINE_MIRROR}/${ALPINE_RELEASE}/releases/${ALPINE_ARCH}/netboot/vmlinuz-${ALPINE_FLAVOR}"
  initramfs_url="${ALPINE_MIRROR}/${ALPINE_RELEASE}/releases/${ALPINE_ARCH}/netboot/initramfs-${ALPINE_FLAVOR}"
  alpine_dir="${TEMP_DIR}/alpine"
  alpine_cache_dir="${HOME}/.cache/deploy-live-kexec/${ALPINE_RELEASE}/${ALPINE_ARCH}/${ALPINE_FLAVOR}"
  cache_kernel="${alpine_cache_dir}/vmlinuz"
  cache_initramfs="${alpine_cache_dir}/initramfs"
  mkdir -p "$alpine_dir"
  mkdir -p "$alpine_cache_dir"

  if [ -s "$cache_kernel" ]; then
    log "Using cached Alpine kernel: $cache_kernel"
    cp "$cache_kernel" "${alpine_dir}/vmlinuz"
  else
    log "Downloading Alpine netboot kernel"
    retry_with_timeout 90 4 "下载Alpine kernel" \
      curl --fail --location --silent --show-error \
      --retry 3 --retry-delay 2 --retry-all-errors \
      --output "${alpine_dir}/vmlinuz" "$kernel_url" ||
      die "Failed to download Alpine kernel: $kernel_url"
    cp "${alpine_dir}/vmlinuz" "$cache_kernel"
  fi

  if [ -s "$cache_initramfs" ]; then
    log "Using cached Alpine initramfs: $cache_initramfs"
    cp "$cache_initramfs" "${alpine_dir}/initramfs"
  else
    log "Downloading Alpine netboot initramfs"
    retry_with_timeout 90 4 "下载Alpine initramfs" \
      curl --fail --location --silent --show-error \
      --retry 3 --retry-delay 2 --retry-all-errors \
      --output "${alpine_dir}/initramfs" "$initramfs_url" ||
      die "Failed to download Alpine initramfs: $initramfs_url"
    cp "${alpine_dir}/initramfs" "$cache_initramfs"
  fi

  LOCAL_KERNEL="${TEMP_DIR}/trampoline-kernel"
  LOCAL_INITRAMFS="${TEMP_DIR}/trampoline-initramfs"
  LOCAL_OVERLAY="${TEMP_DIR}/trampoline-overlay.cpio.gz"
  cp "${alpine_dir}/vmlinuz" "$LOCAL_KERNEL"

  TRAMPOLINE_IDENTITY_FILE="${TEMP_DIR}/trampoline_id_ed25519"
  ssh-keygen -q -t ed25519 -N '' -f "$TRAMPOLINE_IDENTITY_FILE" >/dev/null

  overlay_root="${TEMP_DIR}/overlay"
  mkdir -p \
    "${overlay_root}/bin" \
    "${overlay_root}/dev" \
    "${overlay_root}/etc/dropbear" \
    "${overlay_root}/root/.ssh" \
    "${overlay_root}/usr/share/udhcpc"

  cp "$LOCAL_BUSYBOX" "${overlay_root}/bin/busybox"
  cp "$LOCAL_DROPBEAR" "${overlay_root}/bin/dropbear"
  cp "$LOCAL_KEXEC" "${overlay_root}/bin/kexec"

  for symlink in sh mount mkdir mdev modprobe udhcpc ip sleep cat ls dd sync reboot poweroff ps kill setsid wget cp rm mv chmod ln ifconfig route dmesg uname grep awk sed; do
    ln -s busybox "${overlay_root}/bin/${symlink}"
  done

  # Seed authorized_keys with:
  # 1. the ephemeral trampoline key (used by this script to drive the deployment)
  # 2. the operator's own public key (allows reconnect if the script is interrupted)
  {
    cat "${TRAMPOLINE_IDENTITY_FILE}.pub"
    printf '\n'
    if [ -n "$IDENTITY_FILE" ] && [ -f "${IDENTITY_FILE}.pub" ]; then
      cat "${IDENTITY_FILE}.pub"
      printf '\n'
    fi
    # Also pull in any keys from the SSH agent so the operator can reconnect manually.
    ssh-add -L 2>/dev/null || true
  } | awk 'NF && !seen[$0]++' >"${overlay_root}/root/.ssh/authorized_keys"
  chmod 0700 "${overlay_root}/root/.ssh"
  chmod 0600 "${overlay_root}/root/.ssh/authorized_keys"

  hostkey_file="${overlay_root}/etc/dropbear/dropbear_ed25519_host_key"
  "$LOCAL_DROPBEARKEY" -t ed25519 -f "$hostkey_file" >/dev/null 2>&1

  cat >"${overlay_root}/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/sh
EOF
  cat >"${overlay_root}/etc/group" <<'EOF'
root:x:0:
EOF
  cat >"${overlay_root}/etc/resolv.conf" <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

  udhcpc_script_file="${overlay_root}/usr/share/udhcpc/default.script"
  cat >"$udhcpc_script_file" <<'EOF'
#!/bin/sh
set -eu
PATH=/bin:/sbin

cidr_prefix() {
  case "$1" in
    255.255.255.255) echo 32 ;;
    255.255.255.254) echo 31 ;;
    255.255.255.252) echo 30 ;;
    255.255.255.248) echo 29 ;;
    255.255.255.240) echo 28 ;;
    255.255.255.224) echo 27 ;;
    255.255.255.192) echo 26 ;;
    255.255.255.128) echo 25 ;;
    255.255.255.0) echo 24 ;;
    255.255.254.0) echo 23 ;;
    255.255.252.0) echo 22 ;;
    255.255.248.0) echo 21 ;;
    255.255.240.0) echo 20 ;;
    255.255.224.0) echo 19 ;;
    255.255.192.0) echo 18 ;;
    255.255.128.0) echo 17 ;;
    255.255.0.0) echo 16 ;;
    255.254.0.0) echo 15 ;;
    255.252.0.0) echo 14 ;;
    255.248.0.0) echo 13 ;;
    255.240.0.0) echo 12 ;;
    255.224.0.0) echo 11 ;;
    255.192.0.0) echo 10 ;;
    255.128.0.0) echo 9 ;;
    255.0.0.0) echo 8 ;;
    *) echo 24 ;;
  esac
}

case "${1:-}" in
  deconfig)
    ip addr flush dev "$interface" || true
    ;;
  bound|renew)
    ip addr flush dev "$interface" || true
    ip addr add "${ip}/$(cidr_prefix "${subnet:-255.255.255.0}")" dev "$interface"
    if [ -n "${router:-}" ]; then
      ip route replace default via "${router%% *}" dev "$interface"
    fi
    : > /etc/resolv.conf
    for ns in ${dns:-}; do
      printf 'nameserver %s\n' "$ns" >> /etc/resolv.conf
    done
    ;;
esac

exit 0
EOF
  chmod 0755 "$udhcpc_script_file"

  init_script_file="${overlay_root}/init"
  cat >"$init_script_file" <<EOF
#!/bin/busybox sh
# PID 1 – must never exit.  No set -e here: a failed command must not kill init.
PATH=/bin:/sbin
export HOME=/root USER=root LOGNAME=root

# 最早的输出 - 不依赖任何文件系统的东西
/bin/busybox echo "[!!!] init 已启动"

# 早期初始化：创建基本设备节点，用于输出日志
mkdir -p /dev 2>/dev/null
# 创建console和serial port设备节点（硬编码主设备号）
[ -e /dev/console ] || mknod -m 666 /dev/console c 5 1 2>/dev/null || true
[ -e /dev/ttyS0 ]   || mknod -m 666 /dev/ttyS0 c 4 64 2>/dev/null || true
[ -e /dev/tty0 ]    || mknod -m 666 /dev/tty0 c 4 0 2>/dev/null || true
[ -e /dev/tty ]     || mknod -m 666 /dev/tty c 5 0 2>/dev/null || true
[ -e /dev/null ]    || mknod -m 666 /dev/null c 1 3 2>/dev/null || true
[ -e /dev/zero ]    || mknod -m 666 /dev/zero c 1 5 2>/dev/null || true

# 尝试重定向到多个可能的console
exec_log="/dev/null"
for dev in /dev/console /dev/ttyS0 /dev/tty0; do
  if [ -c "\$dev" ] 2>/dev/null; then
    exec_log="\$dev"
    break
  fi
done
exec >\$exec_log 2>&1

say() { 
  /bin/busybox echo "[init] \$*"
}

say "--- 开始初始化 (console: \$exec_log) ---"

say "--- init started ---"

# ── 1. essential mounts ──────────────────────────────────────────────────────
say "mounting devtmpfs"
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true

# 确保console设备存在并尝试reconnect日志
say "setting up console devices"
[ -c /dev/console ] || mknod -m 666 /dev/console c 5 1 2>/dev/null || true
[ -c /dev/ttyS0 ]   || mknod -m 666 /dev/ttyS0 c 4 64 2>/dev/null || true
[ -c /dev/tty0 ]    || mknod -m 666 /dev/tty0 c 4 0 2>/dev/null || true

# Reconnect output to ensure we're using the best available device
if [ -c /dev/console ]; then
  exec >/dev/console 2>&1
elif [ -c /dev/ttyS0 ]; then
  exec >/dev/ttyS0 2>&1
elif [ -c /dev/tty0 ]; then
  exec >/dev/tty0 2>&1
fi

mkdir -p /proc /sys /run /tmp /dev/pts /dev/shm /root

say "mounting proc"
mount -t proc    proc    /proc   2>/dev/null || true
say "mounting sysfs"
mount -t sysfs   sysfs   /sys    2>/dev/null || true
mount -t devpts  devpts  /dev/pts 2>/dev/null || true
mount -t tmpfs -o mode=0755,nosuid,nodev tmpfs /run  2>/dev/null || true
mount -t tmpfs -o mode=1777,nosuid,nodev tmpfs /tmp  2>/dev/null || true

# Static device nodes (fallback if devtmpfs didn't create them)
[ -e /dev/null ]    || mknod -m 666 /dev/null c 1 3 2>/dev/null || true
[ -e /dev/zero ]    || mknod -m 666 /dev/zero c 1 5 2>/dev/null || true
[ -e /dev/full ]    || mknod -m 666 /dev/full c 1 7 2>/dev/null || true
[ -e /dev/random ]  || mknod -m 666 /dev/random c 1 8 2>/dev/null || true
[ -e /dev/urandom ] || mknod -m 666 /dev/urandom c 1 9 2>/dev/null || true
[ -e /dev/tty ]     || mknod -m 666 /dev/tty c 5 0 2>/dev/null || true
[ -e /dev/console ] || mknod -m 666 /dev/console c 5 1 2>/dev/null || true

# ── 2. kernel hotplug / module loading ──────────────────────────────────────
say "setting up mdev"
echo /bin/mdev > /proc/sys/kernel/hotplug 2>/dev/null || true
mdev -s 2>/dev/null || true

# 显示系统信息和硬件设备
say "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
say "📊 系统硬件和设备信息"
say "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
say "🖥️  CPU信息:"
grep -m1 'model name' /proc/cpuinfo 2>/dev/null | /bin/busybox sed 's/.*: /  /' || say "  [unknown]"
say "💾 内存信息:"
/bin/busybox awk '/MemTotal/ {printf "  总内存: %dMB\\n", \$2/1024}; /MemFree/ {printf "  可用: %dMB\\n", \$2/1024}' /proc/meminfo 2>/dev/null || say "  [unknown]"
say "📡 网络设备:"
ls -1 /sys/class/net 2>/dev/null | /bin/busybox sed 's/^/  /' || say "  [无设备检测]"
say "💾 存储设备:"
ls -1d /sys/block/* 2>/dev/null | sed 's|.*/||' | sed 's/^/  /' || say "  [无设备检测]"
say "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
say ""

say "letting kernel auto-detect devices via mdev"
# Alpine内核通常编译了这些驱动，mdev会自动检测
# 注意：busybox modprobe没有modules.dep，所以我们不使用modprobe
# 而是依赖内核编译进的驱动和udev/mdev自动检测
mdev -s 2>/dev/null || true
sleep 1
# 第二次扫描以确保所有设备都被检测到
mdev -s 2>/dev/null || true

# ── 3. networking ─────────────────────────────────────────────────────────
say "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
say "网络配置阶段"
say "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

ip link set lo up 2>/dev/null || say "[WARN] lo interface setup failed"

net_ok=no
# Give udev/mdev a moment to finish renaming interfaces
sleep 1

say "检查网络接口："
if [ -e /sys/class/net ]; then
  iface_count=0
  for devpath in /sys/class/net/*; do
    iface="\${devpath##*/}"
    say "  - \$iface"
    iface_count=\$((iface_count + 1))
  done
  say "总共 \$iface_count 个网络接口"
  if [ \$iface_count -eq 0 ]; then
    say "⚠️  WARNING：没有检测到任何网络接口！"
  fi
else
  say "⚠️  /sys/class/net 不存在！网络配置可能失败"
fi
say ""

# 尝试应用静态IP配置（如果采集到了）
# @STATIC_IP_CONFIG@

# 如果静态IP配置失败或没有配置，回退到DHCP
if [ "\$net_ok" != "yes" ]; then
  say "[dhcp] 尝试DHCP自动配置..."
  for devpath in /sys/class/net/*; do
    [ -e "\$devpath" ] || continue
    iface="\${devpath##*/}"
    [ "\$iface" = lo ] && continue
    say "[dhcp] 在 \$iface 上尝试DHCP..."
    ip link set "\$iface" up 2>/dev/null || true
    # -t attempts, -T timeout per attempt, -A initial hold-off, -n exit on failure
    if udhcpc -n -q -t 15 -T 3 -A 1 -i "\$iface" 2>/dev/null; then
      say "[dhcp] ✓ \$iface DHCP成功"
      net_ok=yes
      break
    fi
    say "[dhcp] ✗ \$iface DHCP失败，尝试下一个接口"
  done
  
  if [ "\$net_ok" = "no" ]; then
    say "⚠ WARNING: DHCP在所有接口上都失败了"
  fi
fi

say ""
say "网络配置完成 - 网络状态:"
say "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ip addr show 2>/dev/null || say "[!] ip addr命令失败"
say ""
say "路由信息:"
ip route show 2>/dev/null || say "[!] ip route命令失败"
say "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
say ""

if [ "\$net_ok" = "no" ]; then
  say "⚠ WARNING: 网络配置未成功，SSH可能无法连接"
fi

# ── 4. dropbear SSH ──────────────────────────────────────────────────────────
say "preparing dropbear SSH service"
mkdir -p /etc/dropbear 2>/dev/null || true

# 生成dropbear主机密钥（如果不存在）
if [ ! -f /etc/dropbear/dropbear_ed25519_host_key ]; then
  say "generating ED25519 host key for dropbear..."
  dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key 2>/dev/null || say "[warn] ED25519 key generation failed, will try RSA"
  if [ ! -f /etc/dropbear/dropbear_ed25519_host_key ]; then
    say "generating RSA host key for dropbear (fallback)..."
    dropbearkey -t rsa -s 2048 -f /etc/dropbear/dropbear_rsa_host_key 2>/dev/null || true
  fi
fi

say "starting dropbear on port ${TRAMPOLINE_PORT}"
while true; do
  # -E log to stderr  -F foreground  -s no-password  -g allow-root-without-key
  if [ -f /etc/dropbear/dropbear_ed25519_host_key ]; then
    dropbear -E -F -s -g -p ${TRAMPOLINE_PORT} \
      -r /etc/dropbear/dropbear_ed25519_host_key 2>&1 || true
  elif [ -f /etc/dropbear/dropbear_rsa_host_key ]; then
    dropbear -E -F -s -g -p ${TRAMPOLINE_PORT} \
      -r /etc/dropbear/dropbear_rsa_host_key 2>&1 || true
  else
    # 最后的手段：让dropbear自动生成密钥
    say "[warn] no pre-generated host keys found, using dropbear defaults"
    dropbear -E -F -s -g -p ${TRAMPOLINE_PORT} 2>&1 || true
  fi
  say "dropbear exited – restarting in 2s"
  sleep 2
done
EOF
  chmod 0755 "$init_script_file"

  # 注入网络配置（如果采集到了）
  if [ -n "$NETWORK_CONFIG_SCRIPT" ] && [ -f "$NETWORK_CONFIG_SCRIPT" ]; then
    log "将网络配置注入到init脚本（硬编码变量值）"
    # 源入网络配置文件获取变量
    source "$NETWORK_CONFIG_SCRIPT" || true

    # 生成静态IP配置脚本片段
    local static_config_file="${TEMP_DIR}/static-net-config.sh"
    : >"$static_config_file"

    if [ -n "${STATIC_IP:-}" ]; then
      # 关键：直接做字符串替换，将变量硬编码进脚本
      # 这样在init脚本中运行时所有值都是字面常量，不需要动态解析
      {
        echo "# ── 静态IP配置（采集自原系统）──"
        echo 'if [ -z "$static_configured" ]; then'
        echo "  iface=\"${PRIMARY_IFACE:-eth0}\""
        echo "  say \"[net-static] 在 \$iface 上配置IP: ${STATIC_IP}\""
        echo '  ip link set "$iface" up 2>/dev/null || true'
        echo "  sleep 1"
        echo "  if ip addr add \"${STATIC_IP}\" dev \"\$iface\" 2>/dev/null; then"
        echo '    say "[net-static] ✓ IP配置成功"'
        echo "    static_configured=yes"
        echo "  else"
        echo '    say "[net-static] ✗ IP配置失败，回退到DHCP"'
        echo "    static_configured=no"
        echo "  fi"

        if [ -n "${STATIC_GATEWAY:-}" ]; then
          echo '  if [ "$static_configured" = "yes" ]; then'
          echo "    say \"[net-static] 配置网关: ${STATIC_GATEWAY}\""
          echo "    ip route add default via \"${STATIC_GATEWAY}\" 2>/dev/null || true"
          echo "  fi"
        fi

        # 配置DNS
        echo "  # 配置DNS服务器"
        echo '  if [ "$static_configured" = "yes" ]; then'
        echo "    {"

        if [ -n "${DNS1:-}" ]; then
          echo "      printf 'nameserver ${DNS1}\\n'"
        fi
        if [ -n "${DNS2:-}" ] && [ "${DNS2}" != "${DNS1}" ]; then
          echo "      printf 'nameserver ${DNS2}\\n'"
        fi

        echo "    } > /etc/resolv.conf 2>/dev/null || true"
        echo "  fi"

        echo "  # 验证网络配置"
        echo '  if [ "$static_configured" = "yes" ] && ip addr show dev "$iface" 2>/dev/null | grep -q "inet "; then'
        echo '    say "[net-static] ✓ 静态网络已就绪"'
        echo "    net_ok=yes"
        echo "  fi"
        echo "fi"
      } >"$static_config_file"
    fi

    # 用sed替换占位符 - 从临时文件读入
    if [ -s "$static_config_file" ]; then
      log "注入网络配置脚本（共$(wc -l <"$static_config_file")行）"
      sed -i "/@STATIC_IP_CONFIG@/r $static_config_file" "$init_script_file" || log "Warning: sed注入网络配置失败"
      sed -i '/@STATIC_IP_CONFIG@/d' "$init_script_file" # 删除占位符本身
    else
      # 如果没有静态配置，只移除占位符
      sed -i '/@STATIC_IP_CONFIG@/d' "$init_script_file"
    fi

    rm -f "$static_config_file"
  else
    # 没有网络配置，移除占位符
    sed -i '/@STATIC_IP_CONFIG@/d' "$init_script_file"
  fi

  (
    cd "$overlay_root"
    find . -print0 | LC_ALL=C sort -z | cpio --null -o -H newc | gzip -1 >"$LOCAL_OVERLAY"
  ) >/dev/null 2>&1

  cat "${alpine_dir}/initramfs" "$LOCAL_OVERLAY" >"$LOCAL_INITRAMFS"
}

seed_remote_authorized_keys() {
  local remote_key_seed

  [ "$INITIAL_AUTH_MODE" = "password" ] || return 0

  collect_initial_authorized_keys
  remote_key_seed="${REMOTE_ROOT}/authorized_keys.seed"

  log "Seeding remote authorized_keys so the rest of the deployment stays passwordless"
  upload_initial_file "$INITIAL_AUTHORIZED_KEYS_FILE" "$remote_key_seed"
  initial_ssh "
    set -eu
    BUSYBOX=$(printf '%q' "$REMOTE_BUSYBOX")
    AUTH_DIR=\$HOME/.ssh
    AUTH_FILE=\$AUTH_DIR/authorized_keys
    TMP_FILE=\$AUTH_FILE.tmp
    \$BUSYBOX mkdir -p \"\$AUTH_DIR\"
    \$BUSYBOX chmod 0700 \"\$AUTH_DIR\"
    if [ -f \"\$AUTH_FILE\" ]; then
      \$BUSYBOX cat \"\$AUTH_FILE\" $(printf '%q' "$remote_key_seed") > \"\$TMP_FILE\"
    else
      \$BUSYBOX cat $(printf '%q' "$remote_key_seed") > \"\$TMP_FILE\"
    fi
    \$BUSYBOX awk 'NF && !seen[\$0]++' \"\$TMP_FILE\" > \"\$AUTH_FILE\"
    \$BUSYBOX chmod 0600 \"\$AUTH_FILE\"
    \$BUSYBOX rm -f \"\$TMP_FILE\" $(printf '%q' "$remote_key_seed")
  "

  SSH_CMD=(ssh)
  if [ -n "$IDENTITY_FILE" ]; then
    INITIAL_AUTH_OPTS=(-i "$IDENTITY_FILE")
  else
    INITIAL_AUTH_OPTS=()
  fi
  INITIAL_AUTH_MODE="key"
  unset SSH_PASSWORD SSHPASS || true
  ensure_initial_access
}

upload_kexec_payload() {
  log "Uploading Alpine trampoline kernel and initramfs"
  upload_initial_file "$LOCAL_KERNEL" "$REMOTE_KERNEL"
  upload_initial_file "$LOCAL_INITRAMFS" "$REMOTE_INITRAMFS"
  initial_ssh "chmod 0644 $(printf '%q' "$REMOTE_KERNEL") $(printf '%q' "$REMOTE_INITRAMFS")"
}

enter_trampoline() {
  local cmdline

  # nomodeset: avoids VGA mode-switch hang on some hypervisors (Alibaba Cloud KVM)
  # ip=dhcp removed: our custom /init handles DHCP; having both causes races/hangs
  # console参数：多个console设备可以同时使用，最后那个成为交互式console
  # earlycon用于尽早输出内核引导消息，printk日志级别设为在屏幕上显示
  cmdline="earlycon=ttyS0 console=ttyS0 console=tty0 console=tty1 nomodeset panic=30 init=/init"

  log "════════════════════════════════════════════════════════════"
  log "开始KEXEC系统切换（critical stage）"
  log "════════════════════════════════════════════════════════════"

  log "Pre-flight检查：验证kexec工具和镜像文件"
  initial_ssh "
    set -eu
    KEXEC=$(printf '%q' "$REMOTE_KEXEC")
    KERNEL=$(printf '%q' "$REMOTE_KERNEL")
    INITRD=$(printf '%q' "$REMOTE_INITRAMFS")
    BUSYBOX=$(printf '%q' "$REMOTE_BUSYBOX")
    
    echo '[preflight] 关键文件检查:'
    [ -x \"\$KEXEC\" ] && echo '  ✓ kexec可执行' || { echo '  ✗ kexec不可用'; exit 1; }
    [ -f \"\$KERNEL\" ] && echo \"  ✓ kernel存在 (\$(\$BUSYBOX stat -c%s \$KERNEL | /bin/sh -c 'read x; echo \$((x/1024/1024))MB')\" || { echo '  ✗ kernel不存在'; exit 1; }
    [ -f \"\$INITRD\" ] && echo \"  ✓ initramfs存在 (\$(\$BUSYBOX stat -c%s \$INITRD | /bin/sh -c 'read x; echo \$((x/1024/1024))MB')\" || { echo '  ✗ initramfs不存在'; exit 1; }
    
    echo '[preflight] 系统内存状态:'
    \$BUSYBOX grep MemTotal /proc/meminfo | \$BUSYBOX awk '{print \"  总内存: \" \$2/1024 \"MB\"}'
    \$BUSYBOX grep MemFree /proc/meminfo | \$BUSYBOX awk '{print \"  可用: \" \$2/1024 \"MB\"}'
  " || log "WARNING: pre-flight检查失败，但继续执行"

  log "Loading Alpine trampoline with kexec"
  initial_ssh "
    set -eu
    KEXEC=$(printf '%q' "$REMOTE_KEXEC")
    KERNEL=$(printf '%q' "$REMOTE_KERNEL")
    INITRD=$(printf '%q' "$REMOTE_INITRAMFS")
    BUSYBOX=$(printf '%q' "$REMOTE_BUSYBOX")
    
    echo '[kexec] ━━━━━━━━━━━━━━━━━━━ 开始kexec序列 ━━━━━━━━━━━━━━━━━━'
    echo '[kexec] [1/3] kexec -l 加载新kernel和initramfs...'
    \$KEXEC -l \"\$KERNEL\" --initrd=\"\$INITRD\" --command-line=$(printf '%q' "$cmdline") && echo '[kexec] [✓] 内核加载成功'
    
    echo '[kexec] [2/3] 执行sync确保数据写入...'
    \$BUSYBOX sync && echo '[kexec] [✓] sync完成'
    
    echo '[kexec] [3/3] 即将在5秒后执行kexec -e进行系统切换...'
    \$BUSYBOX setsid \$BUSYBOX sh -c $(printf '%q' "sleep 5; echo '[kexec] [EXEC] 执行 kexec -e'; exec ${REMOTE_KEXEC} -e") >/dev/null 2>&1 &
    echo '[kexec] [✓] kexec -e后台进程已启动，SSH即将断开'
  "

  log "等待当前系统关闭... (预期8-15秒)"
  log "  * 新系统将在内存中启动"
  log "  * dropbear SSH服务器将启动"
  log "  * 网络配置将自动进行(DHCP)"
  sleep 8
}

wait_for_trampoline() {
  local i attempt max_attempts=3
  local telnet_ok=no
  local ssh_output_file="${TEMP_DIR}/ssh-test-output.log"

  # Auth options for trampoline: try ephemeral key first, fall back to user identity
  TRAMPOLINE_AUTH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o GlobalKnownHostsFile=/dev/null)
  # Build list of identity files to try: ephemeral key + user's own key
  local trampoline_id_files=()
  [ -f "$TRAMPOLINE_IDENTITY_FILE" ] && trampoline_id_files+=("$TRAMPOLINE_IDENTITY_FILE")
  [ -n "$IDENTITY_FILE" ] && [ -f "$IDENTITY_FILE" ] && trampoline_id_files+=("$IDENTITY_FILE")

  log "════════════════════════════════════════════════════════════"
  log "等待Alpine内存系统SSH启动 (最多${max_attempts}次尝试)"
  log "════════════════════════════════════════════════════════════"
  log "目标: ${TARGET_HOST}:${TRAMPOLINE_PORT}"
  log "每次尝试超时: 240秒（4分钟）"
  log "系统启动预期时间: 30-60秒内SSH可用"
  log ""

  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    log "【尝试 ${attempt}/${max_attempts}】等待Alpine Trampoline..."
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # 尝试这一轮（240秒）
    for ((i = 1; i <= 240; i++)); do
      local ok=no

      # 每20秒打印一条进度信息
      if [ $((i % 20)) -eq 0 ] || [ $i -eq 1 ]; then
        log "[${attempt}/${max_attempts}] 已尝试 $i/240 秒..."
      fi

      if [ ${#trampoline_id_files[@]} -gt 0 ]; then
        # Try each available identity file
        local id_file
        for id_file in "${trampoline_id_files[@]}"; do
          if timeout 6 ssh \
            -T \
            -o ConnectTimeout=3 \
            -o ConnectionAttempts=1 \
            -o ControlMaster=no \
            -o RequestTTY=no \
            "${TRAMPOLINE_AUTH_OPTS[@]}" \
            -i "$id_file" \
            -p "$TRAMPOLINE_PORT" \
            "$TARGET_HOST" \
            'echo trampoline-ok' >"$ssh_output_file" 2>&1; then
            log ""
            log "✓ 系统成功启动！Alpine trampoline SSH已准备就绪"
            log "  尝试次数: ${attempt}/${max_attempts}"
            log "  使用密钥: ${id_file##*/}"
            log "  连接: root@${TARGET_HOST}:${TRAMPOLINE_PORT}"
            TRAMPOLINE_IDENTITY_FILE="$id_file"
            ok=yes
            telnet_ok=yes
            break
          fi
        done
      else
        # Rely on ssh-agent when no explicit identity files available
        if timeout 6 ssh \
          -T \
          -o ConnectTimeout=3 \
          -o ConnectionAttempts=1 \
          -o ControlMaster=no \
          -o RequestTTY=no \
          "${TRAMPOLINE_AUTH_OPTS[@]}" \
          -p "$TRAMPOLINE_PORT" \
          "$TARGET_HOST" \
          'echo trampoline-ok' >"$ssh_output_file" 2>&1; then
          log ""
          log "✓ 系统成功启动！Alpine trampoline SSH已准备就绪"
          log "  尝试次数: ${attempt}/${max_attempts}"
          log "  使用ssh-agent的密钥"
          log "  连接: root@${TARGET_HOST}:${TRAMPOLINE_PORT}"
          ok=yes
          telnet_ok=yes
        fi
      fi
      [ "$ok" = yes ] && return 0
      sleep 1
    done

    # 本轮超时（240秒）
    log "⚠ 尝试 ${attempt}/${max_attempts} 在240秒后超时（无SSH连接）"

    if [ $attempt -lt "$max_attempts" ]; then
      local backoff=$((attempt * 60))
      log ""
      log "诊断: 尝试失败，可能的原因："
      log "  1. init脚本未启动或崩溃"
      log "  2. 网络配置失败"
      log "  3. Dropbear SSH启动失败"
      log ""
      log "在 ${backoff}s 后进行第$((attempt + 1))次尝试..."
      sleep "$backoff"
    fi
  done

  # 所有重试都失败了
  log ""
  log "✗ 最终失败！已达到最大尝试次数 (${max_attempts})"
  log ""
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "诊断信息："
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log ""
  log "1. SSH连接失败的可能原因："
  log "   - Alpine init脚本未启动或多次崩溃"
  log "   - 网络配置失败（IP未被正确分配或配置）"
  log "   - Dropbear SSH服务启动失败"
  log "   - 网络驱动未加载（无网络接口）"
  log "   - kexec内核切换本身失败"
  log ""
  log "2. 建议排查步骤："
  log "   - 检查VNC/console输出，看init脚本的最后一行是什么"
  log "   - 确认网络接口被正确检测到"
  log "   - 确认静态IP配置或DHCP成功"
  log "   - 如果多次失败，检查目标系统状态和网络连接"
  log ""
  log "3. 最后SSH诊断输出:"
  if [ -f "$ssh_output_file" ]; then
    tail -10 "$ssh_output_file" | sed 's/^/    /'
  else
    log "    (无法获得SSH输出)"
  fi
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log ""
  log "部署在 ${TARGET_HOST} 上失败。请检查上述诊断信息。"

  die "Alpine ssh连接失败（已重试${max_attempts}次）"
}

stream_image_from_trampoline() {
  log "════════════════════════════════════════════════════════════"
  log "开始从Alpine trampoline流式传输NixOS镜像"
  log "════════════════════════════════════════════════════════════"
  log "这一步会将已编译的NixOS镜像写入目标磁盘"
  log "可能需要5-30分钟，取决于镜像大小和网络速度"
  log ""

  local id_file_arg=()
  [ -n "$TRAMPOLINE_IDENTITY_FILE" ] && [ -f "$TRAMPOLINE_IDENTITY_FILE" ] && id_file_arg=(--identity-file "$TRAMPOLINE_IDENTITY_FILE")

  # 检查deploy-raw-image.sh是否存在
  if [ ! -f "./scripts/deploy-raw-image.sh" ]; then
    die "Error: deploy-raw-image.sh not found at ./scripts/deploy-raw-image.sh"
  fi

  local attempt max_attempts=3 timeout_sec=1800 # 30分钟超时

  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    log "【尝试 ${attempt}/${max_attempts}】调用deploy-raw-image.sh"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "  Host: ${HOST}"
    log "  Target: ${TARGET_HOST}:${TRAMPOLINE_PORT}"
    log "  Device: ${DEVICE}"
    log "  Timeout: ${timeout_sec}s (30分钟)"
    log ""

    if timeout "$timeout_sec" ./scripts/deploy-raw-image.sh \
      --target ".#nixosConfigurations.${HOST}.config.system.build.diskoImages" \
      --target-host "$TARGET_HOST" \
      --port "$TRAMPOLINE_PORT" \
      "${id_file_arg[@]+${id_file_arg[@]}}" \
      --device "$DEVICE" \
      --only-stream; then
      log ""
      log "✓ 镜像流式传输成功"
      return 0
    else
      local exit_code=$?
      log ""

      if [ $exit_code -eq 124 ]; then
        log "✗ 镜像流式传输超时（${timeout_sec}s），尝试 ${attempt}/${max_attempts}"
      else
        log "✗ 镜像流式传输失败（退出码: $exit_code），尝试 ${attempt}/${max_attempts}"
      fi

      if [ $attempt -lt "$max_attempts" ]; then
        local backoff=$((attempt * 120))
        log ""
        log "可能的原因："
        log "  1. Alpine系统中的dd或网络工具临时失败"
        log "  2. 磁盘写入权限问题（临时）"
        log "  3. 网络中断或超时（临时）"
        log "  4. SSH连接不稳定"
        log ""
        log "在 ${backoff}s 后进行第$((attempt + 1))次尝试..."
        sleep "$backoff"
      fi
    fi
  done

  # 所有重试都失败了
  log ""
  log "✗ 镜像流式传输最终失败！已达到最大尝试次数 (${max_attempts})"
  log ""
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "可能的原因："
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "1. Alpine系统中的dd或网络工具失败（多次）"
  log "2. 磁盘写入权限问题或磁盘故障"
  log "3. 网络中断或严重的连接问题"
  log "4. 目标磁盘无效或不可用"
  log "5. SSH连接在流式传输过程中断开"
  log ""
  log "建议排查步骤："
  log "  1. 检查Alpine trampoline是否仍响应: ssh root@${TARGET_HOST} -p ${TRAMPOLINE_PORT} 'df'"
  log "  2. 检查目标磁盘是否可访问: ssh root@${TARGET_HOST} -p ${TRAMPOLINE_PORT} 'lsblk'"
  log "  3. 检查网络连接稳定性"
  log "  4. 联系系统管理员检查网络和磁盘"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log ""

  die "Image streaming failed (已重试${max_attempts}次)"
}

reboot_final_system() {
  log "Rebooting the trampoline after disk sync"
  local id_opts=()
  [ -n "$TRAMPOLINE_IDENTITY_FILE" ] && [ -f "$TRAMPOLINE_IDENTITY_FILE" ] && id_opts=(-i "$TRAMPOLINE_IDENTITY_FILE")
  ssh \
    -T \
    -o CanonicalizeHostname=no \
    -o ControlMaster=no \
    "${TRAMPOLINE_AUTH_OPTS[@]}" \
    "${id_opts[@]+${id_opts[@]}}" \
    -p "$TRAMPOLINE_PORT" \
    "$TARGET_HOST" \
    '/bin/busybox sh -c "/bin/busybox sync; /bin/busybox sleep 15; exec /bin/busybox reboot -f"' || true
}

report_memory_footprint() {
  local kernel_bytes
  local initramfs_bytes
  local overlay_bytes
  local initramfs_unpacked_bytes

  kernel_bytes="$(wc -c <"$LOCAL_KERNEL")"
  initramfs_bytes="$(wc -c <"$LOCAL_INITRAMFS")"
  overlay_bytes="$(wc -c <"$LOCAL_OVERLAY")"
  initramfs_unpacked_bytes="$(gzip -l "$LOCAL_INITRAMFS" | awk 'NR==2 { print $2 }')"

  log "Trampoline artifact sizes: kernel=$((kernel_bytes / 1024 / 1024))MiB initramfs-compressed=$((initramfs_bytes / 1024 / 1024))MiB overlay=$((overlay_bytes / 1024 / 1024))MiB initramfs-unpacked~= $((initramfs_unpacked_bytes / 1024 / 1024))MiB"
}

preflight_checks() {
  log "════════════════════════════════════════════════════════════"
  log "部署前检查 - 验证关键条件"
  log "════════════════════════════════════════════════════════════"

  local check_ok=yes

  # 1. 检查必要参数
  log ""
  log "验证参数..."
  if [ -z "$HOST" ]; then
    log "  ✗ --host 未指定"
    check_ok=no
  else
    log "  ✓ Host: $HOST"
  fi

  if [ -z "$TARGET_HOST" ]; then
    log "  ✗ --target-host 未指定"
    check_ok=no
  else
    log "  ✓ Target host: $TARGET_HOST"
  fi

  if [ -z "$DEVICE" ]; then
    log "  ✗ --device 未指定"
    check_ok=no
  else
    log "  ✓ Target device: $DEVICE"
  fi

  if [ "$check_ok" = "no" ]; then
    die "缺少必要的命令行参数"
  fi

  # 2. 检查所需的可执行文件
  log ""
  log "验证必要工具..."
  local required_tools=(ssh nix curl setsid ssh-keygen awk sed grep find cpio gzip)
  for tool in "${required_tools[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
      log "  ✓ $tool"
    else
      log "  ✗ $tool (未找到)"
      check_ok=no
    fi
  done

  if [ "$check_ok" = "no" ]; then
    die "缺少必要的工具，请先安装"
  fi

  # 3. 检查deploy-raw-image.sh存在
  log ""
  log "验证部署脚本..."
  if [ -f "./scripts/deploy-raw-image.sh" ]; then
    log "  ✓ deploy-raw-image.sh found"
  else
    log "  ✗ deploy-raw-image.sh 未找到"
    die "$(pwd)/scripts/deploy-raw-image.sh 缺失"
  fi

  # 4. 检查SSH密钥
  log ""
  log "验证SSH身份认证..."
  if [ -n "$IDENTITY_FILE" ]; then
    if [ -f "$IDENTITY_FILE" ]; then
      log "  ✓ Identity file: $IDENTITY_FILE"
    else
      log "  ✗ Identity file 不存在: $IDENTITY_FILE"
      check_ok=no
    fi
  else
    log "  ⓘ No explicit identity file (will attempt default locations)"
  fi

  # 尝试SSH连接测试（快速连接测试，10秒超时）
  log "  测试SSH连接到 $TARGET_HOST..."
  if timeout 10 ssh \
    -T \
    -o ConnectTimeout=5 \
    -o StrictHostKeyChecking=accept-new \
    -o ServerAliveInterval=15 \
    -o ServerAliveCountMax=4 \
    -o ControlMaster=no \
    -o ControlPath=none \
    -p "$PORT" \
    ${IDENTITY_FILE:+-i "$IDENTITY_FILE"} \
    "$TARGET_HOST" "true" >/dev/null 2>&1; then
    log "    ✓ SSH连接成功"
  else
    log "    ✗ SSH连接失败（将在later步骤重试）"
    # 不立即失败，因为在later步骤会有重试逻辑
  fi

  # 5. 验证nix flake配置
  log ""
  log "验证Nix配置..."
  if nix eval --raw --experimental-features 'nix-command flakes' ".#nixosConfigurations.${HOST}.pkgs.stdenv.hostPlatform.system" >/dev/null 2>&1; then
    log "  ✓ NixOS配置存在: $HOST"
  else
    log "  ✗ NixOS配置不存在或无效: $HOST"
    log "  可用的配置："
    nix eval --experimental-features 'nix-command flakes' '.#nixosConfigurations' 2>/dev/null | grep -o '"[^"]*"' | head -5 | sed 's/^/    /' || log "    (无法列出配置)"
    check_ok=no
  fi

  if [ "$check_ok" = "no" ]; then
    die "某些preflight检查失败"
  fi

  # 6. 验证磁盘设备路径语法
  log ""
  log "验证目标设备..."
  case "$DEVICE" in
  /dev/*)
    log "  ✓ Device path looks valid: $DEVICE"
    ;;
  *)
    log "  ✗ Device path不以/dev/开头: $DEVICE"
    die "无效的设备路径"
    ;;
  esac

  # 7. 最终确认
  log ""
  log "════════════════════════════════════════════════════════════"
  log "所有preflight检查已通过！"
  log "准备开始部署流程..."
  log "════════════════════════════════════════════════════════════"
  log ""
}

main() {
  # 显示帮助信息若无参数
  if [ "$#" -eq 0 ]; then
    usage
  fi

  parse_args "$@"
  preflight_checks
  resolve_identity_file
  setup_initial_ssh
  ensure_initial_access
  detect_remote_path_prefix
  cleanup_remote
  determine_target_system
  collect_network_configuration
  prepare_local_artifacts
  report_memory_footprint
  prepare_remote_bootstrap
  seed_remote_authorized_keys
  upload_kexec_payload
  enter_trampoline
  wait_for_trampoline
  stream_image_from_trampoline
  reboot_final_system
  log "Deployment finished. The target should reboot into the new system after flushing writes."
}

main "$@"
