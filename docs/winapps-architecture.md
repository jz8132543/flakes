# WinApps 无缝 Windows 子系统与 Office 集成技术文档

本指南详细记录了在 NixOS 环境下基于 **Rootless Podman + dockur/windows (Tiny10) + WinApps** 实现轻量、高集成度、开箱即用的 Windows 无缝应用及 Office 文档关联体系的总体架构、核心特性、实现细节与排障记录。

---

## 一、 总体架构

本方案打破了传统虚拟机“笨重窗口、全天高 CPU 占用”的劣势，构建了从底层容器虚拟化到桌面环境深度集成的多层协同架构：

```
+-----------------------------------------------------------------------------------+
|                        Linux 桌面环境 (GNOME / Wayland / Nautilus)                 |
|   - 双击 *.docx / *.xlsx / *.pptx 等 Office 文件                                   |
|   - 点击应用启动器图标 (Microsoft Word / Excel / PowerPoint / Windows Subsystem)  |
+------------------------------------------+----------------------------------------+
                                           | xdg-open / xdg-mime
                                           v
+-----------------------------------------------------------------------------------+
|                   Home-Manager 桌面层 (winapps.nix)                                |
|   - 协议处理 & MIME 绑定: winapps-word.desktop 等                                  |
|   - WinApps 官方客户端: ~/.config/winapps/winapps.conf (官方原生参数)              |
|   - 自动缩放算法: 读取 wayland.dpi，计算矢量级 RDP_SCALE 与 /scale-desktop         |
|   - 闲置自动挂起 (AUTOPAUSE): 窗口关闭 300s 后自动触发 podman-compose pause        |
+------------------------------------------+----------------------------------------+
                                           | FreeRDP / RDP 虚拟通道 (端口: 127.0.0.1:3390)
                                           v
+-----------------------------------------------------------------------------------+
|                   NixOS 系统服务层 (podman-windows.nix & oem.nix)                  |
|   - winapps-windows.service: 由 podman-compose 按声明式 compose.yaml 管理容器      |
|   - winapps-boot-suspend.service: 开机完成启动后自动 pause 冻结 Windows (0% CPU)  |
|   - /etc/winapps/oem/install.bat: 无人值守环境配置、安全信任、MAS 静默激活流水线   |
+------------------------------------------+----------------------------------------+
                                           | slirp4netns 用户态协议栈 + KVM 硬件虚拟化
                                           v
+-----------------------------------------------------------------------------------+
|                   Rootless Podman 容器 (dockur/windows:latest)                    |
|   - 系统镜像: Tiny10 (x64 23H2，极简轻量版，内存占用 < 1GB)                       |
|   - 存储路径: /home/tippy/Storage/WinApps (虚拟磁盘 data.img)                     |
|   - 共享目录: /home/tippy/Storage/WinAppsShare -> \\tsclient\WinAppsShare        |
|   - Web VNC: http://127.0.0.1:8006 (安装进度监控与桌面直视)                        |
+-----------------------------------------------------------------------------------+
```

---

## 二、 核心功能特性

### 1. 极致低资源开销与 0% CPU 闲置

- **Tiny10 极简基底**：选用去除了大量后台遥测与无用组件的 Tiny10 镜像，相比官方原版 Windows 10/11 节省超过 60% 的磁盘和内存占用，非常适合轻薄本或配置较弱的设备。
- **开机即冻结（Boot Suspend）**：开机后台启动并检测到 Windows 就绪后，自动执行 `pause` 冻结虚拟机，CPU 占用直接归零。
- **秒级唤醒恢复（Sub-second Resume）**：利用 Linux cgroup v2 freezer 内存保全特性，双击文件时只需约 1 秒即可 unpause 恢复运行。
- **官方空闲挂起（AUTOPAUSE）**：遵循 WinApps 上游机制，当所有 Office 窗口关闭满 300 秒后，自动再次挂起。

### 2. 深度原生级桌面与文档关联

- **双击直接打开**：`.docx`、`.doc`、`.xlsx`、`.xls`、`.pptx`、`.ppt` 等格式默认通过 `winapps-word.desktop` 等拉起。
- **路径实时双向映射**：通过 FreeRDP 驱动重定向，Linux 主目录自动挂载为 `\\tsclient\home`，全盘根目录为 `\\tsclient\root`。
- **免除受保护的视图警告**：通过 OEM 脚本将 `tsclient` 加入 Windows 本地 Intranet 区域，并在注册表中配置 Office 受信任位置，彻底告别黄色只读安全警告。

### 3. 高分屏（HiDPI）矢量级无损渲染

- 结合 NixOS `config.wayland.dpi`（如 144 DPI / 150% 缩放），动态计算 `RDP_SCALE="140"` 与 `/scale-desktop:150`。
- 配合 `+glyph-cache`（字体字形缓存），字体与控件边缘如 Linux 原生应用一般清晰锐利，无位图拉伸模糊。

### 4. 硬件加速与外设穿透

