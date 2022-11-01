{ pkgs, ... }:

let
  windows-run = pkgs.writeShellApplication {
    name = "windows-run";
    text = ''
      MDEV=/sys/bus/mdev/devices/d577a7cf-2595-44d8-9c08-c67358dcf7ac
      ${pkgs.qemu.override { smbdSupport = true; hostCpuOnly = true; }}/bin/qemu-system-x86_64 \
        -nodefaults \
        -machine q35,accel=kvm \
        -bios ${pkgs.OVMF.fd}/FV/OVMF.fd \
        -smp sockets=1,cores=4,threads=2 -m 8G \
        -cpu host,hv_relaxed,hv_spinlocks=0x1fff,hv_vapic,hv_time \
        -display gtk,gl=on,show-cursor=on \
        -nic user,model=virtio-net-pci,smb="$XDG_DOWNLOAD_DIR" \
        -audiodev pa,id=snd0 \
        -device ich9-intel-hda \
        -device hda-duplex,audiodev=snd0 \
        -usb -device usb-tablet \
        -drive if=virtio,file="$XDG_DOCUMENTS_DIR"/vm/windows.img,format=raw \
        -device vfio-pci,sysfsdev="$MDEV",display=on,x-igd-opregion=on,ramfb=on,driver=vfio-pci-nohotplug,romfile="$XDG_DOCUMENTS_DIR"/vm/vbios_gvt_uefi.rom \
        "$@"
    '';
  };
in {
  home.packages = [
    windows-run
  ];
}
