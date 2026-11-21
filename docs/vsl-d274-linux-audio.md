# VSL D-274：NixOS 低延迟钢琴环境与复现指南

记录日期：2026-11-20。适用机器：`arx8`，用户 `tippy`，仓库 `/home/tippy/source/flakes`，音源环境 `/mnt/games/Audio/D-274`。记录覆盖 2026-11-19 至 2026-11-20 的搭建、实机测试和界面修复。

## 1. 最终保留的方案

用户在 2026-11-20 实际体验后确认延迟已经很低，要求停止调优并保留配置。最终保留 **192000 Hz / 1536 帧**，不采用实验中的 768 kHz、2048 帧默认值或无界面入口。

```text
电钢琴
  -> USB MIDI Interface
  -> PipeWire Midi-Bridge
  -> 原生 Carla 后端，单 JACK client
  -> yabridge -> Wine -> Vienna Synchron Pianos VST2
  -> Carla 的 VSL-D274:output_1 / output_2
  -> PipeWire JACK
  -> Topping E2x2 Pro Audio，AUX0 / AUX1
  -> 耳机
```

运行入口是 **VSL Concert D-274 - Low Latency Carla**。它打开真正的 VSL 插件编辑窗口，加载已有 Carla 工程及 `Animenz` 状态，连接实体 MIDI 和立体声输出。原有 **VSL Concert D-274** 仍启动 Windows 独立版 EXE，是另一条音频路径。

| 项目                      | 最终配置或实测状态                                              |
| ------------------------- | --------------------------------------------------------------- |
| 采样率                    | 192000 Hz；本机 E2x2 USB endpoint 列出的最高值                  |
| 启动器请求的 quantum      | 1536 帧                                                         |
| 单周期时间                | `1536 / 192000 = 8 ms`；不是琴键到耳机的总延迟                  |
| ALSA 播放格式             | `S32_LE`，6 通道；只连接前两路主混音                            |
| ALSA 播放 period / buffer | 本次读取为 1536 / 4608 帧；是观测值，不是启动器写死的硬件参数   |
| PipeWire profile          | `pro-audio`                                                     |
| Carla client / 插件名     | `D274-Carla` / `VSL-D274`                                       |
| 原工程                    | `/mnt/games/Audio/D-274/projects/d274-carla.carxp`              |
| 预设                      | 原有 `Animenz`；未通过减少话筒、复音、效果来降低负载            |
| 实时调度上限              | 仅启动器进程及子进程：`RTPRIO=25`                               |
| 锁页上限                  | 同上：67108864 bytes，即 64 MiB                                 |
| 窗口                      | `VSL-D274 (GUI)`，通过 Carla 的 `show_custom_ui()` 打开         |
| 没插声卡                  | 用当前桌面默认立体声输出及其原有 rate/quantum，仍可打开 VSL     |
| 插拔处理                  | 启动时检测；插入设备后需要关闭 VSL 再重开，不是热插拔自动重路由 |

**验收边界：** 用户已认可当前演奏手感。数字录音确认双声道采样合成正常，但较长压力测试仍观察到少量 Carla/声卡时钟节点错误，不能写成“任何负载下绝对零 xrun”。没有做物理琴键到耳机的端到端测量，也没有证明总延迟低于 10 ms。Windows 上“192 kHz、约 10 ms 多一点”是用户提供的参照，不是本机 Linux 的测量结果。

## 2. 为什么换这条链路

Windows 独立版 EXE 和 Windows VST 插件不能混为一谈。原桌面入口直接运行 `Vienna Synchron Pianos.exe`，没有经过 yabridge；独立版曾保存 DirectSound 输出设置。播放器显示的 256 帧只描述某一级缓冲，不代表后续 Wine 音频后端、桌面混音、USB 和 DAC 没有排队。

最终方案让原生 Carla 管理 JACK 音频连接，Windows DLL 仅承担音源计算。yabridge 把 DLL 暴露成 Linux VST2 `.so`；WineASIO 不是这条路径的必需组件，也没有作为最终方案部署。

延迟至少包括键盘扫描、MIDI 传输及等待、宿主处理周期、桥接调度、采样起音、设备队列和转换。提高采样率会缩短相同帧数对应的时间，但也增加处理量。这里选择 192 kHz 是因为它既是用户要求的目标，也是当前 USB descriptor 实际列出的上限；不是因为任意 DAC 都支持 768 kHz。

## 3. 固定版本和仓库外依赖

### 3.1 已使用的工具版本

| 组件                       | 本次使用的版本                                                 |
| -------------------------- | -------------------------------------------------------------- |
| Carla                      | 2.5.10                                                         |
| yabridge / yabridgectl     | 5.1.1                                                          |
| Wine runner                | `wine-9.21 (Staging)`，Nixpkgs 的 `wineWow64Packages.yabridge` |
| 工具环境内 PipeWire / JACK | 1.6.11                                                         |
| Python                     | 工具环境内 Python，含 PyQt5                                    |
| 本次系统内核               | 6.18.63；是环境记录，不是要求更换内核                          |