- **图形与网络优化**：启用 `/network:lan` 禁用 RDP 拥塞延迟，开启 `/gdi:hw` 客户端硬件加速与 `/gfx:RFX` RemoteFX 渐进式渲染。
- **物理打印机无缝穿透**：通过 `/printer` 参数，将 Linux 宿主机的 CUPS 打印机直接映射为 Windows 打印机，在 Office 中直接 `Ctrl + P` 即可打印，无需在虚拟机内重新寻找驱动。
- **双向剪贴板与音频**：`+clipboard`、`/sound`、`/microphone` 全双工直通，文字、富文本和图片自由复制粘贴。

### 5. 全自动静默激活体系（MAS 集成）

- 注入微软开源社区最高可靠性的 **MAS (Microsoft Activation Scripts)**。
- 采用非交互式模式：`/HWID` 实现 Windows 永久数字权利激活（绑定虚拟主板指纹）；`/Ohook` 实现 Office 永久注入激活，免去自建 KMS 的定期续期困扰。

---

## 三、 文件结构与模块职责划分

```text
flakes/
├── docs/
│   ├── winapps-architecture.md         # 本技术文档与实战排障手册
│   └── README.md                       # 文档索引
├── home-manager/modules/desktop/
│   └── winapps.nix                     # 用户桌面集成：MIME 关联、.desktop 文件、winapps.conf
└── nixos/modules/desktop/winapps/
    ├── default.nix                     # 声明式 Options 统一入口（零配置默认值）
    ├── packages.nix                    # 软件包组装：WinApps 补全 PATH 与 SVG 图标提取
    ├── podman-windows.nix              # 容器生命周期：compose 生成、systemd 服务、休眠控制
    ├── oem.nix                         # Windows 客户机自动化流水线：注册表、信任路径、MAS 激活
    ├── libvirt.nix                     # 备用后端：原生 Libvirt/KVM 支持
    ├── docker-windows.nix              # 备用后端：原生 oci-containers 支持
    └── vm-definition.nix               # 备用后端：物理双系统磁盘直通检测
```

### 1. `nixos/modules/desktop/winapps/default.nix`

定义了系统级全局配置选项，并赋予了开箱即用的默认值：

- `desktop.winapps.podman.enable`：默认 `true`（零机器手动配置）。
- `version`：默认 `"tiny10"`。
- `language`：默认 `"English"`（针对 Tiny10 特性优化）。
- `port`：默认 `3390`（避开 Linux 本机 `xrdp` 默认占用的 3389 端口）。
- `username` / `password`：默认 `"Docker"` / `"admin"`（对齐 dockur 官方规范）。
- `storagePath` / `sharedPath`：默认存储于 `~/Storage/WinApps` 与 `~/Storage/WinAppsShare`。

### 2. `nixos/modules/desktop/winapps/podman-windows.nix`

- **生成 `/etc/winapps/compose.yaml`**：将 NixOS 选项渲染为符合 WinApps 官方规范的 compose 配置文件。
- **封装 `podmanCompose` wrapper**：由于 nixpkgs 的 `podman-compose` 没有把 `podman` 和 `slirp4netns` 打入自身 PATH，此处注入 `${lib.makeBinPath [ pkgs.podman pkgs.slirp4netns ]}:/run/wrappers/bin`。
- **`winapps-windows.service`**：开机自动执行 `podman-compose up -d`，关机执行 `down`。
- **`winapps-boot-suspend.service`**：智能检测首次安装标志，避免提前挂起；通过真实 RDP X.224 握手确认系统完全就绪后执行 pause。

### 3. `nixos/modules/desktop/winapps/oem.nix`

在宿主机生成 `/etc/winapps/oem/install.bat`，并在 Windows 首次进入桌面时自动执行：

1. 导入 WinApps 官方的 `RDPApps.reg` 与 `Container.reg`；
2. 开放 Windows 防火墙中的远程桌面规则；
3. 禁用无用的 Windows Update 与遥测服务，降低 CPU 消耗；
4. 将 `\\tsclient` 域名加入 Local Intranet (Zone 1)，将 `\\tsclient\home` 等加入 Office 受信任位置；
5. 注册开机时间校准任务 `TimeSync.ps1`；
6. 自动检测共享目录中是否存在 `OfficeSetup.exe`，若有则自动静默安装；
7. 通过 PowerShell 非交互式运行 MAS，执行 `/HWID /Ohook` 激活。

### 4. `home-manager/modules/desktop/winapps.nix`

- **`~/.config/winapps/winapps.conf`**：完全采用 WinApps 上游官方支持的参数，声明 `WAFLAVOR="podman"`、`AUTOPAUSE="on"`、动态缩放及优化标志。
- **软链 compose 文件**：将 `~/.config/winapps/compose.yaml` 链接到 NixOS 模块生成的同一 store 文件，使客户端的暂停/唤醒能够精准控制由 systemd 启动的同一个容器。
- **MIME 与 Desktop 文件**：完整覆盖 Word、Excel、PowerPoint 的各类新旧 MIME 类型（包括 `.docx`、`.doc`、`.dotx`、`.rtf`、`.xlsx`、`.xls`、`.pptx` 等）。

---

## 四、 核心问题排查与技术解决方案记录

在从零实现与调优的过程中，遭遇并彻底攻克了以下几个深层次技术陷阱：

