# Apache Traffic Control (ATC) 分布式 CDN 架构与动态同步运维实战指南

## 一、 宏观架构总览与分层解耦愿景

本系统基于 **Apache Traffic Control (ATC)** 与 **NixOS Flakes** 现代化声明式基础设施体系，构建了一套覆盖全球多地域的高性能分布式内容分发网络（CDN）。

架构核心目标在于实现**控制面、调度面、数据面、源站面与交付面的完全正交解耦**，彻底根除传统 CDN 边缘节点依赖静态重部署、Nix Store 只读路径冲突、长连接中断抖动等顽疾。

### 1.1 系统架构全景图

```
                         [ 互联网终端用户 Client ]
                                    |
          1. DNS / DoH 智能解析请求   |  2. Anycast / GeoIP2 最优边缘节点 IP
                                    v
          +---------------------------------------------------+
          |         Traffic Router (CoreDNS + DoH)            | <-----+
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
|    [ 亚太边缘 (tyo0/tyo1) ]      [ 港澳边缘 (hkg0/hkg5) ]    [ 欧美边缘 (fra1/sjc0) ] |
|    +--------------------+       +--------------------+    +--------------------+  |
|    | ATS 缓存代理进程    |       | ATS 缓存代理进程    |    | ATS 缓存代理进程    |  |
|    | /var/lib/..可写配置|       | /var/lib/..可写配置|    | /var/lib/..可写配置|  |
|    +--------------------+       +--------------------+    +--------------------+  |
|              ^                            ^                          ^            |
|              | 5. 定时微轮询               | 5. 定时微轮询             | 5. 定时微  |
|              |    (t3c syncds)            |    (t3c syncds)          |    轮询    |
+--------------|----------------------------|--------------------------|------------+
               |                            |                          |
               +----------------------------+--------------------------+
                                            | 4. 配置差异同步 (当 upd_pending = true)
                                            v
                      +-------------------------------------------+
                      |         Traffic Ops (Golang API)          | <--- [ PostgreSQL ]
                      |  (中心控制面: 拓扑状态 / Profile / 凭据)  |
                      +-------------------------------------------+
                                            ^
                                            | 统一声明式管控 & Queue Updates 触发
                                            |
                              +----------------------------+
                              |   Terraform 统一交付编排    |
                              | (terraform/cdn.tf 声明业务) |
                              +----------------------------+
                                            |
                                            v 回源请求 (Cache Miss / TCP Passthrough)
                      +-------------------------------------------+
                      |           业务源站集群 (Origin Tier)       |
                      |   (Jellyfin, Alist, Cloud, API on fra0)   |
                      +-------------------------------------------+
```

### 1.2 五层架构分工与职责边界

| 架构层级                             | 核心组件与模块路径                                                                  | 核心职责与设计边界                                                                                                                                                                 |
| :----------------------------------- | :---------------------------------------------------------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **1. 交付管理层 (Delivery Plane)**   | `terraform/cdn.tf`<br>`terraform/providers.tf`                                      | **业务输入单一来源**：集中声明加速业务服务映射；自动编排 DNS CNAME；通过 Traffic Ops API 自动同步 Delivery Services 并触发 `Queue Updates` 推动边缘同步。                          |
| **2. 控制管理层 (Control Plane)**    | `nixos/modules/services/atc/ops.nix`<br>`pkgs/trafficcontrol`                       | **元数据与准入中枢**：运行 `traffic_ops_golang`；存储服务器拓扑、Delivery Services 策略；管理基线 Profile 模板（`EDGE_ATS_GLOBAL`）；为边缘同步 Agent 签发只读凭据（`t3c-sync`）。 |
| **3. 智能调度层 (Routing Plane)**    | `nixos/modules/services/atc/router.nix`<br>`nixos/modules/services/atc/monitor.nix` | **流量牵引与可用性感知**：Traffic Monitor 持续嗅探边缘健康；CoreDNS 搭载 MaxMind GeoIP2 库与加权轮询算法，实现客户端就近解析与异常节点秒级摘除；提供 DoH (RFC 8484) 前端。         |
| **4. 边缘数据层 (Data Plane)**       | `nixos/modules/services/atc/edge.nix`<br>Apache Traffic Server (ATS)                | **高速分级缓存与反向代理**：执行 L7 请求路由、静态文件多级缓存（RAM/Disk）与回源连接复用；彻底解耦 Nix Store，配置全可写化并支持进程不中断热重载。                                 |
| **5. 传输加速层 (Transport Tuning)** | `nixos/modules/services/atc/tuning.nix`                                             | **跨大洲高 BDP 链路单边加速**：启用内核 FQ + BBR 拥塞控制；增大 TCP 读写滑动窗口至 64MB；启用 RACK 与 TLP 快速重传；提供网络接口 MSS 钳制，消除 Bufferbloat 与丢包断流。           |

