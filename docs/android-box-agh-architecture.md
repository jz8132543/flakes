# Android (KernelSU) 端 Box (Mihomo) 与 AdGuardHome 双模块协同架构与防回环迁移实战指南

## 一、 宏观架构总览与分层协同愿景

在基于 Android (KernelSU / Magisk) 的高级网络调优实践中，同时部署 **AdGuardHome for Magisk/Root**（去广告与本地 DNS 解析中枢）与 **Box for KernelSU**（基于 Mihomo/Clash Meta 的透明代理与分流内核）是兼顾隐私过滤、境内外分流与专网穿透（DN42、Tailscale）的终极方案。

然而，两大模块在底层均依赖 Linux 内核的 `iptables` / `ip6tables`、策略路由（Policy Routing）以及 DNS 劫持机制。如果配置不当，极易引发：

1. **DNS 劫持抢占与端口死锁**（53 端口冲突、UDP 报文死循环导致 CPU 100% 与瞬间断网）；
2. **ColorOS / Android 厂商深度定制防火墙封锁**（`fw_OUTPUT` 链阻断、`netd` 解析器 IPv6 报错断网）；
3. **多网络叠加互吞**（Mihomo 误捕获 Tailscale、EasyTier 或 DN42 虚拟隧道接口）。

本方案达成**零底层脚本侵入（Zero Script Modification）**原则：原版安装包解压后的所有启动脚本（`scripts/*.sh`、`action.sh`、`service.sh` 等）**100% 保持官方原版一致**，所有防回环、分流与兼容逻辑完全通过**配置文件声明式收敛与权限补全**实现。

---

### 1.1 总体架构与数据/DNS 双平面拓扑

```text
┌──────────────────────────────────────────────────────────────────────────────────┐
│                            Android 用户空间 (Apps & OS)                          │
│                                                                                  │
│   [普通应用 (白名单)]       [分身应用 (UID 999)]       [专网服务 (Tailscale/DN42)]  │
└────────────┬─────────────────────────┬─────────────────────────┬─────────────────┘
             │ (DNS 查询 :53)           │                         │
             ▼                         │                         │ (排除网卡/直连)
┌───────────────────────────┐          │                         │
│ AdGuardHome (端口 5591)   │          │                         │
│ 负责: 广告拦截、并行解析  │          │                         │
└──────┬─────────────┬──────┘          │                         │
       │             │                 │                         │
       │ 常规域名    │ 专网域名        │                         │
       │             ├─► [/mag/] ──► 100.64.0.1:5300 (Tailscale) │
       │             └─► [/dn42/] ─► 172.20.0.53 / 172.23.0.53  │
       ▼                                                         │
┌───────────────────────────┐                                    │
│ Box / Mihomo (端口 1053)  │                                    │
│ 负责: 分流判定、防污染解析│                                    │
└──────┬─────────────┬──────┘                                    │
       │             │                                           │
       │ 国内直连    │ 境外代理 (Proxy Group)                    │
       ▼             ▼                                           ▼
┌───────────────────────────┐                          ┌───────────────────┐
│ 国内 DoH (223.5.5.5 等)   │                          │  节点出站代理链路 │
└───────────────────────────┘                          └───────────────────┘
```

#### DNS 解析链路标准流转

$$\text{App} \xrightarrow{\text{DNS :53}} \text{AdGuardHome (:5591)} \xrightarrow{\text{上游分流}} \begin{cases} \text{常规域名} \to \text{Mihomo (127.0.0.1:1053)} \to \begin{cases} \text{国内} \to \text{Ali/Tencent DoH (直连)} \\ \text{境外} \to \text{1.1.1.1 DoH (走代理)} \end{cases} \\ \text{专网域名} \to \begin{cases} \text{/mag/} \to \text{100.64.0.1:5300 (Tailscale 局域网)} \\ \text{/dn42/} \to \text{172.20.0.53, 172.23.0.53 (DN42 Anycast)} \end{cases} \\ \text{Mihomo 宕机后备} \to \text{223.5.5.5 / 114.114.114.114 (公网纯 IP)} \end{cases}$$

#### 业务流量转发路径

