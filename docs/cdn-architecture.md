# Apache Traffic Control (ATC) 分布式 CDN 架构与动态同步运维实战指南

## 一、 宏观架构总览与全自动自适应解耦愿景

本系统基于 **Apache Traffic Control (ATC)** 与 **NixOS Flakes** 现代化声明式基础设施体系，构建了一套覆盖全球多地域的高性能分布式内容分发网络（CDN）。

架构核心目标在于实现**控制面、调度面、数据面、源站面与交付面的完全正交解耦**。系统贯彻**单一事实来源（Single Source of Truth）**与**零主机入侵（Zero Host-Intrusion）**原则：

1. **单一配置入口**：所有控制平面节点、边缘加速节点、权威 DNS 调度节点以及加速业务映射，**全部收敛于 `terraform/cdn.tf` 声明**。任何机器更迭、扩缩容或增减服务，**无需修改任何 NixOS 主机或模块内部业务代码**。
2. **角色自适应分发（Role Auto-Derivation）**：全局 ATC 模块基于 `lib/data/data.json` 自动计算当前主机的角色（控制平面 vs 边缘加速缓存 vs 非 CDN 普通计算节点），各主机 `default.nix` 保持 100% 干净与可复用。
3. **控制面优雅寻址与多控制节点容灾（Multi-Control Plane HA）**：边缘节点不写死单一控制节点的主机名，统一通过通用的控制域（如 `ops.dora.im`）与多候选节点池寻址，预留多控制中心高可用扩展空间。
4. **基于 Git Commit Hash 与 Flake 时间戳的版本仲裁与防倒退（Anti-Rollback）**：针对多控制节点可能存在配置不一致或网络脑裂问题，控制节点对外暴露精确版本指纹（含 Flake `lastModified` 秒级时间戳、Git Commit Hash 与 Nixpkgs 提交版本号，即便在未 Commit 的 Dirty 状态也能精准比对）；边缘节点动态选举最新存活的控制节点，并执行单调防倒退保护。
5. **动态规则下发与完全无限制的极致性能释放**：边缘节点本地不硬编码任何回源规则，全量规则由控制平面动态推送与平滑热更；同时**彻底剔除任何 cgroup 资源与性能配额限制**，全速跑满硬件线速性能。

---

### 1.1 系统架构全景图

```
                         [ 互联网终端用户 Client ]
                                    |
          1. DNS / DoH 智能解析请求   |  2. GeoIP2 / Anycast 最优边缘节点 IP
                                    v
          +---------------------------------------------------+
           |         Traffic Router (DNS & HTTP Steering)            | <-----+
          |        (智能调度面 / 区域优选 / 加权轮询调度)        |       |
          +---------------------------------------------------+       |
                                    |                                 | 3. 健康拓扑上报
                                    v                                 |    与路由表重算
          +---------------------------------------------------+       |
          |                  Traffic Monitor                  | ------+
          |             (健康状态主动嗅探与可用性感知)            |
          +---------------------------------------------------+
                                    ^
                                    | 持续探测 (HTTP / Ping)
                                    v
+-------------------------------------------------------------------------------+
|                           分布式边缘缓存集群 (Edge Tier)                        |
|                                                                               |
|  [ 欧美边缘: fra1 ]    [ 东亚边缘: tyo0 ]    [ 港澳边缘: hkg0 ]    [ 港澳边缘: hkg5 ]  |
|  +----------------+    +----------------+    +----------------+    +----------------+ |
|  | ATS 缓存代理   |    | ATS 缓存代理   |    | ATS 缓存代理   |    | ATS 缓存代理   | |
|  | 全速性能释放   |    | 全速性能释放   |    | 全速性能释放   |    | 全速性能释放   | |
|  | /var/lib/可写  |    | /var/lib/可写  |    | /var/lib/可写  |    | /var/lib/可写  | |
|  +----------------+    +----------------+    +----------------+    +----------------+ |
|          ^                     ^                     ^                     ^          |
|          |                     |                     |                     |          |
+----------|---------------------|---------------------|---------------------|----------+
           | 5. 动态探活选优与增量同步 (t3c syncds / Anti-Rollback Version Election)   |
           +---------------------+---------------------+---------------------+
                                 |
                                 v
          +---------------------------------------------------------+
          |            控制平面高可用集群 (Control Plane HA)          |
          |                                                         |
          |  [ 控制主节点: fra0 ]        [ 备用控制节点: 预留扩容 ]     |
          |  +--------------------+      +--------------------+     |
          |  | Traffic Ops API    |      | Traffic Ops API    |     |
          |  | Version Metadata   |      | Version Metadata   |     |
          |  | PostgreSQL         | <--> | PostgreSQL 复制    |     |
          |  +--------------------+      +--------------------+     |
          +---------------------------------------------------------+
                                 ^
                                 | 统一声明式编排 & Queue Updates 触发
                                 |
                   +----------------------------+
                   |   Terraform 统一交付编排    |
                   | (terraform/cdn.tf 声明业务) |
                   +----------------------------+
                                 |
                                 v 回源请求 (Cache Miss / TLS Passthrough)
                   +---------------------------------------+
                   |         业务源站集群 (Origin Tier)     |
                   | (Jellyfin, Alist, Cloud, Code on fra0)|
                   +---------------------------------------+
```