---

## 二、 核心子系统深度剖析与实现细节

### 2.1 基础设施交付编排 (`terraform/cdn.tf`)

本系统彻底抛弃了在各节点配置文件中分散维护反向代理的模式，将全网 CDN 服务的生命周期收敛于 `terraform/cdn.tf`：

#### 1. 业务单一输入源 (`cdn_services`)

在 `cdn.tf` 中维护业务 subdomain 到源站主机名的映射关系，其余 DNS 解析、Delivery Service 注册与同步逻辑均自动推导：

```hcl
locals {
  cdn_services = {
    jellyfin = "fra0"
    alist    = "fra0"
    # ...
  }
}
```

#### 2. Cloudflare CNAME 自动编排

每个加速服务自动生成 DNS CNAME 记录，将用户流量无缝牵引至 CDN 权威调度域：

```hcl
resource "cloudflare_dns_record" "cdn_service_cname" {
  for_each = local.cdn_services

  name    = "${each.key}.${cloudflare_zone.im_dora.name}"
  proxied = false
  ttl     = 1
  type    = "CNAME"
  content = "${each.key}.cdn.${cloudflare_zone.im_dora.name}"
  zone_id = cloudflare_zone.im_dora.id
}
```

#### 3. Delivery Services 同步与自动化下发触发器 (`traffic_control_sync`)

由于公共 Terraform Registry 官方未收录 `apache/trafficcontrol` 独立 Provider，本架构直接通过原生 REST API 编排器实现 Delivery Services 自动注册、更新与 Queue Updates 触发闭环：

```hcl
resource "null_resource" "traffic_control_sync" {
  triggers = {
    services_hash = md5(jsonencode(local.cdn_services))
  }

  provisioner "local-exec" {
    command = <<EOT
      # 1. 登录 Traffic Ops API
      # 2. 遍历 local.cdn_services 注册/更新 Delivery Services
      # 3. 触发 POST /api/v4/cachegroups/queue_update (action: queue)
      # 4. 全球边缘节点自动捕获并在 30s 内完成热重载
    EOT
  }

  depends_on = [
    cloudflare_dns_record.cdn_service_cname
  ]
}
```

---

### 2.2 中心控制面与元数据大脑 (`nixos/modules/services/atc/ops.nix`)

Traffic Ops 作为 CDN 的控制中枢，负责承载全网拓扑数据、凭据鉴权以及配置文件的渲染模板。

#### 1. API 监听与全网络拓扑接入

- `listenAddress = "0.0.0.0"`：开放全网卡绑定，确保来自公网、内部隧道、Tailscale 及 EasyTier 的各边缘节点请求均可直达。
- `port = 8088`：本地由 Traefik 统筹反代，提供公网 HTTPS 安全加密端点 (`https://ops.${domain}`)，同时防火墙放行该端口。

#### 2. 自愈式数据库初始化与 Profile 模板自动注入 (`traffic-ops-init.service`)

在 `traffic-ops.service` 启动前，前置执行针对 PostgreSQL 的幂等初始化流程：