$$\text{App 流量} \xrightarrow{\text{白名单 UID}} \text{Mihomo TUN (tun0)} \xrightarrow{\text{路由判定}} \begin{cases} \text{直连流量 (CN / IP)} \to \text{物理网卡 (wlan0 / rmnet)} \\ \text{代理流量 (GFW / 海外)} \to \text{VLESS Reality / Shadowsocks 节点出站} \\ \text{专网流量 (100.64.0.0/10, 172.20.0.0/14)} \to \text{排除网卡直通 (tailscale0 / dn42)} \end{cases}$$

---

### 1.2 核心设计边界与职责划分

| 架构层级                  | 运行组件         | 监听端口 / 虚拟接口              | 核心设计边界与职责                                                                                                                                                       |
| :------------------------ | :--------------- | :------------------------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **第一级 DNS (L1 Entry)** | **AdGuardHome**  | `127.0.0.1:5591` (重定向接管 53) | **广告过滤与内网特种分流**：作为手机全局 DNS 入口，过滤广告规则；负责将私有域名（如 `/mag/`、`/dn42/`）直接导向对应专网 DNS，常规流量无缝转交 L2。                       |
| **第二级 DNS (L2 Proxy)** | **Box (Mihomo)** | `0.0.0.0:1053`                   | **智能分流与防污染解析**：不接管全局 53 端口；国内域名使用国内 DoH 直连解析，境外域名经由代理节点发送至 1.1.1.1/8.8.8.8 DoH；严禁 nameserver/fallback 指向本机 53 端口。 |
| **透明代理与出站**        | **Box (Mihomo)** | `tun0` (TUN 模式)                | **出站接管与隔离**：使用 TUN 模式绕过 ColorOS `fw_OUTPUT` 封锁；利用 `package.list.cfg` 精确按 UID 白名单代理；严格排除 `tailscale0` 等虚拟网卡。                        |

---

## 二、 核心冲突机理深度剖析与根治方案

### 2.1 冲突一：本地 127.0.0.1:53 端口争夺与循环死锁 (DNS Loop)

#### 1. 深度病因剖析

- 原版 Box 模块默认启用了 `mihomo_dns_forward="enable"`，其底层脚本会向 `iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-ports 1053` 注入规则，强行抢夺系统的 53 端口流量；
- 此时若 AdGuardHome 模块也配置了 `enable_iptables=true` 并监听 53 端口重定向，两者将在 `iptables` 规则链中发生竞态抢占；
- 更严重的是：如果 Mihomo 订阅中的 `fallback` 或 `nameserver` 错误配置了 `127.0.0.1:53` 或系统默认解析器，会导致以下死锁闭环：
  $$\text{App} \to \text{AGH (:53)} \to \text{Mihomo (:1053)} \to \text{Fallback (:53)} \to \text{AGH (:53)} \to \cdots$$
  瞬时产生每秒上万次的 UDP 回环风暴，CPU 占用拉满到 100%，端口号耗尽，手机全局断网。

#### 2. 根治方案

1. **Box 彻底让出 53 端口**：在 `/data/adb/box/settings.ini` 中设置 `mihomo_dns_forward="disable"`，关闭 Box 对 53 端口的 `nat OUTPUT` 劫持；
2. **AdGuardHome 成为唯一 53 拦截者**：由 AGH 的 iptables 规则将 53 端口重定向至 `127.0.0.1:5591`；
3. **Mihomo 上游解耦**：Mihomo 的 `nameserver` 与 `fallback` 仅配置外部 DoH（如国内阿里/腾讯、海外 Cloudflare/Google），绝对不包含 `127.0.0.1:53` 或 `127.0.0.1:5591`；
4. **AGH 纯 IP 兜底保活**：在 AGH 的 `fallback_dns` 中加入 `223.5.5.5` 与 `114.114.114.114`，确保即使 Box 服务停用或崩溃，手机仍能正常解析域名，避免因代理内核关闭导致手机彻底失联。

---

### 2.2 冲突二：ColorOS / Android netd IPv6 DNS 解析报错断网

#### 1. 深度病因剖析

- 原版 AdGuardHome 模块的默认配置为 `block_ipv6_dns=true`。其实现原理是通过 `ip6tables` 注入如下规则：
  ```bash
  ip6tables -t filter -A OUTPUT -p udp --dport 53 -j REJECT
  ip6tables -t filter -A OUTPUT -p tcp --dport 53 -j REJECT
  ```
