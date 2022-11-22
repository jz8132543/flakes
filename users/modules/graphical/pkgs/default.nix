{ pkgs, ... }:

let
  windows-run = pkgs.writeShellApplication {
    name = "macos";
    text = ''
      ${pkgs.qemu}/bin/qemu-system-x86_64 \
        -machine q35,accel=kvm,usb=on \
        -smbios type=2 \
        -cpu host \
        -smp sockets=1,cores=4,threads=2 -m 8G \
        -drive id=OpenCoreBoot,if=none,snapshot=on,format=qcow2,file="$XDG_DOCUMENTS_DIR/vm/OpenCore.qcow2" \
        -drive if=pflash,format=raw,readonly=on,file="$XDG_DOCUMENTS_DIR/vm/OVMF_CODE.fd" \
        -drive if=pflash,format=raw,file="$XDG_DOCUMENTS_DIR/vm/OVMF_VARS-1024x768.fd" \
        -drive id=InstallMedia,if=none,file="$XDG_DOCUMENTS_DIR/vm/BaseSystem.img",format=raw \
        -drive id=MacHDD,if=none,file="$XDG_DOCUMENTS_DIR/vm/osx.img",format=raw \
        -device usb-ehci,id=ehci \
        -device nec-usb-xhci,id=xhci \
        -device isa-applesmc,osk="ourhardworkbythesewordsguardedpleasedontsteal(c)AppleComputerInc" \
        -device ich9-intel-hda -device hda-duplex \
        -device ich9-ahci,id=sata \
        -device ide-hd,bus=sata.2,drive=OpenCoreBoot \
        -device ide-hd,bus=sata.3,drive=InstallMedia \
        -device virtio-blk-pci,drive=MacHDD \
        -device virtio-net-pci,netdev=net0,id=net0,mac=f2:05:56:b6:6b:68 \
        -device VGA,vgamem_mb=128 \
        -usb -device usb-tablet -device usb-kbd \
        -global nec-usb-xhci.msi=off \
        -netdev user,id=net0 \
        -display gtk,gl=on \
        "$@"
    '';
  };
in {
  home.packages = [
    windows-run
  ];
}