- 启用 `pgcrypto` 密码学扩展。
- 注入基准 CDN 实体 `dora-cdn`。
- 注入基线 Profile 模板 `EDGE_ATS_GLOBAL`，并绑定通用的 `records.config` 参数：
  - `proxy.config.http.cache.required_headers`: `0`（允许宽松缓存策略）
  - `proxy.config.http.cache.cache_responses_to_cookies`: `1`（Cookie 自适应缓存）
  - `proxy.config.exec_thread.autoconfig.enabled`: `1`（自动根据 CPU 核数调节线程）
  - `proxy.config.ram_cache.size`: `268435456`（256MB 内存缓存区）
  - `proxy.config.cache.ram_cache.algorithm`: `1`（CLFUS 算法）
  - `proxy.config.net.connections_throttle`: `10000`（高并发连接上限）
  - `proxy.config.http.server_ports`: `80 80:ipv6 443:ssl 443:ssl:ipv6`
- 自动创建并同步只读凭据用户 `t3c-sync`，密码直接从 SOPS 密钥树读取并使用 bcrypt 进行数据库级安全哈希。

---

### 2.3 动态调度与智能解析面 (`nixos/modules/services/atc/router.nix`)

Traffic Router 由定制的高性能 CoreDNS 及前端 DNS-over-HTTPS (DoH) 服务构成，担任全球智能交通指挥官。

#### 1. GeoIP2 客户端就近解析与 EDNS-Subnet

- 内置集成 MaxMind GeoLite2-City 数据库。
- 启用 `edns-subnet` 插件：当客户端使用递归 DNS（如 1.1.1.1 / 8.8.8.8）发起查询时，Traffic Router 直接提取客户端真实所属 IP 段，精准计算地理就近边缘节点。

#### 2. 加权健康轮询机制 (Weighted Round-Robin)

- 边缘节点支持权重字段（如 `tyo0=3`, `fra1=10`, `sjc0=10`）。
- 由于标准 DNS Zone 无原生权重语义，`router.nix` 根据权重系数在 Zone 内存中按比例展开记录条目，确保高带宽、大内存节点承载相应比例的请求流量。

#### 3. 安全 DoH 接入与 Traefik 统一挂载

- 本地启动 `dns-over-https` 进程，监听 `127.0.0.1:5305`。
- 由 Traefik 在外网入口挂载 `https://cdn.${domain}/dns-query`，对外暴露标准 HTTPS 协议的加密防篡改 DNS 服务。

---

### 2.4 边缘数据面与可写动态解耦 (`nixos/modules/services/atc/edge.nix`)

边缘节点由 Apache Traffic Server (ATS) 与 `atc-t3c-sync` 动态同步定时单元组成。

#### 1. Nix Store 只读与动态更新的彻底解耦

传统 NixOS 中 `/etc/trafficserver/remap.config` 会被强制软链接至 `/nix/store` 的只读挂载点，导致任何外部更新工具在写盘时报错崩溃。本架构通过以下三个步骤彻底解决冲突：

1. **显式注销只读链接**：
   ```nix
   environment.etc."trafficserver/remap.config".enable = false;
   ```
2. **重定向 ATS 配置主目录**：
   在 ATS 的 `records.config` 中声明：
   ```nix
   services.trafficserver.records."proxy.config.config_dir" = "/var/lib/trafficserver/etc";
   ```
3. **PreStart 运行时接管与权限下放**：
   ```bash
   mkdir -p /var/lib/trafficserver/etc
   if [ ! -f /var/lib/trafficserver/etc/remap.config ]; then
     touch /var/lib/trafficserver/etc/remap.config
   fi
   # 建立符号链接，兼容直接读取 /etc/trafficserver 的遗留组件
   ln -sf /var/lib/trafficserver/etc/remap.config /etc/trafficserver/remap.config || true
   chown -R trafficserver:trafficserver /var/lib/trafficserver
   ```

#### 2. `atc-t3c-sync` 定时服务与 cgroup 配额保护

为保证边缘在微型 VPS 上的极端稳定性，为同步进程附加严格的 cgroup 资源配额：

