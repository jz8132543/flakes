{
  lib,
  pkgs,
  ...
}:
let
  catppuccinGrubBase = pkgs.catppuccin-grub.override {
    flavor = "mocha";
  };
  fontSize = 18;
  fontTtf = "${pkgs.nerd-fonts.jetbrains-mono}/share/fonts/truetype/NerdFonts/JetBrainsMono/JetBrainsMonoNerdFont-SemiBold.ttf";
  catppuccinGrub =
    pkgs.runCommand "catppuccin-grub-mocha-jetbrains"
      {
        nativeBuildInputs = [ pkgs.grub2 ];
      }
      ''
        mkdir -p "$out"
        cp -r ${catppuccinGrubBase}/* "$out/"
        chmod -R u+w "$out"

        # 使用 grub-mkfont 从 JetBrains Mono Nerd Font 矢量字体转换生成高清 pf2 字体（含 NixOS、Windows 等图标）
        grub-mkfont --size=${toString fontSize} --name="JetBrainsMono NF" "${fontTtf}" -o "$out/font.pf2"

        # 将主题配置文件中的字体从粗糙的单色点阵 Unifont 替换为 JetBrains Mono Nerd Font
        sed -i "s/Unifont Regular 16/JetBrainsMono NF Regular ${toString fontSize}/g" "$out/theme.txt"
      '';
in
{
  boot = {
    # 自动选择延时 1 秒
    loader.timeout = lib.mkForce 1;

    # GRUB 引导配置
    loader.grub = {
      # 启用 Catppuccin Mocha 主题（搭配 JetBrains Mono Nerd Font 高清矢量字体）
      theme = lib.mkDefault catppuccinGrub;
      font = lib.mkDefault "${catppuccinGrub}/font.pf2";

      # 高分辨率屏幕下原生模式 (auto) 会导致文字和图标极小
      # 设置适宜分辨率（如 1024x768），由硬件/UEFI 缩放显示，使文字与图标比例正常
      gfxmodeEfi = lib.mkDefault "1024x768,auto";
      gfxmodeBios = lib.mkDefault "1024x768";
    };
  };
}
