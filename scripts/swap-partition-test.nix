# swap-partition-test.nix
# 使用 NixOS VM 测试 btrfs-swap-partition-impl.sh 脚本的各种场景
#
# 用法：
#   nix-build /home/tippy/source/flakes/scripts/swap-partition-test.nix
#   nix-build /home/tippy/source/flakes/scripts/swap-partition-test.nix --show-trace -v

{
  pkgs ? import <nixpkgs> { },
}:

let
  implScript = pkgs.writeShellScript "btrfs-swap-partition-impl" (
    builtins.readFile ./btrfs-swap-partition-impl.sh
  );
in
pkgs.testers.runNixOSTest {
  name = "btrfs-swap-partition";

  nodes.machine =
    { pkgs, ... }:
    {
      # 8 GiB 裸磁盘（/dev/vdb），主系统盘 /dev/vda 由 virtualisation 自动创建
      virtualisation.emptyDiskImages = [ 8192 ];
      virtualisation.memorySize = 1024;
      virtualisation.diskSize = 512;

      environment.systemPackages = with pkgs; [
        gptfdisk # sgdisk, gdisk
        btrfs-progs
        e2fsprogs # mkfs.ext4, resize2fs, dumpe2fs, e2fsck
        util-linux # lsblk, mkswap, swapon, blkid, partx
        parted # partprobe
        bash
      ];
    };

  testScript = ''
    IMPL = "${implScript}"

    machine.start()
    machine.wait_for_unit("multi-user.target")

    # ── 辅助函数 ───────────────────────────────────────────

    def settle(dev="/dev/vdb"):
        """Ensure kernel sees up-to-date partition table."""
        machine.succeed(
            # Remove all partition entries then re-add from disk
            f"partx -d {dev} 2>/dev/null || true; "
            f"partx -a {dev} 2>/dev/null || true; "
            f"partprobe {dev} 2>/dev/null || true; "
            f"udevadm settle --timeout=15 2>/dev/null || true; "
            f"sleep 1"
        )

    def swap_exists(dev="/dev/vdb"):
        rc, _ = machine.execute(
            f"lsblk -no PARTLABEL {dev} 2>/dev/null | grep -Fqx SWAP"
        )
        return rc == 0

    def nixos_ok(part, fstype):
        machine.succeed("mkdir -p /mnt/chk")
        if fstype == "btrfs":
            machine.succeed(f"mount -t btrfs -o subvolid=5 {part} /mnt/chk")
        else:
            machine.succeed(f"mount -t ext4 {part} /mnt/chk")
        machine.succeed("umount /mnt/chk")

    def reset_disk(dev="/dev/vdb"):
        """Completely wipe the disk between test cases."""
        machine.succeed(
            # Deactivate any swap from previous test case (otherwise partprobe fails)
            f"swapoff -a 2>/dev/null || true; "
            # sgdisk -Z zeros both primary and backup GPT headers properly
            f"sgdisk -Z {dev} 2>/dev/null || true; "
            # wipefs -a removes all filesystem superblock signatures
            f"wipefs -a {dev} 2>/dev/null || true; "
            # Zero key superblock areas that may still have old signatures
            # Partition 2 typically starts at sector 206848 (100M EFI + 2048 start)
            f"dd if=/dev/zero of={dev} bs=512 seek=204800 count=20480 conv=fsync 2>/dev/null || true; "
            # Also zero the first MiB for GPT area
            f"dd if=/dev/zero of={dev} bs=1M count=2 conv=fsync 2>/dev/null || true"
        )
        settle(dev)

    def part_size_bytes(part):
        return int(machine.succeed(f"lsblk -no SIZE --bytes {part}").strip())

    def run_impl(root_dev, swap_dev, ram_kb=524288):
        rc, out = machine.execute(
            f"ROOT_DEV={root_dev} SWAP_DEV={swap_dev} RAM_KB={ram_kb} "
            f"bash {IMPL} 2>&1 || true"
        )
        print(f"IMPL OUTPUT (rc={rc}):\\n{out}")
        # give udev/kernel extra time to update partlabel symlinks after partition changes
        machine.succeed(
            "partx -u /dev/vdb 2>/dev/null || true; "
            "udevadm settle --timeout=15 2>/dev/null || true; "
            "sleep 1"
        )
        return out

    # ────────────────────────────────────────────────────────
    # Case 1：btrfs NIXOS + 大量未分配空间 → 扩展 + swap 创建
    # ────────────────────────────────────────────────────────
    with subtest("case1_btrfs_free_space"):
        reset_disk()
        machine.succeed(
            "sgdisk -n 1:2048:+100M -t 1:ef00 -c 1:EFI /dev/vdb; "
            "sgdisk -n 2:0:+2G   -t 2:8300 -c 2:NIXOS /dev/vdb"
        )
        settle()
        machine.succeed("mkfs.btrfs -f -L NIXOS /dev/vdb2")
        machine.succeed(
            "mkdir -p /mnt/t && mount -t btrfs /dev/vdb2 /mnt/t && "
            "dd if=/dev/urandom of=/mnt/t/d bs=1M count=100 2>/dev/null && "
            "umount /mnt/t"
        )
        sz_before = part_size_bytes("/dev/vdb2")
        run_impl("/dev/vdb2", "/dev/vdb3", ram_kb=524288)

        assert swap_exists(), "Case 1: swap not created"
        sz_after = part_size_bytes("/dev/vdb2")
        assert sz_after > sz_before, f"Case 1: NIXOS not expanded ({sz_before} -> {sz_after})"
        nixos_ok("/dev/vdb2", "btrfs")
        machine.succeed("lsblk -o NAME,SIZE,PARTLABEL /dev/vdb")
        print("Case 1 PASSED: btrfs free space")

    # ────────────────────────────────────────────────────────
    # Case 2：ext4 NIXOS + 大量未分配空间 → 扩展 + swap 创建
    # ────────────────────────────────────────────────────────
    with subtest("case2_ext4_free_space"):
        reset_disk()
        machine.succeed(
            "sgdisk -n 1:2048:+100M -t 1:ef00 -c 1:EFI /dev/vdb; "
            "sgdisk -n 2:0:+2G   -t 2:8300 -c 2:NIXOS /dev/vdb"
        )
        settle()
        machine.succeed("mkfs.ext4 -F -L NIXOS /dev/vdb2")
        # verify ext4 is readable before test
        machine.succeed("blkid -s TYPE /dev/vdb2 | grep -q ext4")
        machine.succeed(
            "mkdir -p /mnt/t && mount -t ext4 /dev/vdb2 /mnt/t && "
            "dd if=/dev/urandom of=/mnt/t/d bs=1M count=100 2>/dev/null && "
            "umount /mnt/t"
        )
        sz_before = part_size_bytes("/dev/vdb2")
        run_impl("/dev/vdb2", "/dev/vdb3", ram_kb=524288)

        assert swap_exists(), "Case 2: swap not created"
        sz_after = part_size_bytes("/dev/vdb2")
        assert sz_after > sz_before, f"Case 2: NIXOS not expanded ({sz_before} -> {sz_after})"
        nixos_ok("/dev/vdb2", "ext4")
        machine.succeed("lsblk -o NAME,SIZE,PARTLABEL /dev/vdb")
        print("Case 2 PASSED: ext4 free space")

    # ────────────────────────────────────────────────────────
    # Case 3：NIXOS 后紧跟 Windows 分区 + 2G 间隙
    #   预期：swap 只占 NIXOS 和 Windows 之间的空隙
    #         Windows 分区起始扇区不变（不被移动/破坏）
    # ────────────────────────────────────────────────────────
    with subtest("case3_other_partition_gap"):
        reset_disk()
        machine.succeed(
            "sgdisk -n 1:2048:+100M -t 1:ef00 -c 1:EFI    /dev/vdb; "
            "sgdisk -n 2:0:+2G    -t 2:8300 -c 2:NIXOS   /dev/vdb; "
            "sgdisk -n 3:+2G:0   -t 3:0700 -c 3:Windows  /dev/vdb"
        )
        settle()
        machine.succeed("mkfs.btrfs -f -L NIXOS /dev/vdb2")
        machine.succeed("mkfs.ext4 -F /dev/vdb3")
        machine.succeed(
            "mkdir -p /mnt/w && mount -t ext4 /dev/vdb3 /mnt/w && "
            "echo windows-data > /mnt/w/important.txt && "
            "umount /mnt/w"
        )
        win_start = machine.succeed(
            "sgdisk -i 3 /dev/vdb | awk '/First sector:/{print $3}'"
        ).strip()
        run_impl("/dev/vdb2", "/dev/vdb4", ram_kb=524288)

        # Windows 数据完好
        machine.succeed(
            "mount -t ext4 /dev/vdb3 /mnt/w && "
            "grep -q windows-data /mnt/w/important.txt && "
            "umount /mnt/w"
        )
        # Windows 未被移动
        win_start2 = machine.succeed(
            "sgdisk -i 3 /dev/vdb | awk '/First sector:/{print $3}'"
        ).strip()
        assert win_start == win_start2, f"Case 3: Windows moved! {win_start} -> {win_start2}"
        # swap 创建成功且在 Windows 之前
        assert swap_exists(), "Case 3: swap not created"
        swap_s = int(machine.succeed(
            "sgdisk -i 4 /dev/vdb | awk '/First sector:/{print $3}'"
        ).strip())
        assert swap_s < int(win_start), "Case 3: swap ends behind Windows partition start"
        nixos_ok("/dev/vdb2", "btrfs")
        machine.succeed("lsblk -o NAME,SIZE,PARTLABEL /dev/vdb")
        print("Case 3 PASSED: other partition gap (Windows preserved)")

    # ────────────────────────────────────────────────────────
    # Case 4：btrfs 磁盘满，从内部缩减切 swap
    # ────────────────────────────────────────────────────────
    with subtest("case4_btrfs_full_shrink"):
        reset_disk()
        machine.succeed(
            "sgdisk -n 1:2048:+100M -t 1:ef00 -c 1:EFI /dev/vdb; "
            "sgdisk -n 2:0:0      -t 2:8300 -c 2:NIXOS /dev/vdb"
        )
        settle()
        machine.succeed("mkfs.btrfs -f -L NIXOS /dev/vdb2")
        machine.succeed(
            "mkdir -p /mnt/t && mount -t btrfs /dev/vdb2 /mnt/t && "
            "dd if=/dev/urandom of=/mnt/t/d bs=1M count=200 2>/dev/null && "
            "umount /mnt/t"
        )
        run_impl("/dev/vdb2", "/dev/vdb3", ram_kb=524288)

        assert swap_exists(), "Case 4: swap not created"
        nixos_ok("/dev/vdb2", "btrfs")
        machine.succeed("lsblk -o NAME,SIZE,PARTLABEL /dev/vdb")
        print("Case 4 PASSED: btrfs full shrink")

    # ────────────────────────────────────────────────────────
    # Case 5：ext4 磁盘满，缩减切 swap
    # ────────────────────────────────────────────────────────
    with subtest("case5_ext4_full_shrink"):
        reset_disk()
        machine.succeed(
            "sgdisk -n 1:2048:+100M -t 1:ef00 -c 1:EFI /dev/vdb; "
            "sgdisk -n 2:0:0      -t 2:8300 -c 2:NIXOS /dev/vdb"
        )
        settle()
        machine.succeed("mkfs.ext4 -F -L NIXOS /dev/vdb2")
        machine.succeed(
            "mkdir -p /mnt/t && mount -t ext4 /dev/vdb2 /mnt/t && "
            "dd if=/dev/urandom of=/mnt/t/d bs=1M count=200 2>/dev/null && "
            "umount /mnt/t"
        )
        run_impl("/dev/vdb2", "/dev/vdb3", ram_kb=524288)

        assert swap_exists(), "Case 5: swap not created"
        nixos_ok("/dev/vdb2", "ext4")
        machine.succeed("lsblk -o NAME,SIZE,PARTLABEL /dev/vdb")
        print("Case 5 PASSED: ext4 full shrink")

    # ────────────────────────────────────────────────────────
    # Case 6：磁盘满 + 数据极多，无法切 swap → 跳过（不破坏数据）
    # ────────────────────────────────────────────────────────
    with subtest("case6_too_full_skip_swap"):
        reset_disk()
        machine.succeed(
            "sgdisk -n 1:2048:+100M -t 1:ef00 -c 1:EFI /dev/vdb; "
            "sgdisk -n 2:0:0      -t 2:8300 -c 2:NIXOS /dev/vdb"
        )
        settle()
        machine.succeed("mkfs.btrfs -f -L NIXOS /dev/vdb2")
        # 写满磁盘，只留约 400 MiB（< 1 GiB 安全余量 + 128 MiB min_swap）
        machine.succeed(
            "mkdir -p /mnt/t && mount -t btrfs /dev/vdb2 /mnt/t && "
            "avail=$(df -BM /mnt/t | tail -1 | awk '{print $4}' | tr -d M) && "
            "fill=$((avail > 500 ? avail - 500 : 0)) && "
            "[ \"$fill\" -gt 0 ] && dd if=/dev/urandom of=/mnt/t/big bs=1M count=\"$fill\" 2>/dev/null || true; "
            "umount /mnt/t"
        )
        run_impl("/dev/vdb2", "/dev/vdb3", ram_kb=524288)

        assert not swap_exists(), "Case 6: swap created despite full disk"
        nixos_ok("/dev/vdb2", "btrfs")
        print("Case 6 PASSED: too full, swap skipped")

    # ────────────────────────────────────────────────────────
    # Case 7：NIXOS 后仅 ~41 MiB 空隙（< 128 MiB min）
    #   预期：只扩展 NIXOS，不创建 swap
    # ────────────────────────────────────────────────────────
    with subtest("case7_tiny_gap_expand_only"):
        reset_disk()
        machine.succeed(
            "sgdisk -n 1:2048:+100M -t 1:ef00 -c 1:EFI /dev/vdb; "
            # 8050M NIXOS on an 8192M disk leaves only ~41 MiB free (<128 MiB min_swap)
            "sgdisk -n 2:0:+8050M  -t 2:8300 -c 2:NIXOS /dev/vdb"
        )
        settle()
        machine.succeed("mkfs.btrfs -f -L NIXOS /dev/vdb2")
        machine.succeed(
            "mkdir -p /mnt/t && mount -t btrfs /dev/vdb2 /mnt/t && "
            "dd if=/dev/urandom of=/mnt/t/d bs=1M count=50 2>/dev/null && "
            "umount /mnt/t"
        )
        sz_before = part_size_bytes("/dev/vdb2")
        run_impl("/dev/vdb2", "/dev/vdb3", ram_kb=524288)

        assert not swap_exists(), "Case 7: swap created in tiny gap"
        sz_after = part_size_bytes("/dev/vdb2")
        assert sz_after >= sz_before, f"Case 7: NIXOS shrunk ({sz_before} -> {sz_after})"
        nixos_ok("/dev/vdb2", "btrfs")
        machine.succeed("lsblk -o NAME,SIZE,PARTLABEL /dev/vdb")
        print("Case 7 PASSED: tiny gap, expand only (no swap)")

    # ────────────────────────────────────────────────────────
    # Case 8：重复运行 → 幂等性检查（第二次不做任何事）
    # ────────────────────────────────────────────────────────
    with subtest("case8_idempotent"):
        reset_disk()
        machine.succeed(
            "sgdisk -n 1:2048:+100M -t 1:ef00 -c 1:EFI /dev/vdb; "
            "sgdisk -n 2:0:+2G   -t 2:8300 -c 2:NIXOS /dev/vdb"
        )
        settle()
        machine.succeed("mkfs.btrfs -f -L NIXOS /dev/vdb2")
        # 第一次运行
        run_impl("/dev/vdb2", "/dev/vdb3", ram_kb=524288)
        assert swap_exists(), "Case 8: swap not created on first run"
        sz_after_first = part_size_bytes("/dev/vdb2")
        swap_sz_first  = part_size_bytes("/dev/vdb3")

        # 第二次运行
        out2 = run_impl("/dev/vdb2", "/dev/vdb3", ram_kb=524288)
        assert "already" in out2 or "skipping" in out2, "Case 8: second run did not skip"
        sz_after_second = part_size_bytes("/dev/vdb2")
        swap_sz_second  = part_size_bytes("/dev/vdb3")
        assert sz_after_first == sz_after_second, "Case 8: NIXOS size changed on second run"
        assert swap_sz_first  == swap_sz_second,  "Case 8: SWAP size changed on second run"
        nixos_ok("/dev/vdb2", "btrfs")
        print("Case 8 PASSED: idempotent")

    # ────────────────────────────────────────────────────────
    # Case 9：模拟 dd 镜像到更大磁盘
    #   场景：2 GiB 镜像 dd 到 8 GiB 磁盘
    #         分区表来自镜像（小），磁盘末端有 ~5.9 GiB 未分配空间
    #         NIXOS 分区本身满了（先写 100 MiB 数据）
    #   预期：NIXOS 扩展到几乎全盘（留 swap），swap 分区被创建
    #         数据完好
    # ────────────────────────────────────────────────────────
    with subtest("case9_dd_image_to_larger_disk"):
        reset_disk()
        # 模拟 2 GiB 镜像：只用磁盘前 2 GiB 建分区（GPT backup header 在 2 GiB 处）
        # 使用 sgdisk -e 可以把 backup header 挪到磁盘末尾（模拟 dd 后第一次 parted fixup）
        machine.succeed(
            # 建分区，仅用磁盘前 2 GiB
            "sgdisk -n 1:2048:+100M -t 1:ef00 -c 1:EFI /dev/vdb "
            "         --set-alignment=1 "
            "--new=2:0:+1800M -t 2:8300 -c 2:NIXOS /dev/vdb; "
            # 将 GPT backup header 挪到磁盘实际末尾（模拟 dd 后自动修复）
            "sgdisk -e /dev/vdb"
        )
        settle()
        machine.succeed("mkfs.btrfs -f -L NIXOS /dev/vdb2")
        machine.succeed(
            "mkdir -p /mnt/t && mount -t btrfs /dev/vdb2 /mnt/t && "
            "dd if=/dev/urandom of=/mnt/t/userdata bs=1M count=100 2>/dev/null && "
            "umount /mnt/t"
        )

        # 确认磁盘末端确实有大量空闲（~5.8 GiB）
        free_sectors = int(machine.succeed(
            "sgdisk -p /dev/vdb | awk '/Total free space/{print $5; exit}'"
        ).strip() or "0")
        print(f"Free sectors before impl: {free_sectors} (~{free_sectors*512//1048576} MiB)")
        assert free_sectors > 1000000, f"Case 9: not enough free space ({free_sectors} sectors)"

        sz_before = part_size_bytes("/dev/vdb2")
        run_impl("/dev/vdb2", "/dev/vdb3", ram_kb=524288)

        assert swap_exists(), "Case 9: swap not created after dd image expansion"
        sz_after = part_size_bytes("/dev/vdb2")
        assert sz_after > sz_before, f"Case 9: NIXOS not expanded ({sz_before} -> {sz_after})"
        # NIXOS 应扩展到 >> 2G（原始大小）
        assert sz_after > 2 * 1024 * 1024 * 1024, \
            f"Case 9: NIXOS not significantly expanded (only {sz_after//1048576} MiB)"
        # 数据完好
        nixos_ok("/dev/vdb2", "btrfs")
        machine.succeed("mount -t btrfs /dev/vdb2 /mnt/chk && ls /mnt/chk/userdata && umount /mnt/chk")
        machine.succeed("lsblk -o NAME,SIZE,PARTLABEL /dev/vdb")
        print(f"Case 9 PASSED: dd image expanded from {sz_before//1048576} MiB "
              f"to {sz_after//1048576} MiB + swap created")

    print("\\n=== All 9 cases PASSED! ===")
  '';
}