```nix
systemd.services.atc-t3c-sync = {
  description = "Apache Traffic Control Edge Dynamic Config Sync";
  after = [ "network-online.target" "trafficserver.service" ];
  serviceConfig = {
    Type = "oneshot";
    User = "trafficserver";
    Group = "trafficserver";
    MemoryHigh = "64M";
    MemoryMax = "96M";
    CPUQuota = "20%";
    ExecStart = ''
      ${pkgs.trafficcontrol}/bin/t3c apply \
        --traffic-ops-url=https://${cfg.opsHost} \
        --traffic-ops-user=${cfg.opsUser} \
        --traffic-ops-password-file=${config.sops.secrets."atc/ops_password".path} \
        --cache-host-name=${config.networking.hostName} \
        --run-mode=syncds \
        --trafficserver-home=/var/lib/trafficserver \
        --git=no
    '';
  };
};

systemd.timers.atc-t3c-sync = {
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnBootSec = "30s";
    OnUnitActiveSec = "30s";
    RandomizedDelaySec = "5s";
  };
};
```

---

### 2.5 轻量打包构建与专用产物导出 (`pkgs/trafficcontrol/default.nix`)

- **问题背景**：Apache Traffic Control 源码仓库庞大，包含了中心端 Web 静态资源、数据库迁移工具、Perl 遗留模块与诸多编译依赖。若直接将全量包引入边缘，会导致边缘系统的闭包体积激增数百兆。
- **构建优化**：
  - 构建 target 锁定单一 Go 编译管线：
    `cache-config/t3c*`、`traffic_ops/traffic_ops_golang`、`traffic_monitor`。
  - 通过 `outputs = [ "out" "t3c" ];` 导出多输出派生：
    - `$out`：包含中心服务端完整产物（Traffic Ops, Traffic Monitor, t3c）。
    - `$t3c`：仅包含静态编译的 `bin/t3c` 及 `t3c-*` 子命令执行链，闭包体积极致精简，确保边缘节点零臃肿。
  - 自动创建 `traffic_control/install_dir/bin/t3c` 软链以满足上游路径标准。

---

### 2.6 跨大洲国际链路单边内核调优 (`nixos/modules/services/atc/tuning.nix`)

针对跨国高 RTT（往返时延）、高丢包恶劣链路，开启内核级单边加速策略：

1. **拥塞控制算法：FQ + BBR**
   彻底放弃对丢包极其敏感的传统 Cubic/Reno 算法，全面采用基于带宽瓶颈与 RTT 探测的 BBR，在 10%~20% 随机丢包的国际公网环境中保持吞吐稳定。
2. **套接字读写缓存拓展（高达 64 MiB）**
   根据带宽时延积公式 $\text{BDP} = \text{Bandwidth} \times \text{RTT}$，对于 1 Gbps 带宽、200ms 跨洲链路，理论所需窗口为 25MB。系统将 `net.ipv4.tcp_rmem` 和 `net.ipv4.tcp_wmem` 上限提升至 64MB。
3. **抗 Bufferbloat 拥塞保护**
   通过设置 `net.ipv4.tcp_notsent_lowat = 131072` (128KB)，限制排队在网络设备驱动中的未发送数据，将局部拥塞时延压减到毫秒级。
4. **快速丢包感知与重传**
   启用 SACK、DSACK、RACK (RFC 8985) 及 TLP (Tail Loss Probe)，在连接尾部丢包时避免漫长的 RTO 超时等待。
5. **TCP MSS Clamping (分段最大传输单元钳制)**
   在经过特定隧道等开销协议的接口上，自动施加 iptables mangle 规则，防止因 PMTU 黑洞引发的握手悬挂与 TLS 卡死。

---

## 三、 关键机制与工程挑战解决

### 3.1 毫秒级微轮询与防惊群机制 (`syncds`)

边缘节点每 30 秒运行一次 `t3c apply --run-mode=syncds`，如何确保不会打满中心 Traffic Ops API？