---

### 1.2 五层架构分工与职责边界

| 架构层级                             | 核心组件与模块路径                                                                                | 核心职责与设计边界                                                                                                                                                                                                                                                                                        |
| :----------------------------------- | :------------------------------------------------------------------------------------------------ | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **1. 交付管理层 (Delivery Plane)**   | `terraform/cdn.tf`<br>`lib/data/data.json`                                                        | **全局唯一的配置入口**：集中声明控制节点列表（`cdn_control_nodes`）、边缘节点列表（`cdn_edge_nodes`）与业务加速映射（`cdn_services`）。自动编排 Cloudflare DNS，触发 Traffic Ops 变更队列。                                                                                                               |
| **2. 控制管理层 (Control Plane)**    | `nixos/modules/services/atc/ops.nix`<br>`pkgs/trafficcontrol`                                     | **元数据、凭据与版本中枢**：运行 `traffic_ops_golang`；存储服务器拓扑、Delivery Services 映射与基线 Profile；提供 HTTP `/version.json` 端点供边缘节点进行版本仲裁；管理只读同步凭据 `t3c-sync`。                                                                                                          |
| **3. 智能调度层 (Routing Plane)**    | `nixos/modules/services/atc/router.nix`<br>`nixos/modules/services/atc/monitor.nix`               | **流量牵引与可用性感知**：Traffic Monitor 持续嗅探边缘健康；Traffic Router 搭载 MaxMind GeoIP2 库与 ATC 动态拓扑，实现客户端就近解析与异常节点秒级摘除；**DNS Steering（53 端口）与 HTTP Steering（80 端口）互补共存，非二选一**，默认仅启用 DNS 模式，HTTP 模式按需开启。                                |
| **4. 边缘数据层 (Data Plane)**       | `nixos/modules/services/atc/edge.nix`<br>`pkgs/trafficcontrol.t3c`<br>Apache Traffic Server (ATS) | **全速分级缓存与热重载代理**：执行 L7 请求路由、静态文件多级缓存（RAM/Disk）与回源连接复用；彻底解耦 Nix Store，配置全可写化并支持进程不中断热重载；**全量释放 VPS 计算性能，无任何 cgroup 限制**。边缘节点仅拉取轻量级 `trafficcontrol.t3c` 输出，避免中心端 Web 静态资源与 Perl/Go 依赖进入边缘依赖树。 |
| **5. 传输加速层 (Transport Tuning)** | `nixos/modules/services/atc/tuning.nix`                                                           | **跨大洲高 BDP 链路单边加速**：启用内核 FQ + BBR 拥塞控制；增大 TCP 读写滑动窗口至 64MB；启用 RACK 与 TLP 快速重传；提供网络接口 MSS 钳制，消除 Bufferbloat 与丢包断流。                                                                                                                                  |

---

## 二、 核心机制设计：单一入口、多控制面与版本仲裁

### 2.1 零逻辑硬编码：所有机器配置收敛于 `terraform/cdn.tf`

为确保系统可复用，未来增删节点或更换控制节点机器时，**严禁修改任何 Nix 代码逻辑**。所有配置全部收敛在 `terraform/cdn.tf` 的 `locals` 块中：