- 在原生 AOSP 或部分类原生系统中，系统解析器遇到 REJECT 会优雅回退至 IPv4 DNS 查询；
- **但是在 OPPO/OnePlus ColorOS 及部分定制 ROM 中**，底层的系统网络守护进程（`netd`）对 DNS 请求设置了严格的异常处理状态机。当发送 IPv6 DNS 报文立即收到内核丢回的 ICMPv6 Port Unreachable (REJECT) 时，`netd` 会直接将当前网络接口标记为 `NO_INTERNET` 甚至解析器底层抛错崩溃，导致整个手机所有网络请求全线瘫痪。

#### 2. 根治方案

- 在 `/data/adb/agh/settings.conf` 中必须强制修改为：
  ```ini
  block_ipv6_dns=false
  ```
- 允许 IPv6 DNS 请求正常进入解析流程，由 AGH 或 Mihomo 内部进行 AAAA 过滤或通过代理返回，严禁在 `ip6tables` 传输层暴力 REJECT。

---

### 2.3 冲突三：ColorOS `fw_OUTPUT` 防火墙链阻断 Google 等境外流量

#### 1. 深度病因剖析

- Box 模块原版默认采用 `network_mode="tproxy"`（透明代理模式）。
- ColorOS 内部集成了一套深度定制的安全防火墙链（`fw_OUTPUT` / `oem_out`），该链会在路由判决前对系统应用（如 Google Play 服务、Google 框架、海外浏览器等）的 socket 连接状态和打标数据包进行合规性深度校验；
- 在 TPROXY 模式下，未建立连接的境外流量在经过 mangle 链打标并被重定向到本地时，极易被 `fw_OUTPUT` 误判为异常伪造流量而直接 DROP；
- 同时，TPROXY 复杂的规则生成过程耗时较长，开机自启通常需要 5~10 秒。

#### 2. 根治方案

- 将 Box 运行模式切换为纯 TUN 模式：`/data/adb/box/settings.ini` 设置 `network_mode="tun"`；
- **机理优势**：
  1. TUN 虚拟网卡（`tun0`）直接在 Layer 3（IP 层）接管网络数据包，绕过了 ColorOS `iptables` mangle/nat 针对特定流的校验拦截；
  2. 实现 1 秒极速冷启动，且网络稳定性显著提升，不再受厂商系统更新导致的 iptables 规则链变动影响。

---

### 2.4 冲突四：多网卡与虚拟网卡（Tailscale / EasyTier / DN42）流量互捕死锁

#### 1. 深度病因剖析

- 手机上常常同时运行 Tailscale、EasyTier 或通过 WireGuard 接入的 DN42 专网；
- Box 默认的网卡白名单包含了 `wlan+`、`ap+`、`eth+` 等，且如果未明确排除虚拟网卡，Mihomo 的 TUN `auto-route` 会将发往专网网卡（如 `tailscale0`）的流量再次捕获进 `tun0`；
- 产生虚拟接口间的互相嵌套捕获，造成 Tailscale 节点离线、DN42 路由黑洞。

#### 2. 根治方案

1. **Box 网卡入站严格忽略**：在 `/data/adb/box/ap.list.cfg` 中显式添加 `ignore tailscale0`；
2. **Mihomo TUN 排除网卡与路由声明**：在订阅注入模板中增加：
   ```yaml
   tun:
     exclude-interface: [tailscale0, easytier0, dn42, dn42x-+, xfrm+]
     route-exclude-address:
       - 100.64.0.0/10 # Tailscale CGNAT 地址段
       - 172.20.0.0/14 # DN42 内网 IPv4 段
       - 223.5.5.5/32 # 阿里公共 DNS (保障直连解析)
       - 114.114.114.114/32 # 114 公共 DNS
   ```

---

## 三、 全量配置差异对比速查（原版 Zip vs 生产环境）

### 3.1 `AdGuardHomeForRoot_arm64.zip` 全量差异对比

两个模块的底层脚本（`scripts/*.sh`、`action.sh`、`service.sh` 等）与原版安装包 **100% 一致，没有任何改动**。差异全量收敛于以下两个配置文件：

#### 1. `/data/adb/agh/settings.conf`（模块运行配置）

> 注：`enable_iptables=true`、`redir_port=5591`、`adg_user=root`、`adg_group=net_raw` 均保持原版默认不变。