系统 PipeWire 服务与工具环境中的 JACK 客户端库是不同角色。不要以为仅重建 `carla-tools/result` 就升级或重启了系统音频服务。

### 3.2 必须保存的数据

```text
/mnt/games/Audio/D-274/
  carla-tools/
    tools.nix                 固定版本的工具环境定义
    result -> /nix/store/...   构建输出及 GC root，可按 tools.nix 重建
  prefix/                     完整的专用 Wine 前缀
  projects/
    d274-carla.carxp           实际演奏工程，含插件 chunk 状态
  xdg-config/
  xdg-data/
  xdg-cache/
  xdg-state/
  temp/
```

还必须保存实际采样库及 Wine 盘符/符号链接指向的外部目录。只备份上述目录里的链接，不会自动备份链接目标。

关键文件：

```text
prefix/drive_c/Program Files/Common Files/VST2/Vienna Synchron Pianos.dll
prefix/drive_c/Program Files/Common Files/VST2/Vienna Synchron Pianos.so
prefix/drive_c/users/tippy/Documents/VSL/Vienna Synchron Pianos/Presets/Animenz.vsynpreset
projects/d274-carla.carxp
```

Nix 负责 Linux 工具、启动器和桌面入口；**不会下载/安装商业音源、自动完成授权、生成 Animenz 音色或凭空恢复 Carla chunk**。优先保留整套可工作的私有环境。换机后的厂商授权可能需要重新激活，不能以复制前缀代替授权验证。不要把前缀、采样库、安装包、授权状态或录音提交到 Git/Nix store。

本次只读校验得到的 SHA-256，可用于识别是否仍是同一份已测试文件：

| 文件                        | SHA-256                                                            |
| --------------------------- | ------------------------------------------------------------------ |
| `carla-tools/tools.nix`     | `661262d1f7922aa65475cf28f9f4803fed68dd3f6631ec7b4702ef938d910ea2` |
| `projects/d274-carla.carxp` | `808962e7bc6ad6d6ea4f6c6811dbe13e5fcce30c8604c0da0cb3597187a07067` |
| `Animenz.vsynpreset`        | `d9d8d5c6915f66c3c3a26149722675c0dcf42e546db6f62b31731407f0e1e8ab` |

编辑并保存预设或工程后，哈希自然会改变；不要为了匹配旧哈希丢弃自己的新音色。

### 3.3 完整的 tools.nix

以下是工作环境中的实际定义。若 `carla-tools/tools.nix` 丢失，可在原位置重建此文件：

```nix
let
  source = builtins.fetchTree {
    type = "github";
    owner = "NixOS";
    repo = "nixpkgs";
    rev = "d5cc6833999746cffdfe0598f7bc801a57b887a9";
    narHash = "sha256-Wpz/7x/YWnDIBu7yj6ixe8j6fIMsidd9Y+o1PqPF3iM=";
  };
  pkgs = import source { system = "x86_64-linux"; };
in
pkgs.buildEnv {
  name = "d274-carla-tools";
  paths = [
    pkgs.carla
    pkgs.yabridge
    pkgs.yabridgectl
    pkgs.wineWow64Packages.yabridge
    pkgs.pipewire
    pkgs.pipewire.jack
    pkgs.alsa-utils
    pkgs.xdotool
    (pkgs.python3.withPackages (python: [ python.pyqt5 ]))
  ];
}
```

构建命令，不切换系统：

```bash
nix build --no-update-lock-file \
  --file /mnt/games/Audio/D-274/carla-tools/tools.nix \
  --out-link /mnt/games/Audio/D-274/carla-tools/result -L
```

这个定义单独固定了音频运行工具。仓库的 `flake.lock` 则固定桌面入口构建所用的 Nixpkgs/Home Manager 等输入。恢复时需要两者，不能更新整个 flake 后就认定运行环境完全相同。

## 4. 仓库代码逐层解读

### 4.0 现有 NixOS 音频基础

桌面共享模块 [`nixos/modules/desktop/noctalia.nix`](../nixos/modules/desktop/noctalia.nix) 已提供以下系统基础，不需要再建立一套同名 PipeWire 服务：

```nix
{
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    audio.enable = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };
}
```

本次对 `arx8` 的配置评估还确认 `alsa.enable=true`、`alsa.support32Bit=true`、`jack.enable=false`。最后这一项并不表示正式入口走不了 JACK：它显式使用工具环境的 `pw-jack` 和 PipeWire JACK 库，不依赖全系统 libjack 替换。不要把初版对话中“全局 JACK 开关已启用”的说法当成现行配置。

恢复到其他 NixOS 主机时先确认这层音频基础，按该主机已有共享模块合并，不要改每台主机的 `default.nix` 复制一套服务。系统音频尚未建立时，仅部署用户桌面入口不能补齐系统服务。

### 4.1 文件职责