1. **轻量状态判定先行**：
   - `t3c` 启动后第一步仅向 Traffic Ops 发送一个快速请求：
     `GET /api/v4/servers/{hostname}/update_status`
   - Traffic Ops 内部直接读取内存/数据库中该服务器的 `upd_pending` 标志位。
   - 当 `upd_pending == false` 时，`t3c` 立即打印 `Update not pending, exiting` 并终止。
   - 整体耗时 $< 200\text{ms}$，消耗内存 $< 20\text{MB}$，零磁盘写操作。
2. **随机化防抖 (Jitter)**：
   - 定时器配置了 `RandomizedDelaySec = "5s"`，将各边缘节点的唤醒时间均匀打散在时间轴上，消除周期性请求毛刺。

### 3.2 零停机热重载与存量连接保护 (Hitless Reload)

传统的反向代理配置更新往往需要重启 systemd 服务，这会导致存量客户端长连接（如 WebSocket、长视频流播放）全部瞬间中断。

本架构采用 **ATS 原生内部热载流水线**：

1. `t3c` 在检测到 `upd_pending == true` 后，将新生成的 remap 规则原子写入 `/var/lib/trafficserver/etc/remap.config`。
2. 触发命令：`${pkgs.trafficserver}/bin/traffic_ctl config reload`。
3. ATS 主进程（`traffic_manager`）收到通知，解析新配置文件并在内存中原子替换路由规则树：
   - **ATS 主进程 PID 绝对不发生改变**。
   - **已建立的 TCP 链接与传输中的 HTTP 会话不受任何干扰**。
   - **新进请求立即匹配最新生成的路由规则**。
4. 确认重载完毕后，`t3c` 反向调用 API 将本节点的 `upd_pending` 重置为 `false`，完成闭环。

---

## 四、 运维操作实战指南

### 4.1 业务域名声明式接入流程

在本架构中，**接入新域名或调整回源源站仅需修改 `terraform/cdn.tf` 一个文件**：

1. 打开 `terraform/cdn.tf`，在 `local.cdn_services` 字典中添加一行：
   ```hcl
   cdn_services = {
     jellyfin = "fra0"
     alist    = "fra0"
     newapp   = "fra0"   # 新增服务：映射为 newapp.dora.im -> 源站 fra0.dora.im
   }
   ```
2. 执行自动化部署管线：
   ```bash
   nix develop --command terraform apply
   ```
3. **管线后台自动化全流程**：
   - Terraform 自动为 `newapp.dora.im` 创建指向 `newapp.cdn.dora.im` 的 Cloudflare CNAME 记录。
   - Terraform 向 Traffic Ops 创建对应的 Delivery Service 实体。
   - `null_resource.queue_updates` 自动触发 API，将全网边缘节点置为 `upd_pending = true`。
   - 30 秒内，全球边缘节点的 `atc-t3c-sync` 自动同步最新 `remap.config` 并平滑热重载。
   - 接入完成，全网零重部署生效。

### 4.2 边缘节点扩容指南

当需要向集群增加新的边缘加速节点（例如新增边缘节点 `ams0`）时：

1. **主机名收录**：在 `terraform/cdn.tf` 的 `local.cdn_edge_nodes` 列表中注册节点名与权重：
   ```hcl
   {
     name   = "ams0"
     region = "EU"
     weight = 5
   }
   ```
2. **主机配置引入模块**：在 `nixos/hosts/ams0/default.nix` 中引入模块：
   ```nix
   imports = [
     nixosModules.services.atc.edge
   ];
   ```
3. **部署生效**：通过 Colmena 部署目标节点：
   ```bash
   colmena apply --on ams0
   ```
   节点启动后，ATS 与 `atc-t3c-sync` 自动就绪，从中心拉取最新全局路由表提供服务。

---

## 五、 验证与排障速查表 (Verification & Troubleshooting)

### 5.1 验证检查清单

#### 1. 边缘节点可写目录权限校验

在任意边缘节点执行：

```bash
ls -la /var/lib/trafficserver/etc/
```

- **预期输出**：文件属主与属组必须为 `trafficserver:trafficserver`；`remap.config` 是普通文件或非 `/nix/store` 软链。

