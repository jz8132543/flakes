#!/usr/bin/env bash
set -euo pipefail

HOST=""
USER_NAME="root"
PORT="22"
IDENTITY_FILE="${HOME}/.ssh/id_ed25519"
OUTPUT_FILE="/tmp/hardware-configuration.nix"
INSTALL_NIX="1"
CONTROL_PERSIST="20m"

usage() {
  cat <<'EOF'
Usage:
  remote-nixos-hardware-config.sh --host HOST [options]

Options:
  --host HOST           Remote host or IP (required)
  --user USER           SSH user (default: root)
  --port PORT           SSH port (default: 22)
  --identity FILE       SSH private key path (default: ~/.ssh/id_ed25519)
  --output FILE         Local output path (default: /tmp/hardware-configuration.nix)
  --no-install-nix      Do not install Nix when remote host does not have it
  --persist DURATION    SSH ControlPersist duration (default: 20m)
  -h, --help            Show this help

Examples:
  ./scripts/remote-nixos-hardware-config.sh --host 203.0.113.10
  ./scripts/remote-nixos-hardware-config.sh --host 203.0.113.10 --user ubuntu --output ./nixos/hardware-configuration.nix
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --host)
    HOST="${2:-}"
    shift 2
    ;;
  --user)
    USER_NAME="${2:-}"
    shift 2
    ;;
  --port)
    PORT="${2:-}"
    shift 2
    ;;
  --identity)
    IDENTITY_FILE="${2:-}"
    shift 2
    ;;
  --output)
    OUTPUT_FILE="${2:-}"
    shift 2
    ;;
  --no-install-nix)
    INSTALL_NIX="0"
    shift
    ;;
  --persist)
    CONTROL_PERSIST="${2:-}"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown arg: $1" >&2
    usage
    exit 1
    ;;
  esac
done

if [[ -z $HOST ]]; then
  echo "Missing required --host" >&2
  usage
  exit 1
fi

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing command: $1" >&2
    exit 1
  }
}

need_cmd ssh
need_cmd scp
need_cmd curl
need_cmd tar
need_cmd mktemp
need_cmd dirname

SSH_TARGET="${USER_NAME}@${HOST}"
CONTROL_PATH="$(mktemp -u "/tmp/remote-hwcfg-ssh.${USER}.XXXXXX")"

SSH_OPTS=(
  -o StrictHostKeyChecking=accept-new
  -o ServerAliveInterval=15
  -o ServerAliveCountMax=6
  -o ControlMaster=auto
  -o ControlPersist="${CONTROL_PERSIST}"
  -o ControlPath="${CONTROL_PATH}"
  -p "${PORT}"
)

if [[ -n $IDENTITY_FILE ]]; then
  if [[ -f $IDENTITY_FILE ]]; then
    SSH_OPTS+=(-i "${IDENTITY_FILE}")
  else
    echo "Identity file not found, fallback to default SSH auth: ${IDENTITY_FILE}" >&2
    IDENTITY_FILE=""
  fi
fi

SCP_OPTS=(
  -o StrictHostKeyChecking=accept-new
  -o ServerAliveInterval=15
  -o ServerAliveCountMax=6
  -o ControlMaster=auto
  -o ControlPersist="${CONTROL_PERSIST}"
  -o ControlPath="${CONTROL_PATH}"
  -P "${PORT}"
)
if [[ -n $IDENTITY_FILE ]]; then
  SCP_OPTS+=(-i "${IDENTITY_FILE}")
fi

cleanup() {
  ssh "${SSH_OPTS[@]}" -O exit "${SSH_TARGET}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

run_ssh() {
  # shellcheck disable=SC2029
  ssh "${SSH_OPTS[@]}" "${SSH_TARGET}" "$@"
}

run_scp() {
  scp "${SCP_OPTS[@]}" "$@"
}

echo "Opening persistent SSH connection (password prompt appears once if needed)..." >&2
ssh "${SSH_OPTS[@]}" -o ControlMaster=yes -Nf "${SSH_TARGET}"

ensure_remote_pubkey() {
  if [[ -z $IDENTITY_FILE ]]; then
    return
  fi
  local pub_file="${IDENTITY_FILE}.pub"
  if [[ ! -f $pub_file ]]; then
    echo "Skip public key upload: ${pub_file} not found." >&2
    return
  fi

  echo "Uploading ${pub_file} to remote authorized_keys (idempotent)..." >&2
  run_scp "$pub_file" "${SSH_TARGET}:~/.codex_upload_id.pub"
  run_ssh 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && pub=$(cat ~/.codex_upload_id.pub) && (grep -qxF "$pub" ~/.ssh/authorized_keys || echo "$pub" >> ~/.ssh/authorized_keys); rm -f ~/.codex_upload_id.pub'
}

remote_system_from_uname() {
  local arch
  arch="$(run_ssh "uname -m")"
  case "$arch" in
  x86_64 | amd64) echo "x86_64-linux" ;;
  aarch64 | arm64) echo "aarch64-linux" ;;
  *)
    echo "Unsupported remote architecture: $arch" >&2
    exit 1
    ;;
  esac
}