| 文件                                                                                          | 职责                                                             |
| --------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| [`flake/wine-audio.nix`](../flake/wine-audio.nix)                                             | 独立 Home Manager 配置、六个音频桌面入口及专用安装 app/package   |
| [`launchers.nix`](../home-manager/modules/desktop/wine-audio/launchers.nix)                   | VSL/CFX 原独立版及 Wine 桌面入口，前缀目录和桌面准备             |
| [`low-latency.nix`](../home-manager/modules/desktop/wine-audio/low-latency.nix)               | 低延迟启动脚本、设备检测、临时实时限额、环境变量、精确连线       |
| [`scripts/d274-editor.py`](../home-manager/modules/desktop/wine-audio/scripts/d274-editor.py) | 原生 Carla API 宿主、加载工程、显示 VSL 窗口、Qt idle 和关闭处理 |
| [`tests/wine-audio-launchers-test.nix`](../tests/wine-audio-launchers-test.nix)               | 生成文件范围、入口数量、私有 profile 等断言                      |
| [`tests/wine-audio-desktop-entries-test.py`](../tests/wine-audio-desktop-entries-test.py)     | 用 GLib 解析 `.desktop`，验证 Exec 参数、名称、图标及工作目录    |
| [`flake/checks.nix`](../flake/checks.nix)                                                     | 注册 `checks.x86_64-linux.wine-audio-launchers-test`             |

**最终没有保留新的 NixOS 系统级低延迟模块。** 早期试写的 `services.pipewire.wineAudio`、全局 JACK drop-in 和 768 kHz 系统默认值均不是现行配置。不要再按旧对话寻找或添加这些选项。

### 4.2 选项与启用方法

独立配置导入 `launchers.nix`、`low-latency.nix`，并启用：

```nix
{
  programs.wineAudio = {
    enable = true;
    dataDirectory = "/mnt/games/Audio";
    lowLatency = {
      enable = true;
      sampleRate = 192000;
      quantum = 1536;
    };
  };
}
```

当前显式启用在 `flake/wine-audio.nix`；rate、quantum、dataDirectory 使用模块默认值。后续要显式配置，放到同一个独立 Home Manager 模块中。不要只改主机常规 HM 配置，却忘记实际桌面入口由这个独立配置安装。

`programs.wineAudio.package` 控制原独立版入口及前缀准备的 Wine；低延迟入口使用 `D-274/carla-tools/result` 内的固定 runner。只改该 package 选项，不会替换低延迟环境里的 Wine。

`dataDirectory` 可改变根目录，但并不自动迁移 `.carxp` 内的绝对插件路径、Wine 库路径和用户目录。MIDI/Card/Sink 名称、`D274-Carla`、`VSL-D274` 及主混音端口在脚本中是明确匹配的；换设备或改插件名时须一起调整。

### 4.3 low-latency.nix 启动流程

1. 检查原工程、Wine prefix、`yabridge-host.exe` 和含 PyQt5 的 Python 是否存在。
2. 用 `$XDG_RUNTIME_DIR/vsl-concert-d274.lock` 和 `flock` 防止重复启动同一音源。
3. 清除继承来的 `PIPEWIRE_RATE`、`PIPEWIRE_QUANTUM`、`PIPEWIRE_LATENCY`。
4. 发现 E2x2 时选择 `pro-audio`，请求 192 kHz / 1536 帧，并给本次进程树增加实时/锁页上限。
5. 没发现 E2x2 时使用桌面默认 `playback_FL/FR`，不强迫内置声卡承受 192 kHz，不强制要求 MIDI 已插入。
6. 建立临时 XDG config 目录，设置专用 Wine prefix 和固定工具 PATH，然后运行 `d274-editor.py`。
7. 等待日志中的 `D-274 project loaded`，有界等待约 30 秒；失败时退出并提示日志路径。
8. 用外部 `pw-link -w` 建立两路输出及可用的实体 MIDI 连线。
9. 窗口关闭或终端 Ctrl-C 时关闭宿主并清理临时 config，不删除工程、采样或预设。

主要环境变量：

| 变量                                                  | 用途                                                                                          |
| ----------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `WINEPREFIX`                                          | 指向 `D-274/prefix`，不使用默认 `~/.wine`                                                     |
| `XDG_CONFIG_HOME`                                     | 本次启动临时目录；不覆盖原 Carla 桌面偏好                                                     |
| `XDG_DATA_HOME` / `XDG_CACHE_HOME` / `XDG_STATE_HOME` | 指向 D-274 专用目录                                                                           |
| `TMPDIR`                                              | `D-274/temp`                                                                                  |
| `WINEDLLOVERRIDES=winemenubuilder.exe=d`              | 禁止 Wine 自行发布额外桌面快捷方式                                                            |
| `WINEDEBUG=-all`                                      | 关闭 Wine 常规调试输出；Carla/yabridge 自己的日志仍可能出现                                   |
| `QT_QPA_PLATFORM=xcb`                                 | 当前桌面通过 XWayland 打开 Qt/VSL 界面                                                        |
| `PATH` / `NIX_PROFILES`                               | 让桥接器找到固定 Wine、yabridge 和资源                                                        |
| `PIPEWIRE_RATE=1/192000`                              | 有 E2x2 时请求高采样率                                                                        |
| `PIPEWIRE_QUANTUM=1536/192000`                        | 有 E2x2 时请求对应图周期；可能影响同驱动上的其他应用                                          |
| `PIPEWIRE_LATENCY=1536/192000`                        | 客户端延迟请求，不是物理延迟保证                                                              |
| `CARLA_DONT_MANAGE_CONNECTIONS=1`                     | 由脚本管理外部连线，不恢复工程里的无关连接                                                    |
| `PIPEWIRE_PROPS`                                      | `jack.self-connect-mode = fail-external`、`jack.global-buffer-size = false`；保持当前已测行为 |

