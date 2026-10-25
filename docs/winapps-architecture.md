# WinApps 无缝 Windows 子系统与 Office 集成技术文档

本指南详细记录了在 NixOS 环境下基于 **Rootless Podman + dockur/windows (Tiny10/Windows 11) + WinApps** 实现轻量、高集成度、开箱即用的 Windows 无缝应用及 Office 文档关联体系的总体架构、核心特性、实现细节与排障记录。

---

## 一、 总体架构

本方案打破了传统虚拟机“笨重窗口、全天高 CPU 占用”的劣势，构建了从底层容器虚拟化到桌面环境深度集成的多层协同架构：

```
+-----------------------------------------------------------------------------------+
|                        Linux 桌面环境 (GNOME / Wayland / Nautilus)                 |
|   - 双击 *.docx / *.xlsx / *.pptx 等 Office 文件                                   |
|   - 点击应用启动器图标 (Microsoft Word / Excel / PowerPoint / Windows Subsystem)  |
|   - 点击 "WinApps: Scan Applications" 一键识别新安装的 Windows 软件 (如豆包)       |
+------------------------------------------+----------------------------------------+
                                           | xdg-open / xdg-mime / 命令调用
                                           v
+-----------------------------------------------------------------------------------+
|                   Home-Manager 桌面层 (home-manager/.../winapps.nix)               |
|   - 协议处理 & MIME 绑定: word-o365.desktop 等官方应用入口                          |
|   - WinApps 官方客户端: ~/.config/winapps/winapps.conf (官方原生参数)              |
|   - 闲置自动挂起 (AUTOPAUSE): 窗口关闭 300s 后自动触发 podman-compose pause        |
|   - 调用自动唤醒 (Auto Resume): 客户端检测到 paused 状态自动 unpause 秒级恢复      |
|   - 按需应用识别工具: winapps-scan 脚本与桌面扫描入口                              |
+------------------------------------------+----------------------------------------+
                                           | FreeRDP 3 / RDP 虚拟通道 (端口: 127.0.0.1:3390)
                                           v
+-----------------------------------------------------------------------------------+
|              NixOS 系统服务层 (nixos/modules/desktop/winapps/)                     |
|   - options.nix: programs.winapps 原生声明式配置 (通过 Haumea 自动全量加载)       |
|   - podman-windows.service: 由 podman-compose 按声明式 compose.yaml 管理容器      |
|   - winapps-boot-suspend.service: 开机单发挂起服务 (部署完成后按需冻结，无定时器)  |
|   - oem.nix: 微软官方 ODT 静默部署、目录联接兼容、slmgr/ospp 官方授权流水线        |
|   - packages.nix: 上游包注入 HKCU/开始菜单快捷方式识别补丁 (支持豆包等 AppData 应用)|
+------------------------------------------+----------------------------------------+
                                           | slirp4netns 用户态协议栈 + KVM 硬件虚拟化
                                           v
+-----------------------------------------------------------------------------------+
|                   Rootless Podman 容器 (dockur/windows:latest)                    |
|   - 系统镜像: Tiny10 / Windows 11 (内存占用 < 1GB)                                 |
|   - 持久化磁盘: /persist/home/tippy/Storage/WinApps (虚拟磁盘 data.img)           |
|   - 共享目录: /persist/home/tippy/Storage/WinAppsShare -> \\host.lan\Data        |
|   - Web VNC: http://127.0.0.1:8006 (安装进度监控与备用桌面直视)                    |
+-----------------------------------------------------------------------------------+
```

---

## 二、 核心功能机制解答

### 1. 自动挂起（Suspend）与自动唤醒（Wakeup）闭环机制

用户的完整使用周期（开机 → 闲置冻结 → 双击唤醒 → 退出休眠）由两套分工明确的机制协同保障：

```
                    开机启动
                       │
                       ▼
       ┌───────────────────────────────┐
       │     Windows 容器启动就绪       │
       └───────────────┬───────────────┘
                       │
          autoSuspend = true? (开机单发挂起)
                       │
          ┌────────────┴────────────┐
          ▼ 是                      ▼ 否 (默认)
┌──────────────────┐      ┌──────────────────┐
│ winapps-boot-    │      │  容器保持 running │
│ suspend 延迟后   │      │  待机状态         │
│ 执行 pause (0%CPU)│      └─────────┬────────┘
└─────────┬────────┘                │
          │                         │
          └────────────┬────────────┘
                       │
                       ▼
            用户双击 docx 或启动软件
                       │
                       ▼
         winapps 检测容器状态是否为 paused?
                       │
          ┌────────────┴────────────┐
          ▼ 是                      ▼ 否
┌──────────────────┐      ┌──────────────────┐
│ podman-compose   │      │ 直接建立 RDP 连入│
│ unpause 自动唤醒 │      └─────────┬────────┘
└─────────┬────────┘                │
          │                         │
          └────────────┬────────────┘
                       │
                       ▼
             弹出 Office 窗口正常使用
                       │
                       ▼
             所有 Office 窗口全部关闭
                       │
                       ▼
        WinApps 官方 AUTOPAUSE 倒计时 (默认 300 秒)
                       │
                       ▼
         执行 podman-compose pause 深度挂起 (0% CPU)
```