```hcl
locals {
  # ── 控制平面节点列表 (Control Plane Nodes) ──────────────────────────────────
  # 运行 Traffic Ops API、Traffic Monitor 以及智能权威 DNS (Traffic Router)
  # 目前为 ["fra0"]，代码架构预留支持扩展多个控制节点以实现多中心高可用容灾
  cdn_control_nodes = ["fra0"]

  # ── 智能调度 DNS 权威服务器 (Authoritative NS Hosts) ─────────────────────────
  cdn_ns_hosts = local.cdn_control_nodes
  cdn_ns_host  = local.cdn_ns_hosts[0]

  # ── 边缘加速节点列表 (Edge Cache Nodes) ────────────────────────────────────
  # 运行 Apache Traffic Server (ATS) 高速缓存代理与 t3c 动态热同步 Agent
  # 当前指定节点：fra1, tyo0, hkg0, hkg5 (tyo1 因运营商硬件严格限制性能已排除)
  cdn_edge_nodes = [
    {
      name   = "fra1"
      region = "EU"
      weight = 10
    },
    {
      name   = "tyo0"
      region = "AP"
      weight = 5
    },
    {
      name   = "hkg0"
      region = "HK"
      weight = 8
    },
    {
      name   = "hkg5"
      region = "HK"
      weight = 8
    },
  ]

  # ── 加速业务映射 (Accelerated Services) ──────────────────────────────────────
  # 子域名映射 -> 真实后端源站主机名 (全部通过源站集群回源)
  cdn_services = {
    jellyfin = "fra0"
    zone     = "fra0"
    alist    = "fra0"
    office   = "fra0"
    code     = "fra0"
    cloud    = "fra0"
    m        = "fra0"
    chat     = "fra0"
    mcp      = "fra0"
    s        = "fra0"
    persona  = "fra0"
    bot      = "fra0"
    napcat   = "fra0"
  }
}
```

#### 自动化管线流转机制

1. Terraform 导出包含控制节点、边缘节点 IP 与服务列表的 `cdn_data` 输出；
2. 提取脚本自动更新 `lib/data/data.json`；
3. NixOS 全局模块 `nixos/modules/services/atc/roles.nix` 自动将当前机器的 `networking.hostName` 与 `controlNodeNames` / `edgeNodeNames` 进行匹配：
   - 匹配为控制节点：自动开启 `ops`, `monitor`, `router`, `tuning`，自动关闭 `edge`；
   - 匹配为边缘节点：自动开启 `edge`, `tuning`，自动关闭控制面组件；
   - 既不是控制节点也不是边缘节点（例如 `tyo1`, `arx8`）：自动全面禁用 `services.atc.*`。
4. **交付结果**：未来即便更换机器（如新增 `ams0`、将 `fra0` 迁移到 `fra2`），只需在 `cdn.tf` 中修改名称与 IP，全部节点自适应应用，无任何手工调整。

---

### 2.2 优雅控制面寻址：解耦特定主机名，预留多控制节点空间

传统架构将边缘节点的同步目标写死为 `fra0.dora.im`，一旦控制节点更迭或迁移，全部边缘节点将集体失联。

本架构采用**高可用控制域与多候选节点动态选举**方案：

1. **虚拟控制域名（Virtual Control Domain）**：统一使用 `ops.${domain}`（如 `ops.dora.im`）作为通用控制面入口，由 Cloudflare CNAME 指向当前活跃的控制节点（`fra0.dora.im`）。
2. **多节点直连回退（Direct IP / Node Fallback）**：边缘节点在启动时，根据 `lib/data/data.json` 自动将所有控制节点的真实 IP 写入本地 `/etc/hosts`：
   ```
   94.249.174.75 ops.dora.im fra0-ops.dora.im
   ```
   即使公网 DNS 发生解析抖动或递归服务器故障，边缘节点依然能通过内置 IP 链路直连控制集群。
3. **多控制中心高可用（Multi-Controller HA）**：
   在 `cdn.tf` 的 `cdn_control_nodes` 中增加新控制节点（如 `["fra0", "fra2"]`）后：
   - 边缘节点的 t3c 同步脚本会自动将其加入候选探测队列；
   - Traffic Router 需配合外部负载均衡（Cloudflare NS 轮询 / BGP Anycast / HAProxy）实现多活，避免单点故障。

#### 控制节点迁移流程（零边缘节点改动）

当需要将控制节点从 `fra0` 迁移到 `fra2` 时：

1. 在 `terraform/cdn.tf` 中修改 `cdn_control_nodes = ["fra2"]`；
2. 修改 Cloudflare CNAME：`ops.dora.im → fra2.dora.im`；
3. 在 `fra2` 上部署完整的 ATC 控制平面（ops + monitor + router）；
4. **边缘节点零改动，自动探测到新控制节点并开始同步**。