| 配置项                | 安装包默认值 | 当前生产修改值   | 架构与避坑说明                                                                                        |
| :-------------------- | :----------- | :--------------- | :---------------------------------------------------------------------------------------------------- |
| **`block_ipv6_dns`**  | `true`       | **`false`**      | **核心避坑项**：设为 `false` 防止 `ip6tables REJECT` 导致 ColorOS `netd` 解析器抛错进而造成全局断网。 |
| **`startup_timeout`** | `120`        | _(脚本默认 120)_ | 保留默认 `startup_timeout=120` 即可。                                                                 |

#### 2. `/data/adb/agh/bin/AdGuardHome.yaml`（AdGuardHome 核心配置）

> 注：Web 管理端口 `127.0.0.1:3000`、DNS 监听端口 `127.0.0.1:5591`、默认去广告规则订阅 `AWAvenue-Ads-Rule` 均与原版一致。

| 配置区块                      | 安装包默认值                                                        | 当前生产修改值                                                                                                                     | 架构与避坑说明                                                                                                                 |
| :---------------------------- | :------------------------------------------------------------------ | :--------------------------------------------------------------------------------------------------------------------------------- | :----------------------------------------------------------------------------------------------------------------------------- |
| **`dns.upstream_dns`**        | `- https://223.5.5.5/dns-query`<br>`- https://1.12.12.12/dns-query` | **`- 127.0.0.1:1053`**<br>**`- '[/mag/]tcp://100.64.0.1:5300'`**<br>**`- '[/dn42/]172.20.0.53'`**<br>**`- '[/dn42/]172.23.0.53'`** | 常规域名全部交由 Mihomo (`1053`) 分流解析；特定专网后缀（`/mag/`、`/dn42/`）由 AGH 直接转发给内网 DNS 权威节点，彻底规避回环。 |
| **`dns.fallback_dns`**        | `- https://1.1.1.1/dns-query`<br>`- https://8.8.8.8/dns-query`      | `- https://1.1.1.1/dns-query`<br>`- https://8.8.8.8/dns-query`<br>**`- 223.5.5.5`**<br>**`- 114.114.114.114`**                     | 增加国内纯 IP 后备 DNS。当 Box/Mihomo 关闭维护或异常宕机时，AGH 单开即可毫秒级回退至直连 DNS，保障基础网络不中断。             |
| **`dns.upstream_mode`**       | `load_balance`                                                      | **`parallel`**                                                                                                                     | 改为并行并发查询模式，显著降低首次域名解析延迟。                                                                               |
| **`filtering.max_http_size`** | _(未指定，默认很小)_                                                | **`256MB`**                                                                                                                        | 调高规则文件最大下载体积限制，防止大型去广告规则更新失败。                                                                     |

---

### 3.2 `box_1.2.9.3b9fa58.zip` 全量差异对比

#### 1. `/data/adb/box/settings.ini`（Box 模块运行参数）

| 配置项                           | 安装包默认值 | 当前生产修改值                                | 架构与避坑说明                                                                                                  |
| :------------------------------- | :----------- | :-------------------------------------------- | :-------------------------------------------------------------------------------------------------------------- |
| **`network_mode`**               | `"tproxy"`   | **`"tun"`**                                   | **模式核心变更**：启用 TUN 模式，避开 ColorOS `fw_OUTPUT` 防火墙链对 Google 框架的断网封锁，并实现 1 秒冷启动。 |
| **`performance_mode`**           | `"false"`    | **`"true"`**                                  | 启用性能模式（需配合 `/data/adb/box/bin/boxbpf` 赋予 `0755` 权限）。                                            |
| **`quic`**                       | `"enable"`   | **`"disable"`**                               | 禁用 UDP 443 QUIC，防止海外视频流媒体或 Google 搜索直接走 UDP 泄露导致卡顿降速。                                |
| **`mihomo_dns_forward`**         | `"enable"`   | **`"disable"`**                               | **防冲突核心**：关闭 Box 的 53 端口 `nat OUTPUT` 劫持，将 53 端口完全出让给 AdGuardHome。                       |
| **`dns_hijack_mode`**            | `"redirect"` | **`"tproxy"`**                                | 在 TPROXY 辅助模式下接管漏网的 IPv6 DNS。                                                                       |
| **`mac_filter`**                 | `"false"`    | **`"true"`**                                  | 启用热点客户端 MAC 黑白名单能力。                                                                               |
| **`proxy_mode`**                 | `"core"`     | **`"whitelist"`**                             | 改为应用白名单模式（仅代理 `package.list.cfg` 中的应用，避免银行/国内支付 App 异常）。                          |
| **`subscription_url_mihomo`**    | `()`         | **`("https://sub.dora.im/.../mihomo.yaml")`** | 统一订阅生成服务提供的 Mihomo 订阅链接。                                                                        |
| **`name_provide_mihomo_config`** | `()`         | **`("doraim")`**                              | 本地订阅配置文件命名标识。                                                                                      |
| **`renew`**                      | `"false"`    | **`"true"`**                                  | 更新订阅时强制覆盖并重新生成 `config.yaml`。                                                                    |
| **`update_subscription`**        | `"false"`    | **`"true"`**                                  | 开启订阅计划任务自动定时更新。                                                                                  |
| **`use_ghproxy`**                | `"false"`    | **`"true"`**                                  | 启用 GitHub 下载镜像加速源 (`https://ghfast.top`)。                                                             |