#### 各配置项的影响说明：

- **`programs.winapps.podman.autoSuspend`**：
  - **设为 `false`（推荐默认值）**：开机后容器先在后台待机。只有当你**首次**打开并关闭 Office 满 300 秒后，WinApps 官方客户端才会将其挂起。开机期间不会有任何系统级服务干涉容器。
  - **设为 `true`**：系统开机并在 Windows 引导就绪 `autoSuspendDelay` 秒（默认 300 秒）后，由 `winapps-boot-suspend.service` 自动执行**一次性单发 `pause`**，覆盖开机后从未打开过任何文件的空窗期。**该服务已被完全重写为单发 oneshot 服务，删除了所有后台循环定时器与 RDP 探测，绝对不会发生反复抢占桌面的问题**。
- **`programs.winapps.autopause`**：
  - 默认启用（`enable = true; timeout = 300;`），由 WinApps 官方客户端在关闭所有 RDP 窗口后负责自动挂起与下次调用时自动唤醒。

---

### 2. 打开完整 Windows 桌面的方式对比

| 方式                         | 入口                                                                 | 技术原理                                            | 特性与体验                                                                                                                                                           |
| :--------------------------- | :------------------------------------------------------------------- | :-------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **方式一（原生极速，推荐）** | 应用菜单点击 **"Windows Subsystem"**<br>或终端运行 `winapps windows` | 原生 FreeRDP 3 连接本地 3390 端口                   | - **支持自动唤醒**：虚拟机处于 paused 状态时自动 unpause。<br>- 60fps 硬件加速渲染，支持 HiDPI。<br>- 剪贴板、打印机、声卡双向完全直通。<br>- 支持全屏或无缝窗口化。 |
| **方式二（系统托盘）**       | 桌面右上角系统托盘点击 **WinApps 图标** -> 选择 **"Windows"**        | WinApps Launcher (`yad`) 菜单触发 `winapps windows` | - 随时在托盘掌控虚拟机状态（ON / PAUSED / OFF）。<br>- 支持托盘一键 Resume、Pause、Power Off。                                                                       |
| **方式三（Web 免客户端）**   | 浏览器访问 `http://127.0.0.1:8006`                                   | dockur 容器内置 noVNC Web 服务                      | - 仅作为备用维护通道（如查看初次安装过程或调试引导）。<br>- **注意**：容器处于 paused 时网页会断开，需先通过 `winapps` 唤醒。                                        |

---

### 3. 用户自装软件（如豆包）的识别与启动

1. **进入 Windows 安装软件**：
   通过应用菜单中的 **"Windows Subsystem"**（或执行 `winapps windows`）进入 Windows 桌面，使用内置 Edge 浏览器下载并安装**豆包**（或其他软件）。
2. **一键生成 Linux 入口**：
   在 Linux 应用菜单中点击 **`WinApps: Scan Applications`**（或在终端运行 `winapps-scan`）。
3. **识别原理**：
   - 传统 WinApps 只扫描 `HKLM`（系统全局安装）。本项目通过 `packages.nix` 为底层扫描脚本注入了对 `HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths` 与当前用户/全局开始菜单快捷方式（`*.lnk`）的提取补丁。
   - 豆包默认安装在用户 `AppData` 目录，扫描程序会自动解析其主程序路径与图标，并在 Linux 端自动生成 `~/.local/share/applications/` 桌面图标及 `~/.local/bin/doubao` 命令行包装器。
4. **像打开 Office 一样无缝使用**：
   扫描完成后，直接在 Linux 应用程序抽屉中搜索“豆包”或“Doubao”点击即可弹出窗口；打开时同样支持自动唤醒虚拟机，关闭后同样自动进入 300 秒闲置休眠。

---

## 三、 文件结构与模块职责划分

项目完全遵循 Haumea 自动扁平加载规范（**不使用 `default.nix`**，避免子目录模块被拦截隔离）：