---

### 2.3 基于 Git Commit Hash 与 Flake 时间戳的版本仲裁与防倒退机制

当集群存在多个控制节点，或者控制节点处于构建更新过渡期时，控制节点之间可能产生版本差异。边缘节点若盲目连接，会导致配置在新旧版本之间反复“拉扯”震荡。

#### 1. 控制端精确版本指纹导出 (`/version.json`)

控制节点伴生运行独立的轻量元数据微服务（端口 8083，由 Traefik 挂载于 `https://ops.dora.im/version.json`），对外输出结构化版本信息：

```json
{
  "host": "fra0",
  "epoch": 1792742523,
  "gitRev": "fe13242281a67641c0102cdb1087f0ebe586c7df",
  "shortRev": "fe132422",
  "nixosVersion": "26.11.20261015.fe13242",
  "label": "26.11.20261015.fe13242",
  "fingerprint": "1792742523-fe132422-26.11.20261015.fe13242"
}
```

- **单调递增时间戳（`epoch`）**：采用 Flake 的 `self.lastModified`。**即便仓库处于未 Commit 的 Dirty 状态，只要代码或配置文件被修改，Flake 的 `lastModified` 就会单调增加**，完美解决了无 Git Commit 时的版本识别难题。
- **Git 提交哈希（`gitRev` / `shortRev`）**：当仓库完成 Commit 后，精确输出 Git 提交散列值。
- **Nixpkgs 官方基准版本号（`nixosVersion`）**：携带形如 `26.11.20261015.fe13242` 的上游提交标识。

#### 2. 边缘端动态选举与防倒退算法 (Anti-Rollback Election)

边缘节点在每轮 30 秒同步周期中，执行以下步骤：

1. **多节点探活与元数据收集**：并发探测所有候选控制节点的 `/version.json`，提取各自的 `epoch` 与指纹。
2. **最新版本仲裁（Highest-Epoch Election）**：选出存活且 `epoch` 最大的控制节点作为本轮唯一同步源。
3. **单调防倒退校验（Anti-Rollback Check）**：
   - 边缘节点在本地持久化记录已成功应用的版本：`/var/lib/trafficcontrol-cache-config/applied_epoch`；
   - 若当前选举出的控制节点 `epoch` 小于本地已记录的 `applied_epoch`，说明当前控制节点配置发生倒退（例如网络分区导致连接到了尚未同步完成的旧备机），边缘节点**立即中止同步并告警，坚决保持现有新配置不被降级回滚**；
4. **安全应用与状态更新**：仅当控制节点 `epoch >= applied_epoch` 时，才调用 `t3c apply` 下发并更新记录。

---

### 2.4 边缘性能全量释放：零 cgroup 性能扼杀

由于 CDN 边缘节点核心职责是承载高并发网络 IO、大容量静态资源缓存与吞吐转发，对系统吞吐量和内存带宽极其敏感。

根据架构要求，系统**彻底剔除任何对边缘性能的人为限制**：

1. **移除 cgroup 限制**：移除 `atc-t3c-sync` 与 `trafficserver` 的 `MemoryHigh`, `MemoryMax`, `CPUQuota` 等限额，允许同步进程在解析超大规模规则集时突发使用全部 CPU 与内存，避免因 OOM 杀死同步导致配置停滞。
2. **内核 TCP 栈深层性能释放 (`tuning.nix`)**：
   - 全面启用 **FQ + BBR** 拥塞控制算法；
   - `net.core.rmem_max` 与 `wmem_max` 提升至 **64 MiB**，撑满跨大洲高时延高带宽（High-BDP）链路；
   - 启用 RACK (RFC 8985) 与 Tail Loss Probe (TLP)，在突发网络丢包时将重传延迟降至毫秒级；
   - 连接队列 `somaxconn` 提升至 32768，`tcp_max_syn_backlog` 提升至 8192，防止突发流量洪峰造成 SYN 丢包。

---

## 三、 核心子系统实现细节

### 3.1 中心控制面与元数据大脑 (`nixos/modules/services/atc/ops.nix`)

Traffic Ops 作为 CDN 的控制中枢，负责承载全网拓扑数据、凭据鉴权以及配置文件的渲染模板。

#### 1. 自动数据库初始化与全量业务注入 (`traffic-ops-init.service`)

在服务启动前，自动执行幂等初始化脚本：

