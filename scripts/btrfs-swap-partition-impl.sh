#!/usr/bin/env bash
# btrfs-swap-partition-impl.sh
#
# 核心逻辑：在 initrd 中自动扩展 NIXOS 分区并切出 Swap 分区。
# 支持 btrfs / ext4，自动检测分区类型。
#
# 环境变量（供测试覆盖，生产环境由 nix 内联展开）：
#   ROOT_DEV    - NIXOS 分区设备路径，默认 /dev/disk/by-partlabel/NIXOS
#   SWAP_DEV    - SWAP 分区设备路径，默认 /dev/disk/by-partlabel/SWAP
#   RAM_KB      - 内存 KB 数（测试用），默认读 /proc/meminfo
#
# 设计原则：
#   路径A：NIXOS 后方有未分配空间
#     → 在未分配空间末端切出 swap，其余全部扩给 NIXOS
#     → 若未分配空间 < 128 MiB，只扩展 NIXOS 不创建 swap
#   路径B：无未分配空间，需从 NIXOS 内部缩减
#     → 读文件系统最小占用，计算可缩减量（需保留 1 GiB 安全余量）
#     → 先缩减文件系统，再缩减分区，最后创建 swap
#     → 若可缩减量 < 128 MiB，跳过 swap
#   - 任何失败都 exit 0 以保证系统能继续启动

set -ux

ROOT_PART_LABEL="NIXOS"
SWAP_PART_LABEL="SWAP"
ROOT_DEV="${ROOT_DEV:-/dev/disk/by-partlabel/${ROOT_PART_LABEL}}"
SWAP_DEV="${SWAP_DEV:-/dev/disk/by-partlabel/${SWAP_PART_LABEL}}"
# 1 GiB 安全余量：文件系统压缩到最小使用量后至少再留这么多
FS_RESERVE_BYTES=$((1 * 1024 * 1024 * 1024))
# swap 最小 128 MiB，小于此则不创建
MIN_SWAP_BYTES=$((128 * 1024 * 1024))

# ── 日志 ─────────────────────────────────────────────────
log() { echo "cloud-btrfs-swap-partition: $*"; }

# ── btrfs 临时挂载点 ──────────────────────────────────────
BTRFS_MNT="/btrfs_tmp"
BTRFS_MOUNTED=0

btrfs_mount() {
  mkdir -p "$BTRFS_MNT"
  if mount -t btrfs -o subvolid=5 "$ROOT_DEV" "$BTRFS_MNT" 2>/dev/null; then
    BTRFS_MOUNTED=1
    return 0
  fi
  return 1
}

btrfs_umount() {
  if [ "$BTRFS_MOUNTED" = "1" ]; then
    umount "$BTRFS_MNT" 2>/dev/null || true
    BTRFS_MOUNTED=0
  fi
}

# ── 清理并以 0 退出（保证启动继续） ──────────────────────
cleanup_exit() {
  local msg="${1:-}"
  [ -n "$msg" ] && log "$msg"
  btrfs_umount
  exit 0
}

trap 'cleanup_exit "unexpected error, aborting safely"' ERR
trap 'btrfs_umount' EXIT

# ═══════════════════════════════════════════════════════════
# 前置检查
# ═══════════════════════════════════════════════════════════
log "start"

if [ ! -e "$ROOT_DEV" ]; then
  cleanup_exit "root device $ROOT_DEV not found, skipping"
fi

# ── 检测分区信息 ──────────────────────────────────────────
root_disk_name=$(lsblk -no PKNAME "$ROOT_DEV" 2>/dev/null | head -n1 | tr -d '[:space:]')
root_part_name=$(lsblk -no KNAME "$ROOT_DEV" 2>/dev/null | head -n1 | tr -d '[:space:]')
root_partnum=$(lsblk -no PARTN "$ROOT_DEV" 2>/dev/null | head -n1 | tr -d '[:space:]')
# 自动检测文件系统类型（btrfs / ext4）
fstype=$(lsblk -no FSTYPE "$ROOT_DEV" 2>/dev/null | head -n1 | tr -d '[:space:]')

