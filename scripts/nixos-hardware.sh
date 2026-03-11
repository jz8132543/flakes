#!/usr/bin/env bash

set -e

echo "=== 开始获取官方 NixOS 硬件配置 (按需拉取/用完即清理版) ==="

# 1. 自动适配并安装轻量级系统依赖
MISSING_CMDS=""
for cmd in curl xz tar sudo; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    MISSING_CMDS="$MISSING_CMDS $cmd"
  fi
done

if [ -n "$MISSING_CMDS" ]; then
  echo "正在静默安装基础依赖: $MISSING_CMDS"
  SUDO_CMD=$([ "$EUID" -eq 0 ] && echo "" || echo "sudo")

  if command -v apt-get >/dev/null 2>&1; then
    # shellcheck disable=SC2001
    PKGS=$(echo "$MISSING_CMDS" | sed 's/\bxz\b/xz-utils/g')
    $SUDO_CMD apt-get update -qq && $SUDO_CMD apt-get install -y -qq "$PKGS"
  elif command -v dnf >/dev/null 2>&1; then
    $SUDO_CMD dnf install -y -q "$MISSING_CMDS"
  elif command -v yum >/dev/null 2>&1; then
    $SUDO_CMD yum install -y -q "$MISSING_CMDS"
  elif command -v pacman >/dev/null 2>&1; then
    $SUDO_CMD pacman -Sy --noconfirm -q "$MISSING_CMDS"
  elif command -v zypper >/dev/null 2>&1; then
    $SUDO_CMD zypper install -y -q "$MISSING_CMDS"
  fi
fi

# 2. 安装官方 Nix 环境
if ! command -v nix >/dev/null 2>&1; then
  echo "正在安装官方 Nix 包管理器..."
  curl -L https://nixos.org/nix/install | sh -s -- --daemon

  if [ -f "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]; then
    # shellcheck disable=SC1091
    source "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
  else
    echo "Nix 安装完成。请运行 'source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' 后再次执行本脚本。"
    exit 0
  fi
fi

# 3. 设置输出目录
OUT_DIR="$PWD/nixos-config"
mkdir -p "$OUT_DIR"

# 4. 核心：调用官方工具 (按需精确拉取，不解压庞大的 Channel)
echo "正在调用官方 nixos-generate-config (通过 Flakes 极速获取)..."
SUDO_CMD=$([ "$EUID" -eq 0 ] && echo "" || echo "sudo")

# shellcheck disable=SC2086
nix shell --extra-experimental-features "nix-command flakes" github:NixOS/nixpkgs/nixos-unstable#nixos-install-tools -c $SUDO_CMD nixos-generate-config --dir "$OUT_DIR"

# 5. 极致清理：执行深度垃圾回收
echo "正在清理临时缓存释放存储空间..."
# shellcheck disable=SC2086
$SUDO_CMD nix-collect-garbage -d >/dev/null 2>&1 || true

echo "=== 执行完毕！ ==="
echo "官方配置文件已成功生成，保存在: $OUT_DIR"