- 严格应用上游数据库迁移表结构，修正 ATC 8.0.2 中 Delivery Service `active` 状态的 enum 兼容性；
- 采用 Traffic Ops 原生 SCRYPT 算法生成只读用户 `t3c-sync` 的安全凭据；
- **声明式自动注册**：根据 `cdn.tf` 导出的业务清单，自动向数据库灌入所有 Delivery Services、HOST_REGEXP 正则匹配表、源站 Origin 实体，以及将 Delivery Services 绑定到所有声明的边缘缓存节点。

#### 2. 安全凭据隔离与运行时配置注入

- 禁止将签名密钥和数据库密码写入任何人可读的 `/nix/store`。
- `traffic-ops.service` 在 `preStart` 阶段从 SOPS 密钥树读取密码，使用 `jq` 动态生成仅进程所属用户（`trafficops:trafficops`，权限 `0600`）可读的 `/etc/traffic_ops/cdn.conf`。
- 本地生成自签名 TLS 证书供后端监听，由 Traefik 在公网统一挂载 Let's Encrypt 证书并终结外部 TLS。

---

### 3.2 边缘数据面与动态同步 (`nixos/modules/services/atc/edge.nix`)

#### 1. Nix Store 只读与动态更新的彻底解耦

- 在 NixOS 模块中显式注销只读软链：
  ```nix
  environment.etc."trafficserver/remap.config".enable = false;
  ```
- 将 ATS 配置基座定位在可写路径 `/var/lib/trafficserver/etc`。
- 在 `systemd.services.trafficserver.preStart` 中完成目录自愈与种子文件释放：初次启动若无 `remap.config` 则创建空文件，软链接 `/etc/trafficserver/remap.config -> /var/lib/trafficserver/etc/remap.config`，并将整树所有权委托给 `trafficserver:trafficserver` 用户。

#### 2. 轻量级 t3c 边缘依赖 (`pkgs/trafficcontrol`)

- `pkgs/trafficcontrol` 声明多输出包：
  - `$out`：完整包，包含 `traffic_ops_golang`、`traffic_monitor`、数据库 schema 与静态资源，供控制节点使用；
  - `$t3c`：仅包含 `t3c`、`t3c-apply`、`t3c-check` 等边缘同步客户端二进制，供边缘节点使用。
- 边缘节点通过 `trafficcontrol.t3c` 输出引用，系统 `PATH` 仅注入必要的 t3c 工具链，边缘节点 Nix 闭包完全不包含中心端 Web 服务与 Perl 运行时依赖。

#### 3. 安全凭据传递

- `atc-t3c-sync` 服务通过 `--traffic-ops-password-file` 直接将 SOPS 解密后的密码文件路径传递给 `t3c apply`，避免密码出现在进程环境变量或 `systemd` journal 中。
- 密码文件权限严格限制为 `trafficserver:trafficserver` `0400`，确保只有同步服务进程可读。

#### 4. 平滑热重载 (Hitless Dynamic Reload)

当控制平面更新规则并触发 Queue Updates 后：

1. `t3c apply --run-mode=syncds` 捕获差异；
2. 原子写入 `/var/lib/trafficserver/etc/remap.config`；
3. 执行 `traffic_ctl config reload` 通知 ATS 内部重载；
4. **ATS 主进程 PID 保持不变，存量 TCP 长连接与传输会话零中断，新请求瞬时走新路由规则**。

#### 5. 边缘节点接入层：Traefik TLS 终结与端口分配

边缘节点 Traefik 负责外部 TLS 终结，配置**一次部署，终生不动**：

| 端口    | 行为                                            | 目标                    |
| :------ | :---------------------------------------------- | :---------------------- |
| **80**  | HTTP → HTTPS **302 重定向**，不反代任何业务流量 | 强制客户端使用 HTTPS    |
| **443** | TLS 终结后转发至 ATS                            | `http://127.0.0.1:8089` |

关键设计：

- **80 端口不写任何源站逻辑**，纯重定向，边缘节点无需知道源站地址；
- **443 端口只做 TLS 终结和转发**，回源规则由 t3c 动态下发到 ATS；
- 所有业务域名通过 `Host(`${s}.${config.networking.domain}`)` 规则匹配；
- 边缘节点一次部署后，**终生不需要重新更新任何配置**，所有规则从控制节点自动获取。

---

### 3.3 智能调度与权威 DNS 面 (`nixos/modules/services/atc/router.nix`)

