{ pkgs, inputs, ... }:
{
  nixpkgs.overlays = [
    inputs.chinese-fonts-overlay.overlays.default
  ];
  # all fonts are linked to /nix/var/nix/profiles/system/sw/share/X11/fonts
  fonts = {
    # use fonts specified by user rather than default ones
    enableDefaultPackages = false;
    fontDir.enable = true;

    packages = with pkgs; [
      # 图标字体
      material-design-icons
      font-awesome

      # 编程与终端字体 (JetBrains Mono + Nerd Fonts 图标)
      nerd-fonts.jetbrains-mono
      nerd-fonts.symbols-only

      # 苹果苹方字体 (PingFang SC/TC/HK, 包含完整 6 字重)
      apple-pingfang

      # 现代高质感西文字体 (UI 与网页浏览)
      inter

      # 经典开源中文字体 (高质量无衬线与衬线 fallback)
      source-han-sans
      source-han-serif

      # 彩色表情符号
      noto-fonts-color-emoji

      # 霞鹜文楷与朱雀仿宋 (优雅手写/书法类补充)
      nur.repos.ccicnce113424.lxgw-wenkai-gb
      nur.repos.ccicnce113424.zhuque

      # WPS 办公套件专属符号字体 (解决 mtextra, symbol, wingdings 缺字报错)
      nur.repos.rewine.ttf-wps-fonts

      # Windows 核心字体 (包含 SimSun 宋体等)
      nur.repos.rewine.ttf-ms-win10

      # 国标公文核心方正字库 (方正小标宋_GBK、方正仿宋_GBK、方正楷体_GBK、方正黑体_GBK、方正书宋_GBK)
      foundertype-fonts
    ];

    # 用户首选与回退字体配置
    fontconfig = {
      defaultFonts = {
        sansSerif = [
          "PingFang SC"
          "Inter"
          "Source Han Sans SC"
          "Noto Color Emoji"
        ];
        serif = [
          "Source Han Serif SC"
          "SimSun"
          "Noto Color Emoji"
        ];
        monospace = [
          "JetBrainsMono Nerd Font"
          "JetBrainsMono Nerd Font Mono"
          "PingFang SC"
          "Source Han Sans SC"
          "Noto Color Emoji"
        ];
        emoji = [ "Noto Color Emoji" ];
      };

      localConf = ''
        <?xml version="1.0"?>
        <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
        <fontconfig>
          <!-- 国标公文标准 (GB/T 9704-2012) 字体智能双向别名匹配 (带 _GBK 与 不带 _GBK 完全兼容) -->
          <!-- 方正小标宋 / 方正大标宋 (发文机关标志、主标题) -->
          <match target="pattern">
            <test name="family" qual="any">
              <string>方正小标宋简体</string>
            </test>
            <edit name="family" mode="assign" binding="strong">
              <string>方正小标宋_GBK</string>
            </edit>
          </match>
          <match target="pattern">
            <test name="family" qual="any">
              <string>方正小标宋</string>
            </test>
            <edit name="family" mode="assign" binding="strong">
              <string>方正小标宋_GBK</string>
            </edit>
          </match>
          <match target="pattern">
            <test name="family" qual="any">
              <string>方正大标宋简体</string>
            </test>
            <edit name="family" mode="assign" binding="strong">
              <string>方正小标宋_GBK</string>
            </edit>
          </match>
          <match target="pattern">
            <test name="family" qual="any">
              <string>方正大标宋</string>
            </test>
            <edit name="family" mode="assign" binding="strong">
              <string>方正小标宋_GBK</string>
            </edit>
          </match>

          <!-- 方正仿宋 / 仿宋_GB2312 (公文正文) -->
          <match target="pattern">
            <test name="family" qual="any">
              <string>方正仿宋简体</string>
            </test>
            <edit name="family" mode="assign" binding="strong">
              <string>方正仿宋_GBK</string>
            </edit>
          </match>
          <match target="pattern">
            <test name="family" qual="any">
              <string>方正仿宋</string>
            </test>
            <edit name="family" mode="assign" binding="strong">
              <string>方正仿宋_GBK</string>
            </edit>
          </match>
          <match target="pattern">
            <test name="family" qual="any">
              <string>仿宋_GB2312</string>
            </test>
            <edit name="family" mode="assign" binding="strong">
              <string>方正仿宋_GBK</string>
            </edit>
          </match>
          <match target="pattern">
            <test name="family" qual="any">
              <string>仿宋</string>
            </test>
            <edit name="family" mode="assign" binding="strong">
              <string>方正仿宋_GBK</string>
            </edit>
          </match>
          <match target="pattern">
            <test name="family" qual="any">
              <string>FangSong</string>
            </test>
            <edit name="family" mode="assign" binding="strong">
              <string>方正仿宋_GBK</string>
            </edit>
          </match>

          <!-- 方正楷体 / 楷体_GB2312 (二级标题、签发人) -->
          <match target="pattern">
            <test name="family" qual="any">
              <string>方正楷体简体</string>
            </test>
            <edit name="family" mode="assign" binding="strong">
              <string>方正楷体_GBK</string>
            </edit>
          </match>
          <match target="pattern">
            <test name="family" qual="any">
              <string>方正楷体</string>
            </test>
            <edit name="family" mode="assign" binding="strong">
              <string>方正楷体_GBK</string>
            </edit>
          </match>
          <match target="pattern">
            <test name="family" qual="any">
              <string>楷体_GB2312</string>
            </test>
            <edit name="family" mode="assign" binding="strong">
              <string>方正楷体_GBK</string>
            </edit>
          </match>
          <match target="pattern">
            <test name="family" qual="any">
              <string>楷体</string>
            </test>
            <edit name="family" mode="assign" binding="strong">
              <string>方正楷体_GBK</string>
            </edit>
          </match>
          <match target="pattern">
            <test name="family" qual="any">
              <string>KaiTi</string>
            </test>
            <edit name="family" mode="assign" binding="strong">
              <string>方正楷体_GBK</string>
            </edit>
          </match>

          <!-- 方正黑体 / 黑体 (一级标题) -->
          <match target="pattern">
            <test name="family" qual="any">
              <string>方正黑体简体</string>
            </test>
            <edit name="family" mode="assign" binding="strong">
              <string>方正黑体_GBK</string>
            </edit>
          </match>
          <match target="pattern">
            <test name="family" qual="any">
              <string>方正黑体</string>
            </test>
            <edit name="family" mode="assign" binding="strong">
              <string>方正黑体_GBK</string>
            </edit>
          </match>
          <match target="pattern">
            <test name="family" qual="any">
              <string>黑体</string>
            </test>
            <edit name="family" mode="assign" binding="strong">
              <string>方正黑体_GBK</string>
            </edit>
          </match>
          <match target="pattern">
            <test name="family" qual="any">
              <string>SimHei</string>
            </test>
            <edit name="family" mode="assign" binding="strong">
              <string>方正黑体_GBK</string>
            </edit>
          </match>

          <!-- 方正书宋 / 宋体 (辅衬线) -->
          <match target="pattern">
            <test name="family" qual="any">
              <string>方正书宋简体</string>
            </test>
            <edit name="family" mode="assign" binding="strong">
              <string>方正书宋_GBK</string>
            </edit>
          </match>
          <match target="pattern">
            <test name="family" qual="any">
              <string>方正书宋</string>
            </test>
            <edit name="family" mode="assign" binding="strong">
              <string>方正书宋_GBK</string>
            </edit>
          </match>

          <!-- 苹果系统与网页常用别名映射 -->
          <match target="pattern">
            <test name="family" qual="any">
              <string>-apple-system</string>
            </test>
            <edit name="family" mode="prepend" binding="strong">
              <string>PingFang SC</string>
              <string>Inter</string>
            </edit>
          </match>
          <match target="pattern">
            <test name="family" qual="any">
              <string>BlinkMacSystemFont</string>
            </test>
            <edit name="family" mode="prepend" binding="strong">
              <string>PingFang SC</string>
              <string>Inter</string>
            </edit>
          </match>
          <match target="pattern">
            <test name="family" qual="any">
              <string>苹方-简</string>
            </test>
            <edit name="family" mode="assign" binding="strong">
              <string>PingFang SC</string>
            </edit>
          </match>
          <match target="pattern">
            <test name="family" qual="any">
              <string>苹方</string>
            </test>
            <edit name="family" mode="assign" binding="strong">
              <string>PingFang SC</string>
            </edit>
          </match>
        </fontconfig>
      '';
    };
  };

  # https://wiki.archlinux.org/title/KMSCON
  services.kmscon = {
    # Use kmscon as the virtual console instead of gettys.
    # kmscon is a kms/dri-based userspace virtual terminal implementation.
    # It supports a richer feature set than the standard linux console VT,
    # including full unicode support, and when the video card supports drm should be much faster.
    enable = true;
    extraOptions = "--term xterm-256color";
    # Whether to use 3D hardware acceleration to render the console.
    config.hwaccel = true;
  };

  hardware.graphics.enable = true;
}
