#! /nix/store/q1c2flcykgr4wwg5a6h450hxbk4ch589-bash-5.2-p15/bin/bash
export PATH=/nix/store/bpjd8324a6qj34zxhn5asgvi8bpm9bb2-jq-1.7-bin/bin:/nix/store/xv65dhpwdqblhnzglfkrb4l6mm3ymx8r-parted-3.6/bin:/nix/store/i0m67bhvzs6gddyh5pgd37kf62xdj0kn-systemd-minimal-254.3/bin:/nix/store/wijccjzl2g8knym08ixzbhqp06p8d2ck-util-linux-2.39.2-bin/bin:/nix/store/gca7ia36lyj5zwlgi7pwff6y8xsira76-dosfstools-4.2/bin:/nix/store/r7mfa5s3rhy3w3sb4x706c4rbpx0mphx-btrfs-progs-6.6.2/bin:/nix/store/bblyj5b3ii8n6v4ra0nb37cmi3lf8rz9-coreutils-9.3/bin:$PATH
set -efux
# first create the necessary devices
(
  device='/dev/nvme0n1'
  imageSize='2G'
  name='main'
  type='disk'
  
  (
    device='/dev/nvme0n1'
    format='gpt'
    type='table'
    
    
    
  )
  
  
)


# and then mount the filesystems in alphabetical order
(
  device='/dev/nvme0n1'
  imageSize='2G'
  name='main'
  type='disk'
  
  (
    device='/dev/nvme0n1'
    format='gpt'
    type='table'
    
    (
      device='/dev/nvme0n1p5'
      declare -a extraArgs=('-f')
      declare -a mountOptions=('defaults')
      mountpoint=''
      type='btrfs'
      
      if ! findmnt /dev/nvme0n1p5 "/mnt/" > /dev/null 2>&1; then
        mount /dev/nvme0n1p5 "/mnt/" \
        -o discard -o noatime -o nodiratime -o ssd_spread -o compress-force=zstd -o space_cache=v2 -o subvol=/rootfs \
        -o X-mount.mkdir
      fi
      
      
    )
    
    
  )
  
  
)
(
  device='/dev/nvme0n1'
  imageSize='2G'
  name='main'
  type='disk'
  
  (
    device='/dev/nvme0n1'
    format='gpt'
    type='table'
    
    (
      device='/dev/nvme0n1p5'
      declare -a extraArgs=('-f')
      declare -a mountOptions=('defaults')
      mountpoint=''
      type='btrfs'
      
      if ! findmnt /dev/nvme0n1p5 "/mnt/boot" > /dev/null 2>&1; then
        mount /dev/nvme0n1p5 "/mnt/boot" \
        -o discard -o noatime -o nodiratime -o ssd_spread -o compress-force=zstd -o space_cache=v2 -o subvol=/boot \
        -o X-mount.mkdir
      fi
      
      
    )
    
    
  )
  
  
)
(
  device='/dev/nvme0n1'
  imageSize='2G'
  name='main'
  type='disk'
  
  (
    device='/dev/nvme0n1'
    format='gpt'
    type='table'
    
    (
      device='/dev/nvme0n1p1'
      declare -a extraArgs=()
      format='vfat'
      declare -a mountOptions=('defaults')
      mountpoint='/boot/efi'
      type='filesystem'
      
      if ! findmnt /dev/nvme0n1p1 "/mnt/boot/efi" >/dev/null 2>&1; then
        mount /dev/nvme0n1p1 "/mnt/boot/efi" \
          -t "vfat" \
          -o defaults \
          -o X-mount.mkdir
      fi
      
      
    )
    
    
  )
  
  
)
(
  device='/dev/nvme0n1'
  imageSize='2G'
  name='main'
  type='disk'
  
  (
    device='/dev/nvme0n1'
    format='gpt'
    type='table'
    
    (
      device='/dev/nvme0n1p5'
      declare -a extraArgs=('-f')
      declare -a mountOptions=('defaults')
      mountpoint=''
      type='btrfs'
      
      if ! findmnt /dev/nvme0n1p5 "/mnt/nix" > /dev/null 2>&1; then
        mount /dev/nvme0n1p5 "/mnt/nix" \
        -o discard -o noatime -o nodiratime -o ssd_spread -o compress-force=zstd -o space_cache=v2 -o subvol=/nix \
        -o X-mount.mkdir
      fi
      
      
    )
    
    
  )
  
  
)
(
  device='/dev/nvme0n1'
  imageSize='2G'
  name='main'
  type='disk'
  
  (
    device='/dev/nvme0n1'
    format='gpt'
    type='table'
    
    (
      device='/dev/nvme0n1p5'
      declare -a extraArgs=('-f')
      declare -a mountOptions=('defaults')
      mountpoint=''
      type='btrfs'
      
      if ! findmnt /dev/nvme0n1p5 "/mnt/persist" > /dev/null 2>&1; then
        mount /dev/nvme0n1p5 "/mnt/persist" \
        -o discard -o noatime -o nodiratime -o ssd_spread -o compress-force=zstd -o space_cache=v2 -o subvol=/persist \
        -o X-mount.mkdir
      fi
      
      
    )
    
    
  )
  
  
)
(
  device='/dev/nvme0n1'
  imageSize='2G'
  name='main'
  type='disk'
  
  (
    device='/dev/nvme0n1'
    format='gpt'
    type='table'
    
    (
      device='/dev/nvme0n1p5'
      declare -a extraArgs=('-f')
      declare -a mountOptions=('defaults')
      mountpoint=''
      type='btrfs'
      
      if ! findmnt /dev/nvme0n1p5 "/mnt/swap" > /dev/null 2>&1; then
        mount /dev/nvme0n1p5 "/mnt/swap" \
        -o discard -o noatime -o nodiratime -o ssd_spread -o compress-force=zstd -o space_cache=v2 -o subvol=/swap \
        -o X-mount.mkdir
      fi
      
      
    )
    
    
  )
  
  
)


