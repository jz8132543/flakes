# WinPodX 声明式集成

WinPodX 输入由 `flake.lock` 固定。配置入口是 `programs.winpodx`，应用快捷方式集中在 `nixos/modules/desktop/winpodx/shortcuts.nix`。

## 配置与状态

- `~/.config/winpodx/nixos.toml` 是只读的 Nix 参数文件，不包含密码或产品密钥。
- Home Manager 激活时，`winpodx-deploy init` 仅在文件不存在时复制模式为 `0600` 的可写 `winpodx.toml`。之后由 WinPodX 管理配置、令牌与密码，不再使用自写 Python 同步器。修改 Nix 初始值不会覆盖已有运行配置。
- `passwordFile`、`activation.windowsProductKeyFile`、`activation.officeProductKeyFile` 只接收运行时路径，可使用用户可读的 sops-nix secrets。未指定密码时首次部署生成随机密码。
- VM 磁盘和运行状态分别持久化在 `~/Storage/WinPodX`、`~/.config/winpodx`、`~/.local/share/winpodx`。
- 不要在安装后随意修改版本或语言：dockur 可能将其视为安装介质变化并备份重装。初始配置不再在每次重建时覆盖运行值。

## 首次部署

`winpodx-deploy.service` 是 systemd 用户 `Type=exec` 服务，登录时后台执行；运行上限八小时，失败五分钟后重试。它不让系统切换等待整个安装流程；`init` 遇到正在运行的部署锁时直接退出，不阻塞 Home Manager 激活。

1. shell 在首次启动前写入持久化 `~/.config/winpodx/deployment.pending`，调用 WinPodX 原生命令，由其管理容器拉取和底座 ISO 下载、Windows 安装。
   原生 OEM 目录准备同时调用上游令牌函数，将相同认证令牌私有地保存到主机和 OEM；不能只复制静态脚本而省略此步骤。
2. 保留完整的 WinPodX OEM 初始化，在其最终服务重启前增加一个小钩子，复制 Office 文件并注册 SYSTEM 计划任务。
3. Windows 计划任务在启动后运行，每十分钟重试未完成步骤，且同一时间只允许一个实例。宿主退出或关机不删除部署标记、虚拟磁盘或任务。
4. 计划任务使用 ODT 安装中文版 Office，验证 Microsoft 安装器签名、安装返回值和程序文件；只有安装完整结束后才提交独立的 `office.installed` 检查点。后续激活失败不再重新安装 Office。
5. 执行选定的激活方式并读取实际授权状态。`official` 使用合法产品密钥/已有授权；Microsoft 365 账户登录不能伪装成自动激活。`mas` 是显式选择的第三方实现，仅在客户机内运行固定提交的 MAS 3.12，并在宿主与客户机两端核对 SHA-256。MAS 状态不等于取得了微软软件许可。
6. 客户机通过底座原生 Samba `Data` 共享（`/storage/shared`）原子发布状态。宿主收到匹配部署版本且完成的结果后运行上游 provisioning/discovery/reverse-open，检查 `sync_error`，最后释放暂停保护。共享不可用不算完成。

Tiny10 的上游社区安装介质通常只有英文版本。`language = "Chinese"`、区域和输入法配置不等于安装介质包含中文显示语言包；必须在部署后核实实际语言。Office 独立使用 `zh-cn` 安装语言。

部署状态写入 `~/Storage/WinPodX/shared/winpodx-deployment.json`，客户机同时保存 `C:\ProgramData\WinPodX-NixOS\deployment.json` 和 `provision.log`。`complete = true` 需要安装及验证成功，默认还要求已激活。宿主另外保留 `deployment.done`，完整部署后再次登录不会为了重跑任务唤醒虚拟机。

## 生命周期与桌面

- `winpodx-tray.service` 使用原生 idle pause、reverse-open 和 Office 窗口回收。保护不只依赖服务启动顺序：包内暂停入口和 Podman 子进程受持久化标记与共享锁保护，手动打开 GUI/托盘也不能在部署期间暂停、停止或替换容器，磁盘清理入口亦会拒绝操作。原生空闲监控在标记释放后继续运行，没有新增空闲守护进程。
- Podman 后端的 Compose 使用专用 `slirp4netns` 网络，DNS 经 `10.0.2.2` 回到宿主解析器，并配置 `no-aaaa`。这避免默认 `pasta` 复制大量 DN42 路由失败，不修改宿主路由或全局容器网络默认值。
- 容器启动在独立 systemd scope 内执行，子进程关闭部署锁文件描述符。调度服务结束或重启不会误杀容器的端口转发进程，也不会让辅助进程一直占用部署锁。
- 托盘服务在部署标记存在时不自动启动；部署成功后由调度启动。手动启动的 GUI/托盘仍服从相同保护。
- 保护范围是本项目安装的 WinPodX；直接运行 Podman 管理命令、宿主关机和 OOM 不属于该保护。旧的未修补进程必须先停止。
- `autoStart = false` 禁止每次登录主动启动 Windows；应用启动仍由上游负责按需恢复。空闲行为设为 `pause`，具体唤醒时间取决于宿主与客户机状态，不能保证毫秒级恢复。
- 上游 RemoteApp 命令内置 CJK IME 支持位修复。多会话由上游 rdprrap 注入和状态检查管理，`maxSessions` 是目标上限，不是所有软件一定可并发的保证。
- 声明的 Word、Excel、PowerPoint 生成真实 `app.toml` 叶文件及系统 `.desktop`，正确配置 WM_CLASS 和单文件 `%f` 传参。豆包需先在新客户机中安装并发现，不能因桌面入口存在就认为它已安装。
- 自动发现保留应用数据与图标，自动注册桌面入口被环境变量 `WINPODX_DECLARATIVE_SHORTCUTS=1` 禁用，避免与 Nix options 管理的快捷方式重复。
- 不会为了 Office 保存而默认关闭 Protected View 或信任整个主目录；需要网络可信位置时应仅信任明确的工作目录。

## 常用命令

| 命令                                             | 用途                     |
| ------------------------------------------------ | ------------------------ |
| `winpodx-deploy`                                 | 重试无人值守部署         |
| `winpodx-deploy status`                          | 读取部署和授权检查结果   |
| `systemctl --user status winpodx-deploy.service` | 查看首次部署服务         |
| `journalctl --user -u winpodx-deploy.service`    | 查看部署日志             |
| `winpodx app run desktop`                        | 完整 Windows 桌面        |
| `winpodx app run word <file>`                    | 用 Word 打开一个宿主文件 |
| `winpodx app refresh --json`                     | 重新发现客户机应用       |
| `winpodx guest multi-session status`             | 检查实际多会话补丁状态   |
| `winpodx host-open daemon-status --json`         | 检查 reverse-open 监听器 |
| `winpodx doctor`                                 | 上游健康检查             |