当前脚本没有主动清除 `PULSE_LATENCY_MSEC`；本链路不通过 Pulse 音频客户端输出，不用它来调钢琴 JACK 周期。

### 4.4 实时权限的范围

原用户会话曾测得 `RTPRIO=0`、`MEMLOCK=8 MiB`，yabridge 提示不能锁定共享缓冲。改成只在 E2x2 分支为启动器进程设置：

```text
sudo /nix/store/<util-linux>/bin/prlimit \
  --pid "$$" --rtprio=25 --memlock=67108864
```

上面是代码行为示意，实际脚本的 util-linux 路径由 Nix 生成，不要复制 `<util-linux>`。它提高的是资源上限，不是把整个 Python GUI 变成 FIFO 25。Carla/yabridge 自己为音频线程申请调度策略。

本次进程检查确认 VSL bridge 的 `audio` 线程使用 FIFO 25，许多 worker 为 FIFO 5，两个进程都继承 64 MiB 锁页上限。未更改全局 PAM 限额、内核实时配额或 sudoers，也没有要求把整个音源以 root 运行。

桌面入口保留 `Terminal=true`，以便 sudo 在需要时询问密码。若新登录后失败，先在终端 `sudo -v`，再重开入口；不要为此添加宽泛的 NOPASSWD 规则。

### 4.5 d274-editor.py 的作用和限制

Python 脚本使用已安装 Carla 的公开 `CarlaHostDLL`，不是重新实现音频引擎或修改上游源码。关键步骤：

```python
host.engine_init("JACK", "D274-Carla")
host.load_project(str(project))
host.show_custom_ui(0, True)
```

实际代码还设置单 client、禁用宿主传输与 OSC、关闭自动音频连线、指定 Carla 资源路径，检查工程恰好包含一个且有编辑器的插件，并用 30 ms Qt timer 调用 `engine_idle()`。

收到编辑器关闭回调后退出 Qt loop，最终 `engine_close()`。UI 打开失败也会退出并记日志。原 `carla --no-gui` 虽能发声，但不会弹出 VSL，已从正式入口移除。

**此脚本不自动保存工程。** 在窗口里改音色后直接关闭，下一次仍加载磁盘上的 `.carxp`。要长期保留更改，先在 VSL 保存用户预设，再用原生 Carla 前端更新工程的插件状态；备份原工程后再覆盖。不要把“窗口能调参数”误认为已经持久化。

## 5. 从备份恢复或新建环境

### 5.1 恢复顺序

1. 恢复仓库及其 `flake.lock`，包括第 4 节列出的新增/修改文件。只恢复旧分支而缺少 `d274-editor.py` 不够。
2. 挂载原采样盘到 `/mnt/games`，恢复完整 D-274 前缀、采样库、工程、用户预设和目录映射；保持用户可读写。
3. 用第 3.3 节重建 `carla-tools/result`。不要把旧机器上的裸 `/nix/store/...` 路径写进桌面入口。
4. 验证 Wine/bridge 版本及厂商授权；优先恢复已工作的 `.dll`、相邻 `.so` 和原工程。
5. 确保桌面已有工作的 PipeWire、WirePlumber 和 JACK 客户端支持。此部署器不会替代 NixOS 音频基础配置。
6. 构建并运行第 6 节的独立安装器，然后从新入口启动。

若完全从空环境安装，需要使用自己的合法 VSL/Synchron Pianos、D-274 采样库和授权安装流程。安装目标必须是这套专用前缀，含 **64 位 VST2**。仅安装独立版 EXE 或 VST3 不满足当前工程。

可在 Bash 中统一使用以下环境执行已有安装器或 Wine 配置工具：

```bash
root=/mnt/games/Audio/D-274
tools="$root/carla-tools/result"
export WINEPREFIX="$root/prefix"
export XDG_CONFIG_HOME="$root/xdg-config"
export XDG_DATA_HOME="$root/xdg-data"
export XDG_CACHE_HOME="$root/xdg-cache"
export XDG_STATE_HOME="$root/xdg-state"
export TMPDIR="$root/temp"
export PATH="$tools/bin:$PATH"
export NIX_PROFILES="${NIX_PROFILES:-} $tools"
export WINEDLLOVERRIDES=winemenubuilder.exe=d
export WINEDEBUG=-all
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME" "$TMPDIR"
wine --version
yabridgectl --version
```