#### 2. `/data/adb/box/ap.list.cfg`（网卡过滤规则）

- **原版安装包默认值**：
  ```ini
  allow ap+
  allow wlan+
  allow rndis+
  allow swlan+
  allow ncm+
  allow eth+
  # ignore wlan+
  ```
- **生产修改值**：
  ```ini
  # allow ap+
  # allow wlan+
  allow rndis+
  allow swlan+
  allow ncm+
  allow eth+
  ignore ap+
  ignore wlan+
  ignore tailscale0
  ```
  > **说明**：显式注释掉直接接管的 `allow ap+` 与 `allow wlan+`，增加 `ignore tailscale0`，彻底防止虚拟隧道接口流量被 Box 误劫持。

#### 3. `/data/adb/box/gid.list.cfg`（绕过用户组 GID）

- **原版安装包默认值**：全注释为空。
- **生产修改值**：
  ```text
  9999
  #3004
  ```

#### 4. `/data/adb/box/package.list.cfg`（白名单分流应用包名列表）

- **原版安装包默认值**：仅为 10 行说明注释模板。
- **生产修改值**：录入了 **385 个应用包名**，支持双用户空间隔离：
  - `0:<包名>`：主空间应用（如 Chrome、Telegram、Google Play、YouTube、Syncthing 等）；
  - `999:<包名>`：多开/应用分身空间应用。
  > **迁移建议**：换新设备时建议直接保留并复制该文件，无需在 WebUI 中重新逐个勾选。

#### 5. `/data/adb/box/mihomo/config.yaml`（Mihomo 运行时配置）

由订阅链接（`renew="true"`）拉取生成，并在启动时由 `box.service` 中的 `prepare_mihomo` 函数自动注入系统 UID。核心配置区块如下：

1. **DNS 配置区（防污染与防回环架构）**：
   ```yaml
   dns:
     enable: true
     listen: 0.0.0.0:1053
     ipv6: true
     enhanced-mode: redir-host
     default-nameserver:
       - 1.12.12.12
       - 223.5.5.5
       - 119.29.29.29
     nameserver:
       - "https://1.1.1.1/dns-query#PROXY"
       - "https://8.8.8.8/dns-query#PROXY"
     nameserver-policy:
       "+.dn42": [172.20.0.53, 172.23.0.53, "172.20.232.1:53"]
       "+.dora.dn42": [172.20.0.53, 172.23.0.53, "172.20.232.1:53"]
       "+.ts": ["100.100.100.100:53"]
       "+.dora.im": [https://223.5.5.5/dns-query, https://1.12.12.12/dns-query]
       "+.kxy.ovh": [https://223.5.5.5/dns-query, https://1.12.12.12/dns-query]
       "geosite:cn,apple,private,steam,onedrive":
         [https://223.5.5.5/dns-query, https://1.12.12.12/dns-query]
   ```
2. **TUN 配置区（虚拟网卡隔离与防回环声明）**：
   ```yaml
   tun:
     enable: true
     stack: system
     device: tun0
     auto-route: true
     auto-redirect: true
     auto-detect-interface: true
     exclude-interface:
       - tailscale0
       - easytier0
       - dn42
       - dn42x-+
       - xfrm+
     route-exclude-address:
       - 100.64.0.0/10
       - 172.20.0.0/14
       - 223.5.5.5/32
       - 114.114.114.114/32
     # include-uid 由 box.service 依据 package.list.cfg 自动计算并追加
   ```