if [ -z "$root_disk_name" ] || [ -z "$root_part_name" ] || [ -z "$root_partnum" ]; then
  cleanup_exit "cannot resolve partition geometry"
fi

if [ "$fstype" != "btrfs" ] && [ "$fstype" != "ext4" ]; then
  cleanup_exit "unsupported filesystem '$fstype' (only btrfs/ext4 supported)"
fi

root_disk="/dev/$root_disk_name"
log "detected: disk=$root_disk part=$root_part_name num=$root_partnum fstype=$fstype"

# 检查是否已有 SWAP 分区（用分区标签检查，比设备路径更可靠）
if lsblk -no PARTLABEL "$root_disk" 2>/dev/null | grep -Fqx "$SWAP_PART_LABEL"; then
  cleanup_exit "swap partition label already exists on disk, skipping"
fi

# ── 读取扇区信息 ──────────────────────────────────────────
# 优先用 sysfs，更可靠
root_part_sysfs="/sys/class/block/$root_part_name"
[ ! -e "$root_part_sysfs/start" ] && root_part_sysfs="/sys/class/block/$root_disk_name/$root_part_name"
root_disk_sysfs="/sys/class/block/$root_disk_name"

if [ ! -f "$root_part_sysfs/start" ] || [ ! -f "$root_disk_sysfs/size" ]; then
  cleanup_exit "sysfs geometry missing"
fi

root_start=$(cat "$root_part_sysfs/start")
root_size=$(cat "$root_part_sysfs/size")
disk_size=$(cat "$root_disk_sysfs/size")
sector_size=$(cat "$root_disk_sysfs/queue/logical_block_size" 2>/dev/null || echo 512)

if [ "$root_start" -le 0 ] || [ "$root_size" -le 0 ] || [ "$disk_size" -le 0 ]; then
  cleanup_exit "invalid sector geometry"
fi

root_end=$((root_start + root_size - 1)) # NIXOS 末扇区（含）
last_usable=$((disk_size - 34))          # GPT 保留 33 扇区尾部

# ── 确定 NIXOS 后方到下一个已有分区之间的空闲范围 ─────────
# 只取 NIXOS 分区之后紧邻的连续未分配区域
# next_part_start：NIXOS 后方第一个分区的起始扇区（若有）
next_part_start=$(lsblk -nrpo TYPE,START "$root_disk" 2>/dev/null |
  awk -v end="$root_end" '$1=="part" && $2>end { if (min=="" || $2<min) min=$2 } END { print min+0 }')

if [ "$next_part_start" -gt 0 ]; then
  # 有其他分区在 NIXOS 后面，空闲空间上边界为其前一扇区
  free_end=$((next_part_start - 1))
else
  free_end=$last_usable
fi

free_sectors=$((free_end > root_end ? free_end - root_end : 0))
free_bytes=$((free_sectors * sector_size))

log "root: start=$root_start end=$root_end | free_after: sectors=$free_sectors bytes=$free_bytes"

# ── RAM 大小（swap 目标大小） ─────────────────────────────
if [ -n "${RAM_KB:-}" ]; then
  ram_bytes=$((RAM_KB * 1024))
else
  ram_kb=$(awk '/^MemTotal:/ { print $2; exit }' /proc/meminfo 2>/dev/null || echo 0)
  ram_bytes=$((ram_kb * 1024))
fi
[ "$ram_bytes" -le 0 ] && ram_bytes=$((512 * 1024 * 1024)) # 默认 512 MiB
log "ram_bytes=$ram_bytes"

# ═══════════════════════════════════════════════════════════
# ── 辅助：修复 GPT 并重读分区表 ──────────────────────────
gpt_settle() {
  sgdisk -e "$root_disk" 2>/dev/null || true
  partprobe "$root_disk" 2>/dev/null || true
  udevadm settle --timeout=10 2>/dev/null || true
}