在这个 shell 中运行厂商安装器，不能另开一个没有 `WINEPREFIX` 的 Wine 命令。安装和授权成功后再处理桥接。前缀安装器步骤取决于保存的厂商版本，本项目没有验证一套能替代厂商安装器的全自动全新安装脚本。

### 5.2 仅在桥接文件缺失时重建

当前工程引用与 DLL 同目录的 `.so`。yabridgectl 5.1.1 默认使用集中式 VST2 路径，直接 `sync` 未必恢复相同路径。确需重建时，在上面的专用环境中执行：

```bash
yabridgectl set --vst2-location inline
yabridgectl add "$WINEPREFIX/drive_c/Program Files/Common Files/VST2"
yabridgectl sync
test -f "$WINEPREFIX/drive_c/Program Files/Common Files/VST2/Vienna Synchron Pianos.so"
```

`inline` 是为兼容现有工程采用的布局，不是一般新项目的通用建议。本次验证了该版本 CLI 支持此配置；最初已有正确 `.so`，并未为了测试强制重新 sync。不要使用 `--prune` 清理不相关插件，也不要在默认用户环境里执行这组命令。

### 5.3 工程缺失时的重建

优先从备份恢复 `projects/d274-carla.carxp`，因为它保存的不只是插件路径，还有完整音色 chunk。若确已丢失，可在专用环境中用 `pw-jack carla` 打开原生 Carla 前端，按以下顺序重建：

1. 引擎选 JACK、single-client、Auto-Connect OFF；不要把 Carla 自己的 Windows bridge 和 yabridge 叠加使用。
2. 添加原生 Linux VST2 `.so`，即第 3 节的 `Vienna Synchron Pianos.so`，不是 `.dll` 或独立版 EXE。
3. 将插件实例命名为 `VSL-D274`，工程只保留这一个音源，启用插件并打开其自定义编辑器。
4. 在 VSL 中重新定位原 D-274 库、载入 `Animenz.vsynpreset`，核对麦克风、混音、效果、复音和主输出分配。
5. 保留插件 chunk 状态保存能力，将工程保存为指定的 `projects/d274-carla.carxp`，不要保存无关的外部音频/MIDI 连线。
6. 退出 Carla，再用正式低延迟入口重开，检查音色和端口名；“能发声”不等于恢复了完全相同的 Animenz 状态。

已有外部 `carla-tools/validate-plugin.py` 曾用于准备/保存工程，但不属于仓库必需代码，不能把它当成 Git 恢复必然带回的工具。

## 6. 构建与部署

以下命令在仓库根目录执行，使用 Bash 语法。先确认 `/mnt/games/Audio` 已挂载，并以真实的 `tippy` 用户、`HOME=/home/tippy` 执行。

```bash
nix build --no-update-lock-file --no-link \
  'path:/home/tippy/source/flakes#checks.x86_64-linux.wine-audio-launchers-test'

nix run --no-update-lock-file \
  'path:/home/tippy/source/flakes#wine-audio-launchers'
```

安装器激活一个独立 Home Manager generation。它管理 VSL/CFX 的四个原入口、低延迟入口以及 Bitwig 入口，共六个 `.desktop` 文件，并执行原有 Wine 桌面准备。它不是只发布一个文件，也不是整机 `nixos-rebuild switch`。

状态目录：

```text
/mnt/games/Audio/.launcher-state/
/mnt/games/Audio/.launcher-cache/
/mnt/games/Audio/.launcher-state/nix/profile
```

最终入口由 Home Manager 发布到用户应用目录；不要手工维护 `~/.local/share/applications/*.desktop`。安装器会拒绝不符合用户、HOME、目录所有权等条件的调用。前缀尚未建立时，原 `prepareWineAudioDesktop` 会初始化 64 位前缀并建立 Wine 内的 My Computer 快捷方式，但不会安装钢琴音源。

**为什么命令使用 `path:`：** 初期新增模块未纳入 Git 时，普通 Git-backed flake 看不到新文件，曾出现“选项不存在”的假象。显式路径 flake 会包含工作树源文件，便于验证未提交工作；这不需要 `--impure`。它仍会读取工作树，必须确认输入包含预期文件。本次没有为了让构建通过而 broad-stage 或提交其他工作。

本次最终只更新了独立音频入口。工作树包含其他系统改动，因此没有整机切换。早期曾进行完整系统构建，但那不是最终部署的必要步骤，也不能证明新设备、MIDI 或耳机输出验收通过。

## 7. 日常启动与参数核对

1. 先插 E2x2 和 MIDI 接口，再启动 **VSL Concert D-274 - Low Latency Carla**。
2. 如提示 sudo 密码，在终端输入；VSL 窗口打开后终端继续承担进程管理。
3. 正常退出用 VSL 窗口关闭按钮或终端 Ctrl-C。不要同时启动独立版 EXE，以免重复发声。
4. 如果先打开程序再插设备，关闭并重开；现行入口不监听设备变化。

只读检查：

```bash
wpctl status -n
pw-link -o
pw-link -i
pw-link -l
pw-top -b -n 3
pw-metadata -n settings
```