本架构中的 Traffic Router 调度引擎由 **CoreDNS + `atc-dynamic-dns` 动态健康感知器** 驱动，兼具极致轻量（15MB 内存，5ms 启动）与企业级故障自动摘除能力。

#### 1. 动态健康感知与秒级故障摘除 (`atc-dynamic-dns`)

传统静态 DNS 在边缘节点下线或网络断流时仍会盲目返回故障 IP，导致客户端白屏超时。本架构实现完整的端到端动态感知闭环：

```text
       Traffic Monitor (fra0)
              │
              │ 1. 周期性 (20s) 嗅探各边缘节点 ATS /_astats
              │    (测量 HTTP 可用性与 connection_time 时延)
              ▼
   /var/lib/traffic_monitor/crconfig.backup
              │
              │ 2. atc-dynamic-dns 定时器 (每 10s 触发)
              │    ├── 过滤在线节点 (status == "REPORTED")
              │    ├── 剔除下线节点 (如 hkg0 断流直接移出 DNS)
              │    └── 性能加权展开 (高权重节点 A 记录频次更高)
              ▼
    /var/lib/traffic_router/cdn.dora.im.zone
              │
              │ 3. CoreDNS file 插件 (reload 5s)
              ▼
      CoreDNS 53 端口 (fra0:53)
              │
              │ 4. 返回全球 DNS 应答 (仅含存活边缘节点)
              ▼
        客户端浏览器
```

- **故障摘除时效**：边缘节点一旦断流或 ATS 崩溃，Traffic Monitor 在 20 秒内标记为 UNAVAILABLE，`atc-dynamic-dns` 在 10 秒内生成新 zone，CoreDNS 5 秒内热重载生效，总感知摘除延迟 $< 35$ 秒。
- **极端冷启动兜底**：若控制节点冷启动且 Traffic Monitor 尚未完成首轮探测，脚本自动回退至 `data.json` 中的全部配置边缘节点，确保 DNS 解析**绝不返回空记录，永远保持服务可用**。

#### 2. 调度模式选型与客户端选路流程

针对国内网络环境到海外控制节点（`fra0`）延迟高且不稳定的物理现实，**全面采用「纯 DNS 智能调度」作为主访问路径**：

| 调度模式                       | 客户端链路                                        | 额外 RTT         | 对弱网友好度                               | 适用场景                        |
| :----------------------------- | :------------------------------------------------ | :--------------- | :----------------------------------------- | :------------------------------ |
| **DNS Steering (核心主线)**    | 查 DNS (fra0:53) → **直接访问就近边缘:443**       | **0 次额外 RTT** | **极高** (直连香港/日本边缘，不走控制节点) | 所有 Web、API、媒体流与静态资源 |
| **HTTP 302 Steering (重定向)** | 连控制节点:80 → 302 → 连控制节点:443 → 302 → 边缘 | 2~3 次欧洲 RTT   | 极差 (国内首包延迟将高达 800ms+)           | 仅用于无法配置 DNS 的特殊客户端 |

**为什么选择 DNS Steering 作为唯一推荐主线？**

1. **零控制节点数据面参与**：用户输入 `https://cloud.dora.im/`，浏览器通过 DNS 解析出边缘节点 IP（如香港 `hkg5` 的 `216.23.94.148`），**后续所有 TLS 握手、HTTP/2 会话、Nextcloud 登录与文件下载全在香港边缘节点完成**，数据流量完全不经过欧洲控制节点 `fra0`！
2. **彻底消灭多重 302 跳转**：消除了“控制端 80 端口 302 到 443，443 再 302 到加速节点”的冗余等待，首次访问秒开。

#### 3. 端口划分与服务无冲突共存

控制节点（`fra0`）与边缘节点严格分离端口职责：