```text
flakes/
├── docs/
│   ├── winapps-architecture.md         # 本技术文档与实战排障手册
│   └── README.md                       # 文档总索引
├── home-manager/modules/desktop/
│   ├── apps.nix                        # 全局 MIME 文档关联定义（.docx/.xlsx/.pptx 等统一指向官方 desktop）
│   └── winapps.nix                     # 用户桌面集成：声明式 winapps.conf、应用元数据存储、winapps-scan
└── nixos/modules/desktop/winapps/
    ├── options.nix                     # programs.winapps 原生 Options 声明与全局默认值（取代旧 default.nix）
    ├── shortcuts.nix                   # 声明式 Windows 应用快捷方式模块（自动生成 Desktop Entry 与 CLI 包装）
    ├── podman-windows.nix              # 容器生命周期：compose 生成、systemd 单发开机挂起服务
    ├── oem.nix                         # 微软官方 ODT 静默部署、Office16 目录联接与合法授权维护
    ├── packages.nix                    # WinApps 源码补丁封装：注入豆包/HKCU 识别、补全系统 PATH
    ├── libvirt.nix                     # 备用后端：原生 Libvirt/KVM 支持
    ├── docker-windows.nix              # 备用后端：原生 oci-containers 支持
    └── vm-definition.nix               # 备用后端：物理双系统磁盘直通检测
```

---

## 四、 核心问题排查与技术解决方案记录

### 1. RDP 不停循环重连、抢占桌面焦点的根治

- **故障现象**：在日常操作电脑时，FreeRDP 窗口反复在桌面上弹窗、自动尝试重新连接，长达数分钟，导致键盘鼠标焦点不断被抢走。
- **根因分析**：
  1. 此前配置的 `systemd.user.timers.winapps-discover` 每 10 分钟在用户桌面环境中自动运行一次 `winapps-setup`；
  2. `winapps-setup` 会调用 GUI FreeRDP 探针，且硬编码了 `+auto-reconnect` 参数；
  3. 一旦虚拟机处于休眠或会话冲突状态，FreeRDP 会默认以 15 秒为间隔**在桌面上弹出模态重试对话框并重试 20 次（长达 5 分钟）**；
  4. 同时系统层的 `winapps-boot-suspend.timer` 也存在 2 分钟轮询，造成多重后台定时器叠加扰动。
- **解决方案**：
  1. **彻底移除所有后台定时器**（`winapps-discover.timer` 与 `winapps-boot-suspend.timer`）；
  2. **应用发现改为用户按需主动触发**：提供 `winapps-scan` 脚本与桌面菜单入口，完全消除后台未经许可的 RDP 调用；
  3. **限制重试次数**：在 `winapps.conf` 中追加 `/auto-reconnect-max-retries:1`，断连后立即静默退出，杜绝死循环。

---

### 2. Office 初次自动安装失败与路径丢失

- **故障现象**：虚拟机装好后没有 Office。
- **根因分析**：
  1. 脚本检测的 `\\tsclient\WinAppsShare\OfficeSetup.exe` 依赖 RDP 驱动重定向，而在系统初次无人值守安装阶段根本没有 RDP 客户端连入，`\\tsclient` 不存在；
  2. 宿主机共享目录未提供有效安装包。
- **解决方案**：
  在 `oem.nix` 中引入微软官方 Office Deployment Tool（ODT）自动流水线：
  1. 脚本自动从微软官方 CDN 静默下载 ODT 引导器 `setup.exe`；
  2. 读取由 NixOS 声明式生成的 `office-configuration.xml` 进行静默安装；
  3. 增加网络共享回退逻辑（自动从 dockur 内置 Samba `\\host.lan\Data` 读取配置）；
  4. 强制启用 PowerShell TLS 1.2，解决 PowerShell 5.1 默认 TLS 1.0 被微软 CDN 拒绝的问题；
  5. 安装完成后自动执行 `mklink /J "C:\Program Files\Microsoft Office\Office16" "C:\Program Files\Microsoft Office\root\Office16"`，使新版 Click-to-Run 安装路径与 WinApps 预设路径无缝兼容。

---

### 3. FreeRDP 3 废弃参数、非标 DPI 与高分屏缩放解耦

- **故障现象**：
  1. 调用 Office 应用时 FreeRDP 闪退，日志中抛出大量 `X_PutImage: BadMatch (invalid parameter attributes)` 和 `Broken pipe`；
  2. 运行 `winapps windows` 启动完整 Windows 桌面时，高分屏（2.5K/4K）未按比例缩放，界面与字体微小如针尖。
- **根因分析**：
  1. FreeRDP 3 废弃了老版本的 `/gfx-progressive` 和 `+glyph-cache` 参数；
  2. 原配置计算出的 `RDP_SCALE="140"` 与 `/scale-desktop:150` 混在全局通用标志中；在 XWayland 下，RemoteApp 单独无缝窗口因非标准分数缩放引起像素位图尺寸不匹配，触发 X11 协议报错并切断连接；
  3. 后续为了解决崩溃而将全局 `RDP_SCALE` 锁死为 100 并移除了 `/scale-desktop`，导致 `winapps windows` 完整桌面会话也彻底失去了 DPI 放大，在高分屏下字小无法看清。