ALSA 工具不在常规 PATH 时使用：

```bash
/mnt/games/Audio/D-274/carla-tools/result/bin/aconnect -l
/mnt/games/Audio/D-274/carla-tools/result/bin/amidi -l
/mnt/games/Audio/D-274/carla-tools/result/bin/aplay -l
```

硬件事实以这些文件为准：

```bash
cat /proc/asound/cards
cat /proc/asound/E2x2/stream0
cat /proc/asound/E2x2/pcm0p/sub0/hw_params
cat /proc/asound/E2x2/pcm0p/sub0/status
```

预期连线：

```text
Midi-Bridge:USB MIDI Interface: MIDI 1 (capture)
  -> D274-Carla:VSL-D274:events-in
D274-Carla:VSL-D274:output_1
  -> alsa_output.usb-Topping_E2x2-00.pro-output-0:playback_AUX0
D274-Carla:VSL-D274:output_2
  -> alsa_output.usb-Topping_E2x2-00.pro-output-0:playback_AUX1
```

VSL 提供 22 路输出，不等于要把 22 路全接声卡。该工程主混音只接 1/2。使用 `pro-audio` 后端口叫 AUX，不再是 `analog-surround-21` 下的 FL/FR/LFE。

`pw-top` 中检查 E2x2 活动图与 VSL，而不是 Dummy-Driver 下一个没有实际输出的客户端。`pw-metadata` 的默认 `clock.rate=48000` 不一定等于活动 JACK 图的真实 rate；本次实际硬件和 `pw-top` 均能达到 192000。

错误计数是累计值。记录演奏前后差值，分开看插件加载、图重连和稳定演奏阶段；不要把启动时已有的几百次计数直接叫作“这一分钟掉了几百次音”，也不能忽略演奏中真正新增的计数。

系统输出音量在调试中曾为 0%，一度恢复到 5% 做保守试听；最终用户使用时读到 50%。**音量不是本方案固定参数，启动器不会强制覆盖用户音量。** 无声时先检查：

```bash
pactl get-default-sink
wpctl get-volume @DEFAULT_AUDIO_SINK@
```

按实际设备 ID 或稳定 sink 名调整音量，并结合 E2x2 耳机旋钮确认；不要为排错直接把所有增益拉满。

## 8. 调试过程与结论

| 阶段               | 尝试、观测与处理                                                                                      |
| ------------------ | ----------------------------------------------------------------------------------------------------- |
| 独立版路径         | 原入口运行 EXE，曾保存 DirectSound；其 buffer 数字不能代表 Wine 到设备的总队列                        |
| 48 kHz 准备        | 原 Carla 工程在 256/48000、未接真实设备时有零 xrun 空闲记录；明确不作为演奏验收                       |
| 768 kHz 草案       | 曾错误设为目标；接上硬件后发现 USB 只列到 192 kHz，草案撤回。不要复制旧对话的 768 kHz 默认值          |
| 环绕 profile       | E2x2 曾识别为 Analog Surround 2.1；改用 Pro Audio，并明确只接立体声主混音                             |
| 小缓冲             | 192 kHz 下测试 256、320、384、512 等档位，存在超时；并非硬件能设小帧数就代表 VSL 重负载稳定           |
| 周期不一致         | 有过宿主请求和硬件 period 不一致；后续同时读取 Carla/图/ALSA，不能只看环境变量                        |
| 实时调度           | 原 RTPRIO=0、锁页 8 MiB；针对进程树增加到 25/64 MiB 后，1024 帧同类压力测试的错误显著减少，但并未归零 |
| 临时 systemd scope | 尝试通过用户 scope 设置限额没有形成可用方案；不属于恢复步骤                                           |
| 1536 帧无界面阶段  | 原启动器约 90 秒重复 MIDI 测试可无新增播放/Carla 错误，录音双声道正常；不能外推无限时稳定             |
| 没有 VSL 窗口      | 根因是入口使用 `carla --no-gui`；改为原生 API 宿主显式 `show_custom_ui()`                             |
| 拔掉 E2x2          | 添加无硬件的桌面输出回退，已验证窗口能打开；插回后重开选择 E2x2                                       |
| 带界面复测         | 1536 帧首轮新增 1 次 Carla ERR，暖机后的另一轮没有新增；不据此宣称绝对零掉音                          |
| 临时改图周期       | 1280 帧驱动周期一轮新增 6 次 Carla ERR；1792 帧未新增 Carla ERR，但时钟输入节点有新增                 |
| 2048 对照          | 一次短测无新增，五遍重复 MIDI 的较长测试仍新增 2 次 Carla ERR；因此放弃把默认值改为 2048              |
| 最终选择           | 恢复并保留 192 kHz / 1536 帧，用户主观认可低延迟并明确要求停止调优                                    |