### 1. Rootless Podman 启动失败（退出码 125）与 DN42 路由冲突

- **现象**：容器启动时无限死循环报错 `Argument list too long` 并退出。
- **原因分析**：本机启用了 DN42 全互联网络，宿主机路由表中有 8000+ 条路由。Podman 5 默认的 `pasta` 网络后端在初始化容器网络命名空间时，试图将宿主机所有的路由逐条复制进容器，导致 Linux Netlink 缓冲区溢出。
- **解决方案**：在 `compose.yaml` 中将网络模式强制设为 `network_mode: "slirp4netns"`，并在 wrapper 和系统包中包含 `pkgs.slirp4netns`。`slirp4netns` 使用完全独立的用户态协议栈，只维护一条默认网关，彻底免疫宿主机路由膨胀。

### 2. Tiny10 镜像下载中断卡死（Download aborted）

- **现象**：容器启动后日志显示 `Downloading Tiny 10 from archive.org...` 然后报 `Download aborted`，虚拟磁盘始终为 0 字节。
- **原因分析**：原配置设置了 `language = "Chinese"`。Tiny10 属于开源社区制作的精简系统，在 archive.org 仅存有英文原版镜像。`dockur` 内部的 `fallbackEnglish` 脚本在语言回退拼接文件名时产生了逻辑缺陷，向服务器请求了一个不存在的 `tiny10_zh.iso`，导致 404 终止。
- **解决方案**：在 `default.nix` 中将 Tiny10 的默认语言显式指定为 `language = "English"`。修正后，下载流立即稳定建立，下载速度达到 20MB/s+。

### 3. 开机被错误提前冻结导致安装中断（假就绪问题）

- **现象**：服务拉起 20 秒后容器即被 pause 挂起，导致网页 VNC 打不开，下载和安装停滞。
- **原因分析**：原脚本使用 `nc -z 127.0.0.1 3390` 探测端口。但 Podman 的宿主机端口转发进程 `rootlessport` 在容器一启动就会立即在宿主机监听并应答 TCP 握手（即使容器内虚拟机根本还没启动）。脚本误以为 Windows 已经开机完毕，导致把正在安装系统的 Windows 给强制挂起了。
- **解决方案**：
  1. **安装标记防护**：检测 `/home/tippy/Storage/WinApps/windows.boot` 标记，若未生成，表明正在初次安装，直接跳过挂起，确保安装流程顺畅走完。
  2. **RDP 协议层探针**：摒弃单纯的 TCP 握手，改用 Bash 发送真实的 **RDP X.224 协议握手报文**，仅在容器内部的 Windows RDP 协议栈真正回复时才判定就绪。

### 4. xdg-mime 默认关联回退到 WPS 的问题

- **现象**：配置了 `mimeapps.list`，但终端中 `xdg-mime query default application/msword` 依然输出 `wps-office-wps.desktop`。
- **原因分析**：`xdg-mime` 在解析默认应用时会检查 `.desktop` 中声明的 `Exec=winapps word %F` 是否存在于系统的 `$PATH` 中。之前 `winapps` 二进制包未被加入用户的环境路径，导致系统检测到命令不可用，自动降级回退到列表中下一个可用的 WPS。
- **解决方案**：在 `packages.nix` 中将 `winappsPatched`（带图标和 podman-compose 依赖）加入 `environment.systemPackages`，使其全局进入系统的 `$PATH`。

### 5. xrdp 端口冲突导致连接到 Linux 桌面

- **现象**：在终端运行 `winapps windows` 后，弹出的不是 Windows 桌面，而是 Linux 本机的 xrdp 登录框。
- **原因分析**：GNOME 桌面启用了系统自带的 `services.xrdp`，占用了本机的默认端口 `3389`。WinApps 默认去连 `127.0.0.1:3389` 时连上了 Linux 自身。
- **解决方案**：将 Windows 容器映射端口与 `winapps.conf` 中的连接端口统一调整为 **`3390`**，彻底规避冲突。

---

## 五、 日常运维与使用指南

### 1. 编译部署

在仓库根目录直接执行：

```bash
nh os switch
```

### 2. 状态检查与日志查看

```bash
# 查看容器运行状态 (Up / Paused)
podman ps -a

# 查看容器运行详细输出与进度
podman logs WinApps -f

# 查看开机挂起服务的执行状态
systemctl status winapps-boot-suspend.service
```

### 3. 打开完整 Windows 桌面会话

- **方式一（Web 端免客户端）**：打开浏览器访问 `http://127.0.0.1:8006`。
- **方式二（RDP 高性能客户端）**：在终端运行 `winapps windows`，或在桌面启动器点击 **Windows Subsystem**。

### 4. 安装 Office

1. 启动 Windows 后，打开内置的 Edge 浏览器直接下载安装；
2. 或者在 Linux 端将 Office 安装包放到 `~/Storage/WinAppsShare/OfficeSetup.exe`，系统会在 Windows 初始化时自动调用静默安装参数。
3. 安装完毕后，在 Linux 文件管理器中直接双击任意 `.docx` / `.xlsx` / `.pptx` 即可秒开。