---

### 3.3 二进制依赖与权限补全规范

安装包解压后，部分二进制文件的初始权限或存在缺失，在新机部署时必须进行补齐：

1. **BPF 加速模块权限修复**：
   - 文件路径：`/data/adb/box/bin/boxbpf`
   - 安装包解压默认权限：`0644`（无执行权限，导致性能模式启动报 warning 失败）
   - **修正操作**：`chmod 0755 /data/adb/box/bin/boxbpf`
2. **Mihomo 核心内核补齐**：
   - 文件路径：`/data/adb/box/bin/mihomo`
   - 说明：原版 `box` 模块 zip 包出于体积考量**不自带内核二进制**；
   - **获取方式**：
     - _方式 A_：直接执行 `/data/adb/box/scripts/box.tool upcore` 自动在线拉取；
     - _方式 B_：从现有设备直接复制 `mihomo`（架构为 `aarch64` / `arm64-v8a`，版本为 `Mihomo Meta v1.19.32`），并执行 `chmod 0755 /data/adb/box/bin/mihomo`。

---

## 四、 完整配置文件落地实录

本章节提供生产环境下所有修改文件的完整声明式内容，用于新设备迁移时直接复制还原。

### 4.1 `/data/adb/agh/settings.conf`

```ini
#!/system/bin/sh
# AdGuardHome for Magisk/KernelSU 运行配置

enable_iptables=true
redir_port=5591
adg_user=root
adg_group=net_raw

# 关键设置: 必须为 false, 防止 ColorOS netd 报错断网
block_ipv6_dns=false

startup_timeout=120
```

---

### 4.2 `/data/adb/agh/bin/AdGuardHome.yaml` (关键配置片段)

```yaml
bind_host: 127.0.0.1
bind_port: 3000
users: []
auth_attempts: 0
block_auth_min: 15
http_proxy: ""
language: zh-cn
theme: auto

dns:
  bind_hosts:
    - 127.0.0.1
  port: 5591
  statistics_interval: 1
  querylog_enabled: true
  querylog_file_enabled: true
  querylog_interval: 24h
  querylog_size_memory: 1000
  anonymize_client_ip: false
  protection_enabled: true
  blocking_mode: default
  blocking_ipv4: ""
  blocking_ipv6: ""
  blocked_response_ttl: 10
  protection_disabled_until: null
  edns_client_subnet:
    custom_ip: ""
    enabled: false
    use_custom: false
  max_goroutines: 300
  depth: 0

  # 关键: 上游指向 Mihomo (1053) 与专用内网 DNS
  upstream_dns:
    - 127.0.0.1:1053
    - "[/mag/]tcp://100.64.0.1:5300"
    - "[/dn42/]172.20.0.53"
    - "[/dn42/]172.23.0.53"

  upstream_dns_file: ""

  # 关键: 增加国内纯 IP 兜底, 避免 Mihomo 维护时断网
  fallback_dns:
    - https://1.1.1.1/dns-query
    - https://8.8.8.8/dns-query
    - 223.5.5.5
    - 114.114.114.114

  upstream_mode: parallel
  fastest_addr: false
  fastest_timeout: 1s
  use_http3_upstreams: false
  use_dns64: false
  dns64_prefixes: []
  all_servers: false
  rebind_protection: false

filtering:
  blocking_ipv4: ""
  blocking_ipv6: ""
  blocked_services:
    schedule:
      time_zone: Local
    ids: []
  protection_enabled: true
  filtering_enabled: true
  parental_enabled: false
  safe_search:
    enabled: false
  rewrites: []
  max_http_size: 256MB
```

---

### 4.3 `/data/adb/box/settings.ini`

```ini
#!/system/bin/sh

# 网络运行模式: tun 模式绕过 ColorOS fw_OUTPUT 阻断并加速启动
network_mode="tun"

# 性能模式 (配合 boxbpf 可执行权限)
performance_mode="true"

# 禁用 QUIC (防 UDP 443 漏网/限速)
quic="disable"

# 关键: 关闭 Box 自身 53 劫持, 出让给 AdGuardHome
mihomo_dns_forward="disable"

dns_hijack_mode="tproxy"
mac_filter="true"

# 代理模式: 白名单模式 (仅代理 package.list.cfg)
proxy_mode="whitelist"

# 订阅配置
subscription_url_mihomo=("https://sub.dora.im/.../mihomo.yaml")
name_provide_mihomo_config=("doraim")
renew="true"
update_subscription="true"
use_ghproxy="true"
```