**对比实验的限制：** 后几次使用 `clock.force-quantum` 临时改的是 PipeWire 驱动周期。日志中能同时看到 E2x2 为 2048、Carla 节点仍显示其 1536 帧请求值；不能将它们写成“从启动开始所有层都原生采用 2048 帧”的严格对比。此前部分不同档位使用旧无界面 harness，也不是完全相同条件。最终方案不依赖这些临时强制值，结束后 `clock.force-rate`、`clock.force-quantum` 均为 0。

压力测试生成单音、每轮 8 音的密集音组和 CC64 踏板，共 12 个单音、40 轮音组，约 31 秒一遍。长测重复五遍，保持编辑窗口打开，并把 E2x2 的数字 monitor 录成 192 kHz 浮点双声道 WAV。记录的两个声道均有信号，没有据此证明实际耳机电平或所有微小音色细节完全相同。

未采用 WineASIO、ASIO4ALL、实验性调度器、源码补丁、减少话筒或复音的方案，也没有修改采样库。听感改善不能归功于没有部署过的设置。

## 9. 故障排查与复测技巧

### 9.1 `audioMasterAutomate while disabled`

原日志反复出现：

```text
[carla] Carla assertion failure: audioMasterAutomate while disabled,
condition "pData->enabled" in file CarlaPluginVST2.cpp, line 2021
```

在本次 Carla 2.5.10 代码路径中，这是插件向暂时 disabled 的宿主回报参数变化时的保护性检查，不等于进程必然崩溃。本次核对过的日志中有 645 条位于工程就绪前，就绪后为 0；之后能开窗口、接收 MIDI、输出声音。

不要仅凭这一行宣称音源损坏或删预设。正式入口将详细输出写到：

```text
$XDG_RUNTIME_DIR/vsl-concert-d274.log
```

这是当前登录会话的临时文件，不是长期测试报告。若错误持续发生在演奏期间，或同时无声/退出，应重新调查，不能笼统按无害日志处理。这里没有修改 Carla 源码或移除断言。

### 9.2 窗口没打开、退出或无声

| 现象                     | 优先检查                                                                                   |
| ------------------------ | ------------------------------------------------------------------------------------------ |
| 只有终端、没有 VSL       | 是否点了新入口；日志有无 `D-274 project loaded` 或 UI 错误；不能继续使用旧 `--no-gui` 路径 |
| 提示已在运行             | 检查现有 VSL/终端并正常关闭；`flock` 管理的是锁，不要先删除锁文件来绕开重复实例            |
| sudo 失败                | 在真实用户终端 `sudo -v` 后重开；不要把 Wine 进程改成 root                                 |
| 设备插入后还走内置声卡   | 入口只在启动时检测；关闭重开，再查 `pw-link -l`                                            |
| 有窗口无声音             | 检查预设/采样/授权、声卡音量和旋钮、两条主输出连线；数字 monitor 有声仍不等于耳机必然有声  |
| MIDI 不响应              | `aconnect -l`、`pw-link -o` 检查实际名称，确认不是只接到了 Midi Through 或 MIDI playback   |
| 端口名称变化             | 同步改启动脚本的 midi/card/sink/client/插件名，不依赖易变的数值 ID                         |
| 只在 Dummy-Driver 下运行 | 尚未连接真实输出，空闲负载和零错误不代表演奏可用                                           |
| 图突然变慢/周期变大      | 分别读环境请求、`pw-top` 和 `hw_params`，检查是否遗留全局 force 或其他音频程序             |
| 新开之后音色回去了       | 编辑器不自动保存 `.carxp`；检查保存的用户预设和工程 chunk                                  |

查看物理 MIDI 是否确有琴键/踏板事件，可用工具环境里的 `aseqdump -p <client>:<port>`。只看见设备名称表示接口枚举成功，不代表电钢琴已发送 Note On/Off、力度或 CC64；本次自动压力测试的虚拟 MIDI 也不能替代这项物理检查。

### 9.3 复测方法

日常演奏已被用户接受，不需要每次启动做压力测试。迁移机器、换 Wine/Carla、更新播放器或改变采样率/缓冲后再复测：

1. 先保存并备份原 `.carxp` 和预设，只启动一个 D-274 实例，保持原混音、效果、复音。
2. 打开 VSL 窗口并保持可见，确认声卡 192 kHz/1536、实际 MIDI 和双声道连线。
3. 插件加载、录音客户端接入、图重连后留出稳定时间，再记错误基线。
4. 用同一段 MIDI 文件演奏相同音符、力度、CC64；同时实际弹奏踏板、和弦、快重复音检查手感。
5. 如需留证，用 `pw-record --target 0 --rate 192000 --channels 2 --format f32` 创建录音节点，通过 `pw-link` 只连接 E2x2 的 `monitor_AUX0/1`，不要误录麦克风。
6. 前后记录 `pw-top`、`hw_params`、`status`；以新增 ERR 评估，保留时间长度、窗口开关和实际周期，不能只写“0 xrun”。
7. 结束临时 MIDI/录音客户端，保持实体 MIDI 与 VSL 主输出连接；如做过全局强制，恢复实验前的 metadata。

若实验前 force 均为 0，清理命令是：