remote_has_nix() {
  run_ssh 'command -v nix >/dev/null 2>&1 || [ -x /nix/var/nix/profiles/default/bin/nix ] || [ -x "$HOME/.nix-profile/bin/nix" ]'
}

install_nix_remote_offline() {
  local remote_system="$1"
  local nix_version
  local tar_name
  local tarball
  local url

  need_cmd nix

  nix_version="$(nix --version | awk '{print $3}')"
  if [[ -z $nix_version ]]; then
    echo "Failed to detect local nix version." >&2
    exit 1
  fi

  tar_name="nix-${nix_version}-${remote_system}.tar.xz"
  tarball="/tmp/${tar_name}"
  url="https://releases.nixos.org/nix/nix-${nix_version}/${tar_name}"

  if [[ ! -f $tarball ]]; then
    echo "Downloading ${tar_name} on local machine..." >&2
    curl -fL "$url" -o "$tarball"
  fi

  echo "Copying Nix installer to remote host..." >&2
  run_scp "$tarball" "${SSH_TARGET}:~/${tar_name}"
  run_scp "scripts/remote-install.sh" "${SSH_TARGET}:~/remote-install.sh"

  echo "Installing Nix on remote host (offline)..." >&2
  run_ssh "bash ~/remote-install.sh '${tar_name}' '${nix_version}' '${remote_system}' && rm -f ~/remote-install.sh"
}

require_local_nix() {
  command -v nix >/dev/null 2>&1 || {
    echo "Local nix is required for offline transfer of nixos-install-tools." >&2
    exit 1
  }
}

copy_install_tools_to_remote() {
  local tool_path
  require_local_nix

  echo "Building nixos-install-tools locally..." >&2
  tool_path="$(nix build --no-link --print-out-paths nixpkgs#nixos-install-tools)"
  if [[ -z $tool_path ]]; then
    echo "Failed to build nixos-install-tools locally." >&2
    exit 1
  fi

  echo "Copying nixos-install-tools closure to remote (no remote internet required)..." >&2
  NIX_SSHOPTS="-p ${PORT} -o StrictHostKeyChecking=accept-new -o ControlMaster=auto -o ControlPersist=${CONTROL_PERSIST} -o ControlPath=${CONTROL_PATH}${IDENTITY_FILE:+ -i ${IDENTITY_FILE}}" \
    nix copy --to "ssh://${SSH_TARGET}" "$tool_path"

  echo "$tool_path"
}

OUT_DIR="$(dirname "$OUTPUT_FILE")"
mkdir -p "$OUT_DIR"
TMP_OUT="$(mktemp "${OUTPUT_FILE}.tmp.XXXXXX")"
trap 'rm -f "$TMP_OUT"; cleanup' EXIT

echo "Collecting NixOS hardware config from ${SSH_TARGET}:${PORT} ..." >&2
ensure_remote_pubkey

if ! remote_has_nix; then
  if [[ $INSTALL_NIX != "1" ]]; then
    echo "Remote nix is missing and --no-install-nix was set." >&2
    exit 1
  fi
  remote_system="$(remote_system_from_uname)"
  install_nix_remote_offline "$remote_system"
fi

TOOL_PATH="$(copy_install_tools_to_remote)"

run_ssh "TOOL_PATH='${TOOL_PATH}' bash -s" <<'REMOTE_SCRIPT' >"$TMP_OUT"
#!/usr/bin/env bash
set -euo pipefail

run_as_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
    return
  fi

  if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    sudo -n "$@"
    return
  fi

  echo "Need root or passwordless sudo on remote host." >&2
  exit 1
}

if [[ ! -x "${TOOL_PATH}/bin/nixos-generate-config" ]]; then
  echo "nixos-generate-config not found at ${TOOL_PATH}/bin/nixos-generate-config" >&2
  exit 1
fi

run_as_root "${TOOL_PATH}/bin/nixos-generate-config" --show-hardware-config
REMOTE_SCRIPT

if [[ ! -s $TMP_OUT ]]; then
  echo "Failed to generate hardware config (empty output)." >&2
  exit 1
fi

mv "$TMP_OUT" "$OUTPUT_FILE"
echo "Saved: $OUTPUT_FILE" >&2