---

### 4.4 `/data/adb/box/ap.list.cfg`

```ini
# allow ap+
# allow wlan+
allow rndis+
allow swlan+
allow ncm+
allow eth+
ignore ap+
ignore wlan+
ignore tailscale0
```

---

### 4.5 `/data/adb/box/gid.list.cfg`

```text
9999
#3004
```

---

## 五、 新机 5 分钟迁移与灾备恢复实战指南 (Disaster Recovery Runbook)

当更换新设备或重新刷机时，请按本步骤流水线快速还原双模块环境。

### 5.1 前置准备

1. 确保手机已刷入 **KernelSU**（或 APatch / Magisk），并已赋予 Root 权限管理器与终端（Termux / ADB Shell）Root 权限；
2. 准备好官方原版模块刷机包：
   - `AdGuardHomeForRoot_arm64.zip`
   - `box_1.2.9.3b9fa58.zip`
3. 备份旧手机上的白名单文件：`/data/adb/box/package.list.cfg`。

---

### 5.2 极速安装与配置注入流水线

在电脑端连接手机执行 `adb shell`（或在 Termux 中执行 `su`），按顺序执行：

```bash
# 1. 刷入原版模块 (亦可在 KernelSU App 界面中直接点击安装)
ksud module install /sdcard/Download/AdGuardHomeForRoot_arm64.zip
ksud module install /sdcard/Download/box_1.2.9.3b9fa58.zip

# 2. 停用两模块后台服务以防写入冲突
/data/adb/box/scripts/box.service stop
/data/adb/agh/scripts/agh.service stop

# 3. 补齐二进制文件与可执行权限
chmod 0755 /data/adb/box/bin/boxbpf
# 若未从旧机备份 mihomo 内核，则在线下载：
/data/adb/box/scripts/box.tool upcore
chmod 0755 /data/adb/box/bin/mihomo

# 4. 注入 AdGuardHome 配置
cat <<'EOF' > /data/adb/agh/settings.conf
enable_iptables=true
redir_port=5591
adg_user=root
adg_group=net_raw
block_ipv6_dns=false
startup_timeout=120
EOF
chmod 0644 /data/adb/agh/settings.conf

# 5. 注入 Box 配置
cat <<'EOF' > /data/adb/box/settings.ini
network_mode="tun"
performance_mode="true"
quic="disable"
mihomo_dns_forward="disable"
dns_hijack_mode="tproxy"
mac_filter="true"
proxy_mode="whitelist"
subscription_url_mihomo=("https://sub.dora.im/.../mihomo.yaml")
name_provide_mihomo_config=("doraim")
renew="true"
update_subscription="true"
use_ghproxy="true"
EOF
chmod 0644 /data/adb/box/settings.ini

# 6. 注入网卡忽略与 GID 配置
cat <<'EOF' > /data/adb/box/ap.list.cfg
# allow ap+
# allow wlan+
allow rndis+
allow swlan+
allow ncm+
allow eth+
ignore ap+
ignore wlan+
ignore tailscale0
EOF
chmod 0644 /data/adb/box/ap.list.cfg

cat <<'EOF' > /data/adb/box/gid.list.cfg
9999
EOF
chmod 0644 /data/adb/box/gid.list.cfg

# 7. 还原白名单应用列表 (直接推送备份文件)
# adb push package.list.cfg /data/adb/box/package.list.cfg
chmod 0644 /data/adb/box/package.list.cfg

# 8. 启动服务
/data/adb/agh/scripts/agh.service start
/data/adb/box/scripts/box.service start
```

---

### 5.3 生产验证清单 (Verification Checklist)

完成上述配置与服务启动后，执行以下 5 项测试确认系统处于健康状态：

#### 检查项 1：DNS 解析层级与防回环验证

在终端中执行测试解析：

```bash
# 测试 1: 本地 53 端口是否由 AGH 正常响应
nslookup baidu.com 127.0.0.1:53

# 测试 2: 专网域名是否由 AGH 精准分流至内网 DNS
nslookup router.dn42 127.0.0.1:53

# 测试 3: 检查 Mihomo 端口是否处于监听状态
netstat -tulpn | grep -E '1053|5591|3000'
```