- **解决方案（桌面与单应用缩放解耦）**：
  1. WinApps 上游脚本原生区分了单应用（RemoteApp 使用 `RDP_FLAGS_NON_WINDOWS`）与完整桌面（使用 `RDP_FLAGS_WINDOWS`）；
  2. 全局/RemoteApp 维持 `RDP_SCALE="100"`，确保 Office、豆包等单应用窗口在 XWayland 下绝无 `BadMatch` 闪退；
  3. 在 `RDP_FLAGS_WINDOWS` 中专设 `/scale-desktop:150`（支持通过 `programs.winapps.windows.scale` 灵活配置，默认 150%）与 `/scale-device:140`，通知 Windows 服务端以高 DPI 渲染桌面，使任务栏与窗口字体完美放大，清晰锐利。

---

### 4. 适配 Haumea 模块加载体系（去除 default.nix）

- **背景与原因**：本项目使用 `lib/rake.nix`（基于 `inputs.haumea.lib.load`）组织 NixOS 模块。Haumea 规定若目录内存在 `default.nix`，则该目录会被判定为单一模块，不再自动遍历同目录下的其余 `.nix` 文件，迫使开发者必须在 `default.nix` 中手动书写繁琐的 `imports = [ ... ]`。
- **解决方案**：将 `nixos/modules/desktop/winapps/default.nix` 重命名为 `options.nix`，删除了内部的手动导入列表。Haumea 现在会自动加载 `options.nix`、`podman-windows.nix`、`oem.nix`、`packages.nix` 等同级所有文件，架构优雅扁平。

---

### 5. Btrfs 临时根下的持久化数据迁移

- **背景与原因**：宿主机启用了临时根（每次开机重建根文件系统）。虚拟机的 8GB+ 虚拟磁盘、Office 安装结果与 WinApps 生成的应用元数据若存放在临时根中，重启后会全部丢失。
- **解决方案**：在 Home Manager 中将关键目录声明为持久化绑定挂载，并在生效前完成了数据迁移：
  - `/persist/home/tippy/Storage/WinApps`（虚拟磁盘 `data.img`）
  - `/persist/home/tippy/Storage/WinAppsShare`（共享数据与部署标记）
  - `/persist/home/tippy/.local/share/winapps`（应用配置元数据）
  - `/persist/home/tippy/.local/share/applications`（桌面图标与协议绑定）
  - `/persist/home/tippy/.local/bin`（应用启动包装命令）
  - `/persist/home/tippy/.config/freerdp`（证书与 RDP 连接缓存）

---

### 6. 快速连击导致 Windows Local Session Manager 并发登录冲突（蓝屏错误提示 another session for your user id blocked）

- **故障现象**：在 Linux 文件管理器中双击文档时，偶尔弹出一个 Windows 经典蓝底错误弹窗，提示：`another session for your user id blocked notifying local session manager for 0 minutes, so we are unable to login you in`。
- **根因分析**：
  1. 在 Linux 图形环境下（Nautilus / GNOME），双击文档容易在 0~1 秒内连续派生两个相同参数的 `winapps` 进程；或者用户在虚拟机唤醒的 1~2 秒延时期间进行了二次连击；
  2. 两个独立的 FreeRDP 实例在同一个毫秒级时间窗口内向 Windows 远程桌面端口 3390 发送凭据登录请求；
  3. Windows 10/11 单用户版受单会话并发限制，其内部的 Local Session Manager (LSM) 在处理第一个会话的登录时锁定了会话表，并发连入的第二个连接瞬间触发竞争，Windows 抛出该错误。
- **解决方案**：
  在 `nixos/modules/desktop/winapps/packages.nix` 中对 `bin/winapps` 注入双层防护：
  1. **相同参数调用去重**：3 秒内针对相同文档的调用直接静默退出（`DUPLICATE INVOCATION WITHIN 3s DETECTED. EXITING`），彻底杜绝双击事件多重触发；
  2. **RDP 登录串行化锁 (flock)**：在拉起 FreeRDP 时获取 `${XDG_RUNTIME_DIR}/winapps-rdp-launch.lock`，并预留 2 秒握手窗口后再释放锁，确保即使连续打开多个不同文档，其在 Windows LSM 中的建立也是串行平滑的，完全消除并发碰撞。

---

## 五、 日常运维与使用速查表

```bash
# 1. 启动或检查 Windows 容器服务
systemctl status winapps-windows.service
sudo systemctl start winapps-windows.service

# 2. 查看容器状态 (running 为运行，paused 为休眠)
podman ps -a --filter name=WinApps

# 3. 运行完整 Windows 远程桌面
winapps windows

# 4. 手动扫描并识别 Windows 新安装的软件（如豆包）
winapps-scan
# 或者直接点击应用菜单中的 "WinApps: Scan Applications"

# 5. 直接在终端测试打开 Office
winapps word-o365
winapps excel-o365
winapps powerpoint-o365
```