```bash
pw-metadata -n settings 0 clock.force-rate 0
pw-metadata -n settings 0 clock.force-quantum 0
```

如果原来有自定义 force，应恢复原值而不是一律清零。正式启动器不依赖上面两条命令，不需要每次启动全局强制。

若有 `ffmpeg`，浮点 WAV 的电平统计可用：

```bash
ffmpeg -hide_banner -i /path/to/private-test.wav \
  -af astats -c:a pcm_f32le -f null -
```

峰值/RMS 证明录到了信号；不能单独证明没有爆音、没有丢音或端到端延迟。此前脚本中 null 输出显示的默认 `pcm_s16le` 不代表输入录音不是浮点格式，要分别查看输入与输出描述。

先前的自动 harness 和录音位于 `/tmp/kilo/d274-*`，是临时材料，不是永久恢复依赖，不要把它们当作下次一定存在的配置。持久可复现的核心是仓库脚本、固定工具定义、原工程/预设和同条件验收方法。

### 9.4 无需保存旧临时脚本的 MIDI 测试素材

以下标准库脚本可重新生成与本次同类的测试事件，不依赖 `/tmp/kilo` 中的旧程序。它只写合成 MIDI，不读取授权、采样或用户演奏。示例重复三遍，预留四秒连线时间；生成文件不需要加入 Git。

```bash
/mnt/games/Audio/D-274/carla-tools/result/bin/python - <<'PY'
import struct
from pathlib import Path

def vlq(value):
    data = [value & 127]
    while value >> 7:
        value >>= 7
        data.insert(0, 128 | (value & 127))
    return bytes(data)

events = []
for i in range(12):
    t = 960 + 480 * i
    events.extend([(t, bytes([144, 60 + i, 65])),
                   (t + 320, bytes([128, 60 + i, 0]))])
for i in range(40):
    t = 480 * (17 + i)
    events.extend([(t, bytes([176, 64, 127])),
                   (t + 440, bytes([176, 64, 0]))])
    for j in range(8):
        note = 36 + ((i * 7 + j * 5) % 60)
        events.extend([(t + j * 20, bytes([144, note, 75 + j])),
                       (t + 200 + j * 20, bytes([128, note, 0]))])
repeats, lead = 3, 4 * 960
sequence = [(0, b'\xff\x51\x03\x07\xa1\x20')]
sequence += [(t + 480 * 62 * n + lead, msg)
             for n in range(repeats) for t, msg in events]
sequence.append((480 * 62 * repeats + lead, b'\xff\x2f\x00'))
track, last = bytearray(), 0
for t, msg in sorted(sequence, key=lambda event: event[0]):
    track += vlq(t - last) + msg
    last = t
data = (b'MThd' + struct.pack('>IHHH', 6, 0, 1, 480)
        + b'MTrk' + struct.pack('>I', len(track)) + track)
path = Path('/tmp/d274-repro.mid')
path.write_bytes(data)
print(path)
PY
```

在一个终端运行下列命令，另一个终端用 `pw-link -o` 找到 `d274-check-midi:` 开头的实际端口，并将它连到 `D274-Carla:VSL-D274:events-in`。这只是在原宿主上增加测试 MIDI，不应另开一个 VSL 实例：

```bash
pw-midiplay --target 0 -P '{ node.name = d274-check-midi }' /tmp/d274-repro.mid
```

生成器提供四秒准备时间；手工接线超过时间时重跑播放命令，别把漏掉开头音符误判为音源丢音。复测仍需按 9.3 节另外记录真实设备、窗口、ERR 增量和录音，不能仅以这条命令正常结束作为通过标准。

## 10. 备份与完成标准

迁移前关闭音源，在私有存储中保存：仓库当前更改和 `flake.lock`、第 3 节外部环境、所有采样目标目录及盘符映射、工程和用户预设、厂商安装版本与合法授权恢复信息。可排除 cache/temp，但不要把 `prefix`、`xdg-data` 或 `projects` 当缓存删除。避免备份/发布密码、令牌到本仓库。

`carla-tools/result` 指向的 store 闭包可由固定定义重建；有离线恢复要求时，还需私下保留相应 Nix 闭包/缓存及其引用，不能只保存一个失效链接。桌面入口由 Nix 重建，不必手工复制生成后的 store 绝对路径。

完整恢复至少满足：

- 桌面入口由独立 Home Manager 安装，GLib/入口回归测试通过。
- 工具版本固定，原 DLL、bridge、采样库、授权和用户预设可用。
- 插入 E2x2/MIDI 后重开能显示 `VSL-D274 (GUI)`，保留 Animenz 工程状态。
- 实际活动设备为 E2x2，rate 为 192000，生产请求为 1536，主混音连接 AUX0/1。
- 真实琴键、力度和踏板可用，输出不是静音，用户演奏手感符合预期。
- 记录过同条件演奏与错误增量，清楚区分构建成功、数字发声、主观验收和物理延迟测量。

本记录的最终状态是保留已被用户接受的演奏配置，停止继续压低缓冲；没有把短测成功升级成“绝对无卡顿”承诺。