_预期结果_：

- `5591` (AGH DNS) 与 `1053` (Mihomo DNS) 同时处于 LISTEN 状态；
- `baidu.com` 正常返回国内 CDN IP；
- `router.dn42` 正确返回 `172.20.x.x`；
- 手机 CPU 占用极低（< 2%），无任何回环死锁迹象。

#### 检查项 2：Mihomo 宕机熔断测试

```bash
# 模拟 Mihomo 崩溃/关闭
/data/adb/box/scripts/box.service stop

# 立即在手机上打开网页或 ping 223.5.5.5 / baidu.com
nslookup qq.com 127.0.0.1:53
```

_预期结果_：

- 由于 AGH 配置了 `223.5.5.5` 与 `114.114.114.114` 作为 `fallback_dns`，国内网页依然能够正常秒开，手机绝对不会全局断网。

#### 检查项 3：ColorOS IPv6 断网排查

切换 Wi-Fi 与蜂窝数据，观察手机状态栏 Wi-Fi 图标是否出现感叹号 `!`。

```bash
# 验证 ip6tables 中不存在 53 端口 REJECT 规则
ip6tables -L OUTPUT -n -v | grep 53
```

_预期结果_：无 REJECT 规则输出，网络连接状态显示为“已连接（无网络受限提示）”。

#### 检查项 4：TUN 模式接管与白名单分流

```bash
# 检查 tun0 虚拟网卡状态
ip addr show tun0

# 检查当前白名单 UID 是否已被 Mihomo 正确纳入
grep -A 20 "include-uid" /data/adb/box/mihomo/config.yaml
```

_预期结果_：`tun0` 网卡已分配 IP（通常为 `198.18.0.1/16`），`include-uid` 列表中包含主空间与双开空间的全部目标 UID。

#### 检查项 5：Tailscale 专网共存测试

打开 Tailscale，连接私有节点，尝试访问 Tailscale 内部服务或 Ping 内部 IP：

```bash
ping 100.64.0.1
```

_预期结果_：网络直达无延迟丢包，`tailscale0` 接口未被 Box 拦截。

---

### 5.4 常见故障快速排错速查表

| 故障现象                                                            | 潜在病因排查                                                                                                            | 快速修复命令                                                                                                                                                                                      |
| :------------------------------------------------------------------ | :---------------------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **开机后手机瞬间严重卡顿、发烫，CPU 100%，所有应用无法上网**        | 触发了 DNS 回环死锁：Mihomo 的 upstream 误配了 53 端口，或 Box 的 `mihomo_dns_forward` 未关闭。                         | 1. 紧急停止两模块：<br>`pkill -9 mihomo; pkill -9 AdGuardHome`<br>2. 检查并确保 `/data/adb/box/settings.ini` 中 `mihomo_dns_forward="disable"`<br>3. 检查 `AdGuardHome.yaml` 中没有包含自身端口。 |
| **连接 Wi-Fi 提示“网络连接受限”且无法解析域名，但纯 IP 能 Ping 通** | `block_ipv6_dns=true` 导致 ColorOS `netd` 抛错。                                                                        | 在 `/data/adb/agh/settings.conf` 中修改为 `block_ipv6_dns=false`，重启 AGH 服务。                                                                                                                 |
| **Google 全家桶、海外 App 无法连接，但国内 App 一切正常**           | 1. `settings.ini` 中使用了 `tproxy` 模式被 ColorOS `fw_OUTPUT` 阻断；<br>2. 目标 App 未加入 `package.list.cfg` 白名单。 | 1. 改为 `network_mode="tun"`；<br>2. 检查 `package.list.cfg` 是否包含对应包名。                                                                                                                   |
| **性能模式提示加载失败，日志提示 Permission Denied**                | `/data/adb/box/bin/boxbpf` 缺少可执行权限。                                                                             | 执行 `chmod 0755 /data/adb/box/bin/boxbpf` 并重启 Box 服务。                                                                                                                                      |
| **Tailscale 启动后无法连接对端节点**                                | Box 劫持了虚拟接口。                                                                                                    | 检查 `/data/adb/box/ap.list.cfg`，确保已写入 `ignore tailscale0`。                                                                                                                                |