#### 2. 微轮询低开销状态验证

在未下发变更的稳态下手动触发一次同步并观察日志：

```bash
systemctl start atc-t3c-sync.service
journalctl -u atc-t3c-sync.service -n 20 --no-pager
```

- **预期输出**：必须打印类似 `Update not pending, exiting`，总执行耗时 $< 1\text{s}$。

#### 3. 动态配置无感下发端到端校验

- 在 `terraform/cdn.tf` 增加一条测试规则后执行 `terraform apply`。
- 边缘节点观察日志：
  ```bash
  journalctl -u trafficserver.service -f
  ```
- **预期输出**：日志中必须打印 `remap.config finished loading`。
- 检查主进程 PID：
  ```bash
  systemctl status trafficserver.service | grep "Main PID"
  ```
  配置更新前后 **Main PID 保持一致**，无服务停机。

---

### 5.2 常见排障排错速查表

| 故障现象                                                    | 潜在根因                                                         | 排查与修复步骤                                                                                                                                                                  |
| :---------------------------------------------------------- | :--------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `t3c apply` 报 `Read-only file system`                      | `remap.config` 仍指向 `/nix/store` 路径                          | 检查 `edge.nix` 中 `environment.etc."trafficserver/remap.config".enable = false;` 是否生效；检查 preStart 是否正确创建可写目录。                                                |
| `atc-t3c-sync` 报 `401 Unauthorized`                        | `t3c-sync` 用户凭据不匹配或未在 Traffic Ops 初始化               | 1. 检查 `secrets/common.yaml` 中的 `atc.ops_password`；<br>2. 在中心节点检查 `traffic-ops-init.service` 日志，确认 SQL 种子是否成功灌入 PostgreSQL 的 `tm_user` 表。            |
| `atc-t3c-sync` 一直显示 `Traffic Ops API ... not reachable` | 边缘无法解析/访问 `ops.dora.im`，或健康检查路径错误              | 确认 `ops.dora.im` 是指向中心 `fra0` 的非 CDN CNAME；健康检查使用 `/api/4.0/ping`，不要使用不存在的 `/api/v4/ping`。                                                            |
| CDN 域名返回 `401 Unauthorized` 而非 404                    | 源站 Traefik 的 Basic Auth 正常拦截，说明 CDN 已成功回源         | 保留 `WWW-Authenticate: Basic`；使用 code 服务的 Basic Auth 凭据登录。TLS 终止在 ATS 后，ATS 通过 HTTPS 回源，不绕过源站认证。                                                  |
| CDN 域名返回 404                                            | 请求命中了未运行 ATS 的源站/控制节点，或 Delivery Service 未同步 | 只把运行 `trafficserver` 的节点放入 `cdn_edge_nodes`；确认 Traffic Ops 有对应 DS、HOST_REGEXP、origin 和 edge server 绑定。                                                     |
| 边缘节点报 `Update failed: Connection refused to opsHost`   | 网络策略限制或 Traffic Ops 未监听全接口                          | 1. 检查中心节点 `traffic-ops.service` 是否正常存活；<br>2. 检查 `ops.nix` 的 `listenAddress` 是否为 `0.0.0.0`；<br>3. 检查中心节点 Traefik HTTPS 端点可达性或防火墙 8088 端口。 |
| 新域名解析未能调度到特定边缘节点                            | CoreDNS Zone 文件未更新或权重为 0                                | 1. 检查 `terraform/cdn.tf` 中该节点的 `weight` 是否 $>0$；<br>2. 在 Router 节点执行 `systemctl status traffic-router.service`，验证 CoreDNS 重新加载状态。                      |
| 跨大洲高延迟链路单连接吞吐低下                              | 系统默认 TCP 读写缓存过小                                        | 在边缘和源站节点确认 `services.atc.tuning.enable = true;` 已启用；通过 `sysctl net.ipv4.tcp_rmem` 确认第三项达到 `67108864` (64MB)。                                            |
