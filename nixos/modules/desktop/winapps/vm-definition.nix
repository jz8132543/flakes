{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.desktop.winapps;

  extraDisksXml = lib.concatStringsSep "\n" (
    lib.imap0 (i: disk: ''
      <disk type='block' device='disk'>
        <driver name='qemu' type='raw' cache='none' io='native'/>
        <source dev='${disk}'/>
        <target dev='vd${builtins.substring i 1 "bcdefghijklmnopqrstuvwxyz"}' bus='virtio'/>
      </disk>
    '') cfg.kvm.extraDisks
  );

  winappsXmlTemplate = pkgs.writeText "winapps-vm.xml.in" ''
        <domain type='kvm' xmlns:qemu='http://libvirt.org/schemas/domain/qemu/1.0'>
          <name>Windows-WinApps</name>
          <memory unit='KiB'>8388608</memory>
          <vcpu placement='static'>4</vcpu>
          <os firmware='efi'>
            <type arch='x86_64' machine='pc-q35-8.1'>hvm</type>
            <smbios mode='host'/>
          </os>
          <features>
            <acpi/>
            <apic/>
            <hyperv mode='custom'>
              <relaxed state='on'/>
              <vapic state='on'/>
              <spinlocks state='on' retries='8191'/>
            </hyperv>
            <vmport state='off'/>
          </features>
          <cpu mode='host-passthrough' check='none' migratability='on'/>
          <clock offset='localtime'>
            <timer name='rtc' tickpolicy='catchup'/>
            <timer name='pit' tickpolicy='delay'/>
            <timer name='hpet' present='no'/>
            <timer name='hypervclock' present='yes'/>
          </clock>
          <on_poweroff>destroy</on_poweroff>
          <on_reboot>restart</on_reboot>
          <on_crash>destroy</on_crash>
          <devices>
            <emulator>${pkgs.qemu_kvm}/bin/qemu-system-x86_64</emulator>
            <!-- Dynamic Physical Boot Disk -->
            <disk type='block' device='disk'>
              <driver name='qemu' type='raw' cache='none' io='native'/>
              <source dev='__WINDOWS_DISK_PLACEHOLDER__'/>
              <target dev='vda' bus='virtio'/>
              <boot order='1'/>
            </disk>
            <!-- Extra Disks -->
    ${extraDisksXml}
    ${lib.optionalString cfg.enableCdrom ''
      <!-- Physical CD/DVD Drive Passthrough -->
      <disk type='block' device='cdrom'>
        <driver name='qemu' type='raw'/>
        <source dev='/dev/cdrom'/>
        <target dev='hdc' bus='sata'/>
        <readonly/>
      </disk>
    ''}
            <controller type='usb' index='0' model='qemu-xhci'/>
            <interface type='network'>
              <source network='default'/>
              <model type='virtio'/>
            </interface>
            <input type='tablet' bus='usb'/>
            <input type='keyboard' bus='usb'/>
            <graphics type='spice' autoport='yes'>
              <listen type='address'/>
              <image compression='off'/>
            </graphics>
            <sound model='ich9'/>
            <video>
              <model type='qxl' ram='65536' vram='65536' vgamem='16384' heads='1' primary='yes'/>
            </video>
            <redirdev bus='usb' type='spicevmc'/>
            <redirdev bus='usb' type='spicevmc'/>
          </devices>
          <!-- Inject SLIC table for OEM Windows Activation -->
          <qemu:commandline>
            <qemu:arg value='-acpitable'/>
            <qemu:arg value='sig=SLIC,file=${cfg.kvm.slicAcpiPath}'/>
          </qemu:commandline>
        </domain>
  '';
in
{
  config = lib.mkIf cfg.kvm.enable {
    systemd.services.define-winapps-vm = {
      description = "Auto-detect Windows disk and define WinApps KVM VM";
      wantedBy = [ "multi-user.target" ];
      after = [ "libvirtd.service" ];
      requires = [ "libvirtd.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -eu

        # 1. Dynamically find the Windows Boot Partition using os-prober
        echo "Probing for Windows installation..."
        WIN_PART_RAW=$(${pkgs.os-prober}/bin/os-prober | grep -i "windows" | cut -d: -f1 | head -n 1 || true)

        if [ -n "$WIN_PART_RAW" ]; then
          # os-prober might return /dev/nvme1n1p2@/EFI/... so we strip everything after @
          WIN_PART=$(echo "$WIN_PART_RAW" | cut -d@ -f1)
          echo "Found Windows partition at $WIN_PART"
          
          # 2. Get the parent physical disk using lsblk
          PARENT_KNAME=$(${pkgs.util-linux}/bin/lsblk -rno PKNAME "$WIN_PART" || true)
          if [ -n "$PARENT_KNAME" ]; then
             WIN_DISK="/dev/$PARENT_KNAME"
             echo "Resolved parent physical disk to $WIN_DISK"
          else
             # Fallback if it's already a full disk or an error occurred
             WIN_DISK="$WIN_PART"
          fi
        else
          echo "WARNING: Could not automatically detect Windows partition. Will fallback to /dev/null to prevent XML errors."
          WIN_DISK="/dev/null"
        fi

        # 3. Inject the disk path into the XML template
        TMP_XML="/tmp/winapps-vm-resolved.xml"
        sed "s|__WINDOWS_DISK_PLACEHOLDER__|$WIN_DISK|g" ${winappsXmlTemplate} > $TMP_XML

        # 4. Handle UUID to prevent 'domain already exists with uuid' errors
        if ${pkgs.libvirt}/bin/virsh list --all --name | grep -q "^Windows-WinApps$"; then
          echo "Windows-WinApps VM already exists. Extracting UUID to preserve it..."
          EXISTING_UUID=$(${pkgs.libvirt}/bin/virsh domuuid Windows-WinApps || true)
          if [ -n "$EXISTING_UUID" ]; then
            sed -i "s|<name>Windows-WinApps</name>|<name>Windows-WinApps</name>\n      <uuid>$EXISTING_UUID</uuid>|g" $TMP_XML
          fi
        fi

        # 5. Define the VM in libvirt
        echo "Defining Windows-WinApps VM from resolved XML..."
        ${pkgs.libvirt}/bin/virsh define $TMP_XML

        rm -f $TMP_XML
      '';
    };
  };
}