| 节点                      | 服务组件                   | 监听端口         | 监听地址                  | 职责说明                                            |
| :------------------------ | :------------------------- | :--------------- | :------------------------ | :-------------------------------------------------- |
| **控制节点 (fra0)**       | CoreDNS (`traffic-router`) | **53** (UDP/TCP) | 公网 IP (`94.249.174.75`) | 全球权威 DNS，仅提供 `cdn.dora.im` 解析             |
| **控制节点 (fra0)**       | Traefik                    | **80 / 443**     | `0.0.0.0`                 | 控制面 HTTPS (`ops.dora.im`) 与 Web 证书终结        |
| **控制节点 (fra0)**       | Traffic Ops                | **8084**         | `127.0.0.1`               | ATC Golang API 中枢                                 |
| **控制节点 (fra0)**       | Traffic Monitor            | **8087**         | `127.0.0.1`               | 边缘健康探测引擎与状态发布                          |
| **边缘节点 (fra1..hkg5)** | Traefik                    | **80**           | `0.0.0.0`                 | 内部转发 `/_astats` 给 ATS；普通业务纯 302 到 HTTPS |
| **边缘节点 (fra1..hkg5)** | Traefik                    | **443**          | `0.0.0.0`                 | 终结各业务域名 TLS，反代至本机 ATS:8089             |
| **边缘节点 (fra1..hkg5)** | ATS                        | **8089**         | `127.0.0.1`               | 高速缓存引擎，按 t3c 动态下发的 remap 规则回源      |

---

## 四、 运维操作实战指南

### 4.1 业务域名声明式接入流程

在本架构中，**接入新域名或调整回源源站仅需修改 `terraform/cdn.tf` 一个文件**：

1. 打开 `terraform/cdn.tf`，在 `local.cdn_services` 字典中添加一行：
   ```hcl
   cdn_services = {
     jellyfin = "fra0"
     alist    = "fra0"
     code     = "fra0"
     newapp   = "fra0"   # 新增服务：映射为 newapp.dora.im -> 源站 fra0.dora.im
   }
   ```
2. 执行部署：
   ```bash
   nix develop --command terraform apply
   ```
3. **自动化全流程**：
   - Terraform 自动为 `newapp.dora.im` 创建指向 `newapp.cdn.dora.im` 的 Cloudflare CNAME 记录；
   - API 编排器自动在 Traffic Ops 中创建对应 Delivery Service 并下发更新队列；
   - 30 秒内，全球边缘节点的 `atc-t3c-sync` 自动同步最新 `remap.config` 并平滑热重载，全网零重部署生效。

---

### 4.2 边缘节点扩缩容指南

若需要增加新的边缘加速节点（例如新增 `sjc0`）或淘汰节点：

1. **唯一修改点**：打开 `terraform/cdn.tf`，在 `local.cdn_edge_nodes` 列表中注册或删除节点：
   ```hcl
   cdn_edge_nodes = [
     {
       name   = "fra1"
       region = "EU"
       weight = 10
     },
     {
       name   = "sjc0"  # 新增节点
       region = "US"
       weight = 10
     },
   ]
   ```
2. **无需修改主机代码**：无需打开 `nixos/hosts/sjc0/default.nix` 写任何 `imports = [...]`，全局 `roles.nix` 会在下一次部署时自动识别并开启 `services.atc.edge`。
3. **部署目标机器**：
   ```bash
   colmena apply --on sjc0
   ```
   节点启动后自动探活控制面并拉取最新全局路由表。

#### 4. 验证 Traffic Router 动态故障摘除

在控制节点（`fra0`）执行：

```bash
# 检查 Traffic Router 是否运行
systemctl status traffic-router.service

# 查看 Traffic Monitor 中的边缘节点健康状态
cat /var/lib/traffic_monitor/crconfig.backup | jq '.cdn.caches[] | {host_name, status, health}'

# 查看 Traffic Router 日志
journalctl -u traffic-router.service -n 50 --no-pager
```

预期输出：

- Traffic Router 成功连接 Traffic Ops 并获取 CDN 拓扑
- `crconfig.backup` 中在线节点 `health` 为 `ONLINE`，离线节点为 `OFFLINE`
- Traffic Router 自动将离线节点从 DNS 路由表中摘除
- 当边缘节点离线后，20~30 秒内 DNS 响应不再包含该节点 IP

```bash
# 客户端验证 DNS 解析
dig +short cloud.cdn.dora.im
# 应仅返回在线边缘节点的 IP
```

---

## 五、 验证与排障速查表 (Verification & Troubleshooting)

### 5.1 端到端实测验证（真实生产环境测试结果）

测试客户端：`arx8`
实测边缘节点：`hkg5` (IP: `216.23.94.148`)
控制平面与源站：`fra0`

#### 1. 验证控制平面版本端点

```bash
curl -sk https://ops.dora.im/version.json | jq .
```

预期输出：包含 `epoch`, `gitRev`, `fingerprint` 与 `nixosVersion` 的有效 JSON。

#### 2. 验证边缘节点同步状态与配置热更新

