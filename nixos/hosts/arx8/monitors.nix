{pkgs, ...}: {
  systemd.tmpfiles.rules = [
    "f+ /run/gdm/.config/monitors.xml - gdm gdm - ${pkgs.writeText "gdm-monitors.xml" ''
      <!-- this should all be copied from your ~/.config/monitors.xml -->
      <monitors version="2">
        <configuration>
          <logicalmonitor>
            <x>0</x>
            <y>0</y>
            <scale>1.5</scale>
            <primary>yes</primary>
            <monitor>
              <monitorspec>
                <connector>eDP-1</connector>
                <vendor>CSO</vendor>
                <product>0x161b</product>
                <serial>0x00006000</serial>
              </monitorspec>
              <mode>
                <width>2560</width>
                <height>1600</height>
                <rate>240.000</rate>
              </mode>
            </monitor>
          </logicalmonitor>
        </configuration>
      </monitors>
    ''}"
  ];
}
