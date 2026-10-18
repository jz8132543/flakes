{ pkgs, lib, ... }:
let
  bottles-orig = pkgs.bottles.override { removeWarningPopup = true; };
  bottles-auto-dpi = pkgs.symlinkJoin {
    name = "bottles-gnome-auto-dpi";
    inherit (bottles-orig) meta;
    paths = [ bottles-orig ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      for bin in $out/bin/bottles*; do
        if [ -f "$bin" ] && [ -x "$bin" ]; then
          wrapProgram "$bin" \
            --prefix PATH : ${
              lib.makeBinPath [
                pkgs.glib
                pkgs.xrdb
                pkgs.gawk
                pkgs.gnused
                pkgs.coreutils
              ]
            } \
            --run '
              # 1. 动态检测 GNOME / XWayland 实际缩放倍率
              scale=$(gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig --method org.gnome.Mutter.DisplayConfig.GetCurrentState 2>/dev/null | sed -E -n "s/.*\[\([0-9]+, [0-9]+, ([0-9.]+), uint32 [0-9]+, (true|false).*/\1/p" | head -n1)
              if [ -z "$scale" ]; then
                xft_dpi=$(xrdb -query 2>/dev/null | awk "/Xft.dpi:/ {print int(\$2)}")
                if [ -n "$xft_dpi" ] && [ "$xft_dpi" -gt 0 ]; then
                  scale=$(awk -v d="$xft_dpi" "BEGIN { print d / 96 }")
                else
                  scale=$(gsettings get org.gnome.desktop.interface scaling-factor 2>/dev/null | awk "{print \$2}")
                  [ "$scale" = "0" ] || [ -z "$scale" ] && scale=1.0
                fi
              fi

              # 2. 计算目标 DPI
              target_dpi=$(awk -v s="$scale" "BEGIN { dpi = int(96 * s + 0.5); print (dpi > 0 ? dpi : 96) }")
              hex_dpi=$(printf "%08x" "$target_dpi")
              export BOTTLES_DEFAULT_DPI="$target_dpi"

              # 3. 自动同步当前用户所有已有 Bottle 容器的 DPI 与 Wine 注册表
              bottles_dir="$HOME/.local/share/bottles/bottles"
              if [ -d "$bottles_dir" ]; then
                for b in "$bottles_dir"/*; do
                  [ -d "$b" ] || continue
                  if [ -f "$b/bottle.yml" ]; then
                    sed -i -E "s/(custom_dpi:\s*)[0-9]+/\1$target_dpi/" "$b/bottle.yml"
                  fi
                  if [ -f "$b/user.reg" ]; then
                    if grep -q "\"LogPixels\"=" "$b/user.reg"; then
                      sed -i -E "s/\"LogPixels\"=dword:[0-9a-fA-F]+/\"LogPixels\"=dword:$hex_dpi/g" "$b/user.reg"
                    else
                      sed -i -E "/\[Control Panel\\\\Desktop\]/a \"LogPixels\"=dword:$hex_dpi" "$b/user.reg"
                    fi
                  fi
                  if [ -f "$b/system.reg" ]; then
                    if grep -q "\"LogPixels\"=" "$b/system.reg"; then
                      sed -i -E "s/\"LogPixels\"=dword:[0-9a-fA-F]+/\"LogPixels\"=dword:$hex_dpi/g" "$b/system.reg"
                    else
                      sed -i -E "/\[System\\\\ControlSet001\\\\Hardware Profiles\\\\Current\\\\Software\\\\Fonts\]/a \"LogPixels\"=dword:$hex_dpi" "$b/system.reg"
                    fi
                  fi
                done
              fi
            '
        fi
      done
    '';
  };
in
{
  environment.systemPackages = [
    bottles-auto-dpi
  ];

  environment.global-persistence.user.directories = [
    ".local/share/bottles"
    ".config/bottles"
    ".local/share/ms365"
    ".local/share/umu"
  ];
}