在边缘节点（如 `hkg5`）执行：

```bash
systemctl status atc-t3c-sync.timer
journalctl -u atc-t3c-sync.service -n 20 --no-pager
```

输出显示：

```
Synchronizing configuration from active controller: ops.dora.im (version: ..., epoch: ...)
Traffic Ops requires an update and it was applied successfully. Clearing update state in Traffic Ops.
```

#### 3. 验证业务通过边缘节点高速缓存与反代回源

从客户端（`arx8`）执行各域名探测：

```bash
for d in alist cloud jellyfin code; do
  curl -4skI --resolve "$d.dora.im:443:216.23.94.148" "https://$d.dora.im/"
done
```

实测全部返回 **`HTTP/2 200 OK`**，并且携带 **`server: ATS/9.2.11`** 响应头：

```http
HTTP/2 200
age: 0
server: ATS/9.2.11
content-type: text/html; charset=utf-8
strict-transport-security: max-age=63072000; includeSubDomains
```

该测试结果证实：

- 客户端（`arx8`）请求成功抵达边缘节点（`hkg5`）；
- 边缘节点 Traefik 顺利终结外部 TLS 握手并转发至本机 ATS（端口 `8089`）；
- ATS 根据 `t3c` 动态下发的 `remap.config` 命中规则；
- ATS 建立 HTTPS 隧道回源源站（`fra0`）；
- 响应完整返回客户端，整个 CDN L7 缓存回源闭环 100% 成功。

---

### 5.2 常见排障排错速查表

| 故障现象                                                                | 潜在根因                                                      | 排查与修复步骤                                                                                                                                                                                  |
| :---------------------------------------------------------------------- | :------------------------------------------------------------ | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `t3c apply` 报 `Read-only file system`                                  | `remap.config` 仍指向 `/nix/store` 路径                       | 检查 `edge.nix` 中 `environment.etc."trafficserver/remap.config".enable = false;` 是否生效；检查 preStart 是否正确创建可写目录。                                                                |
| `atc-t3c-sync` 报 `401 Unauthorized`                                    | `t3c-sync` 用户凭据不匹配或未在 Traffic Ops 初始化            | 1. 检查 `secrets/common.yaml` 中的 `atc.ops_password`；<br>2. 在中心节点检查 `traffic-ops-init.service` 日志，确认 SQL 种子是否成功灌入 PostgreSQL 的 `tm_user` 表。                            |
| `atc-t3c-sync` 报 `403 Forbidden` (`sslkeys` 或 `server update`)        | Upstream 默认路由权限要求过高（Admin / Operations）           | 检查 `pkgs/trafficcontrol/default.nix`，确保已对 `sslkeys` 与 `servers/{id}/update` 授予 ReadOnly 级别放行。                                                                                    |
| `remap.config failed to load: unable to open dscp/set_dscp_0.config`    | ATS 插件配置目录未关联                                        | 检查 `/var/lib/trafficserver/etc/dscp/set_dscp_0.config` 是否存在，以及 `/etc/trafficserver/dscp` 软链接是否就绪。                                                                              |
| `atc-t3c-sync` 提示 `All Traffic Ops control endpoints are unreachable` | 控制节点公网 DNS 未发布或端口未放行                           | 检查 `edge.nix` 的 `networking.extraHosts` 是否已注入控制节点 IP；检查控制节点 Traefik HTTPS 代理与 8084 端口。                                                                                 |
| 边缘节点提示 `Skipping sync to prevent rollback`                        | 探测到的控制节点 `epoch` 小于本地记录                         | 说明连接到的控制节点版本落后于历史记录；检查是否有未更新的旧控制节点在响应，或检查当前控制节点的系统构建时间戳。                                                                                |
| CDN 域名返回 404                                                        | 请求命中了未运行 ATS 的非边缘节点，或 Delivery Service 未同步 | 确认 `cdn.tf` 的 `cdn_edge_nodes` 仅包含当前运行 ATS 的节点；检查 Traffic Ops 中是否有对应的 Delivery Service 记录。                                                                            |
| DNS 仍返回离线节点 IP                                                   | Traffic Router 未更新或 Traffic Monitor 未探测                | 1. 检查 `traffic-monitor.service` 是否运行；<br>2. 检查 `crconfig.backup` 中节点健康状态；<br>3. 检查 `traffic-router.service` 日志；<br>4. 确认 Traffic Router 已连接 Traffic Ops 并获取拓扑。 |