settle() {
  partprobe "$root_disk" 2>/dev/null || true
  # partx -u forces kernel to re-read the partition table even if the disk is busy
  partx -u "$root_disk" 2>/dev/null || true
  udevadm settle --timeout=10 2>/dev/null || true
}

# ── 辅助：找一个空闲分区编号 ─────────────────────────────
find_free_partnum() {
  lsblk -no PARTN "$root_disk" 2>/dev/null |
    awk '/^[0-9]+$/ {used[$1]=1} END {for(i=1;i<=128;i++) if(!used[i]) {print i; exit}}'
}

# ── 辅助：扩展分区到目标末扇区（不改变起始扇区） ─────────
expand_partition() {
  local new_end=$1
  log "expanding partition $root_partnum to sector $new_end"
  gpt_settle
  sgdisk \
    --delete="$root_partnum" \
    --new="$root_partnum:$root_start:$new_end" \
    --typecode="$root_partnum:8300" \
    --change-name="$root_partnum:$ROOT_PART_LABEL" \
    "$root_disk" 2>/dev/null || return 1
  settle
}

# ── 辅助：缩减分区到目标末扇区 ───────────────────────────
shrink_partition() {
  local new_end=$1
  log "shrinking partition $root_partnum to sector $new_end"
  sgdisk \
    --delete="$root_partnum" \
    --new="$root_partnum:$root_start:$new_end" \
    --typecode="$root_partnum:8300" \
    --change-name="$root_partnum:$ROOT_PART_LABEL" \
    "$root_disk" 2>/dev/null || return 1
  settle
}

# ── 辅助：创建 swap 分区并格式化 ─────────────────────────
create_swap_partition() {
  local swap_start=$1 swap_end=$2
  local swap_partnum
  swap_partnum=$(find_free_partnum)
  if [ -z "$swap_partnum" ] || [ "$swap_partnum" -le 0 ]; then
    log "no free partition number for swap"
    return 1
  fi
  log "creating swap partition $swap_partnum: sectors $swap_start-$swap_end"
  sgdisk \
    --new="$swap_partnum:$swap_start:$swap_end" \
    --typecode="$swap_partnum:8200" \
    --change-name="$swap_partnum:$SWAP_PART_LABEL" \
    "$root_disk" 2>/dev/null || return 1
  settle
  # Wait for the swap device node to actually appear (up to 15s)
  local waited=0
  while [ ! -b "$SWAP_DEV" ] && [ $waited -lt 15 ]; do
    sleep 1
    waited=$((waited + 1))
    partx -u "$root_disk" 2>/dev/null || true
    udevadm settle --timeout=5 2>/dev/null || true
  done
  if [ ! -b "$SWAP_DEV" ]; then
    log "swap device $SWAP_DEV did not appear after partition creation"
    return 1
  fi
  mkswap -L "$SWAP_PART_LABEL" "$SWAP_DEV" 2>/dev/null || return 1
  swapoff -a 2>/dev/null || true
  swapon "$SWAP_DEV" 2>/dev/null || true
  log "swap created and activated"
}

# ── 辅助：扩展文件系统到分区末端 ─────────────────────────
expand_fs() {
  if [ "$fstype" = "btrfs" ]; then
    btrfs_mount || {
      log "btrfs mount failed, skipping fs expand"
      return 0
    }
    btrfs filesystem resize max "$BTRFS_MNT" 2>/dev/null || true
    btrfs filesystem sync "$BTRFS_MNT" 2>/dev/null || true
    btrfs_umount
  elif [ "$fstype" = "ext4" ]; then
    e2fsck -f -p "$ROOT_DEV" 2>/dev/null || true
    resize2fs "$ROOT_DEV" 2>/dev/null || true
  fi
}

# ── 辅助：读取文件系统最小所需字节数 ─────────────────────
# 返回：文件系统现有数据占用的最小字节数（不含安全余量）
get_fs_min_bytes() {
  if [ "$fstype" = "btrfs" ]; then
    btrfs_mount || {
      echo 0
      return
    }
    local val
    val=$(btrfs inspect-internal min-dev-size "$BTRFS_MNT" 2>/dev/null |
      awk '/^[0-9]/ {print $1; exit}')
    btrfs_umount
    echo "${val:-0}"
  elif [ "$fstype" = "ext4" ]; then
    e2fsck -f -p "$ROOT_DEV" >/dev/null 2>&1 || true
    local block_size min_blocks
    block_size=$(dumpe2fs -h "$ROOT_DEV" 2>/dev/null |
      awk '/^Block size:/ {print $3; exit}')
    min_blocks=$(resize2fs -P "$ROOT_DEV" 2>/dev/null |
      awk '{for(i=1;i<=NF;i++) if($i~/^[0-9]+$/) {print $i; exit}}')
    block_size=${block_size:-4096}
    if [ -n "$min_blocks" ] && [ "$min_blocks" -gt 0 ]; then
      echo $((min_blocks * block_size))
    else
      echo 0
    fi
  else
    echo 0
  fi
}

# ── 辅助：缩减文件系统到目标字节数 ──────────────────────
shrink_fs_to() {
  local target_bytes=$1
  if [ "$fstype" = "btrfs" ]; then
    btrfs_mount || return 1
    local target_mib=$((target_bytes / 1048576))
    log "shrinking btrfs to ${target_mib} MiB"
    btrfs filesystem resize "${target_mib}M" "$BTRFS_MNT" 2>/dev/null || {
      btrfs_umount
      return 1
    }
    btrfs filesystem sync "$BTRFS_MNT" 2>/dev/null || true
    btrfs_umount
  elif [ "$fstype" = "ext4" ]; then
    local block_size
    block_size=$(dumpe2fs -h "$ROOT_DEV" 2>/dev/null |
      awk '/^Block size:/ {print $3; exit}')
    block_size=${block_size:-4096}
    local target_blocks=$((target_bytes / block_size))
    log "shrinking ext4 to ${target_blocks} blocks ($((target_bytes / 1048576)) MiB)"
    e2fsck -f -p "$ROOT_DEV" 2>/dev/null || true
    resize2fs "$ROOT_DEV" "$target_blocks" 2>/dev/null || return 1
  fi
}

# ═══════════════════════════════════════════════════════════
# 主逻辑
# ═══════════════════════════════════════════════════════════

if [ "$free_sectors" -gt 0 ]; then
  # ┌────────────────────────────────────────────────────────
  # │ 路径 A：NIXOS 后方有未分配空间
  # │ 策略：在未分配空间末端切 swap，其余全部给 NIXOS
  # └────────────────────────────────────────────────────────
  log "PATH A: unallocated space found after NIXOS ($((free_bytes / 1048576)) MiB)"

  # swap 大小 = min(RAM, free_space)，但要保证 NIXOS 至少能扩展（哪怕 0 字节也可以）
  desired_swap_bytes=$ram_bytes
  [ "$desired_swap_bytes" -gt "$free_bytes" ] && desired_swap_bytes=$free_bytes

  # 对齐到 MiB
  desired_swap_mib=$((desired_swap_bytes / 1048576))
  desired_swap_bytes=$((desired_swap_mib * 1048576))
  desired_swap_sectors=$((desired_swap_bytes / sector_size))

  if [ "$desired_swap_bytes" -lt "$MIN_SWAP_BYTES" ]; then
    # 空间太少，不值得切 swap，直接把全部空间扩给 NIXOS
    log "free space too small for swap (${desired_swap_mib} MiB < min), expanding NIXOS only"
    expand_partition "$free_end" || cleanup_exit "partition expand failed"
    expand_fs
    cleanup_exit "done: NIXOS expanded, no swap (insufficient free space)"
  fi

  # 正常：扩展 NIXOS 到 (free_end - swap_sectors)，swap 紧随其后
  nixos_new_end=$((free_end - desired_swap_sectors))
  swap_start=$((nixos_new_end + 1))

  log "plan: NIXOS end=$nixos_new_end, swap $swap_start-$free_end (${desired_swap_mib} MiB)"

  # 1. 先扩展 NIXOS 分区到 nixos_new_end（比原来大）
  expand_partition "$nixos_new_end" || cleanup_exit "partition expand failed"

  # 2. 扩展文件系统到新的分区大小
  expand_fs

  # 3. 创建 swap 分区
  create_swap_partition "$swap_start" "$free_end" || cleanup_exit "swap creation failed"

  log "done (PATH A)"

else
  # ┌────────────────────────────────────────────────────────
  # │ 路径 B：无未分配空间，需从 NIXOS 内部缩减
  # │ 策略：读文件系统最小占用，计算可缩减量，切出 swap
  # │ 顺序：先缩减文件系统 → 再缩减分区 → 最后创建 swap
  # └────────────────────────────────────────────────────────
  log "PATH B: no unallocated space, attempting to shrink NIXOS for swap"

  root_bytes=$((root_size * sector_size))
  fs_min_bytes=$(get_fs_min_bytes)

  if [ "$fs_min_bytes" -le 0 ]; then
    cleanup_exit "cannot determine filesystem usage, skipping"
  fi

  # 文件系统可缩减上限：当前大小 - 最小占用 - 1 GiB 安全余量
  shrinkable_bytes=$((root_bytes - fs_min_bytes - FS_RESERVE_BYTES))
  log "fs_min=${fs_min_bytes}B shrinkable=${shrinkable_bytes}B ram=${ram_bytes}B"

  if [ "$shrinkable_bytes" -lt "$MIN_SWAP_BYTES" ]; then
    cleanup_exit "not enough shrinkable space (${shrinkable_bytes}B < ${MIN_SWAP_BYTES}B min), skipping swap"
  fi

  # swap 大小 = min(RAM, 可缩减量)，对齐 MiB
  desired_swap_bytes=$ram_bytes
  [ "$desired_swap_bytes" -gt "$shrinkable_bytes" ] && desired_swap_bytes=$shrinkable_bytes
  desired_swap_mib=$((desired_swap_bytes / 1048576))
  desired_swap_bytes=$((desired_swap_mib * 1048576))
  desired_swap_sectors=$((desired_swap_bytes / sector_size))

  if [ "$desired_swap_bytes" -lt "$MIN_SWAP_BYTES" ]; then
    cleanup_exit "calculated swap too small (${desired_swap_bytes}B), skipping"
  fi

  # NIXOS 新的末扇区
  nixos_new_end=$((root_end - desired_swap_sectors))
  nixos_new_bytes=$(((nixos_new_end - root_start + 1) * sector_size))
  swap_start=$((nixos_new_end + 1))

  log "plan: shrink NIXOS to sector $nixos_new_end ($((nixos_new_bytes / 1048576)) MiB), swap $swap_start-$root_end (${desired_swap_mib} MiB)"

  # 1. 先缩减文件系统（必须先于分区缩减，否则会截断数据！）
  shrink_fs_to "$nixos_new_bytes" || cleanup_exit "filesystem shrink failed, aborting to protect data"

  # 2. 缩减分区
  shrink_partition "$nixos_new_end" || {
    # 分区缩减失败，尝试把文件系统恢复到原大小
    log "partition shrink failed, attempting to restore filesystem"
    expand_fs
    cleanup_exit "partition shrink failed"
  }

  # 3. 创建 swap 分区
  create_swap_partition "$swap_start" "$root_end" || cleanup_exit "swap creation failed"

  log "done (PATH B)"
fi
