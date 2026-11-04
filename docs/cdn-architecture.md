# ATC CDN 架构、hkg5 故障根因与健康调度运维指南

本文记录 2026-11-02 至 2026-11-03 排查得到的生产故障证据，以及对应的声明式代码修复。**历史现场证据不等于所有节点的新代码均已生效**：最初修复只修改代码并做本地验证；操作者更新 Terraform 并授权上线后，才开始分阶段部署。当前功能验收限定为 fra0 控制面和 sjc0 边缘，全部功能通过前不继续部署或测试 hkg5。Terraform apply 和生成输出仍由操作者执行，禁止手改 `data.json`。

## 1. 结论与职责边界

此次问题不是简单的 DNS 解析失败，也不是“正常边缘负载偏高，降权还没跟上”。有两个独立故障：

1. **数据面失效**：ATS worker 初始化失败并退出，manager 禁止自动重新拉起，却保留 HTTP 监听器。内核积压未 accept 的连接，形成大量 CLOSE-WAIT 和持续资源占用。
2. **调度链断裂**：Traffic Monitor 已报告节点不可用，但旧 DNS 脚本读的是静态注册信息；文件读取失败时还回退发布全部边缘，故障节点继续留在 DNS 中。

改进后的原则：不可用、timeout、未知或过期证据对应地址必须移除；只有仍然就绪的节点才进行性能降权；本地恢复不能依赖 Traffic Ops；资源保护不能依赖远程 DNS 及时生效。

**保留重复 DNS 记录表示权重**。健康节点基准权重为正整数，例如当前声明的 sjc0=5、hkg5=8，完成健康验收和恢复后分别展开五条和八条相同 A 记录。未就绪节点为零副本；故障节点的所有副本都移除，不改成随机只返回一个地址。递归 DNS 可能去重、重排或缓存，不能承诺实际 HTTP 流量严格为 5:8。

### 1.1 配置与组件

| 层次          | 文件或服务                             | 实际职责                                                                    |
| ------------- | -------------------------------------- | --------------------------------------------------------------------------- |
| 声明与交付    | `terraform/cdn.tf`                     | CDN 节点、整数权重、业务源站映射、源站直达服务、Cloudflare CNAME 和 NS 委派 |
| 生成数据      | `lib/data/data.json`                   | 现有 Terraform 输出提取流程生成的工件，禁止手工编辑                         |
| 角色识别      | `nixos/modules/services/atc/roles.nix` | 根据生成数据启用控制或边缘角色                                              |
| 控制管理      | `ops.nix`、`traffic-ops`               | 拓扑、profile、Delivery Services、运行时凭据、版本信息和快照                |
| 远程健康      | `monitor.nix`、`traffic-monitor`       | TC 8.0.2 实时分地址族探测，发布 `/publish/CrStates`                         |
| 权威调度      | `router.nix`、`steering.py`            | CoreDNS 公网入口，后台健康采样、本地权威回答、重复记录权重与安全源站回退    |
| 边缘缓存      | `edge.nix`、`trafficserver`            | ATS 9.2.11 manager/worker、本机缓存及 t3c 同步                              |
| 本地健康/恢复 | `edge-health.py`                       | 有界统计桥接、真实 worker 探测、持久化恢复预算及冷却                        |
| 网络调优      | `tuning.nix`、系统网络模块             | TCP/FQ/BBR 等调优，不负责清理失效应用持有的监听队列                         |

这里的 `traffic-router` **实际上是 CoreDNS，不是 Apache Java Traffic Router**。当前没有实现 GeoIP、ECS、Anycast 或按客户端地理位置择优，也没有 HTTP 302 跨边缘调度。

### 1.2 请求与健康链路

```text
客户端 DNS
  -> 父区域 Cloudflare CNAME: code.dora.im -> code.cdn.dora.im
  -> CDN 权威 CoreDNS: 公网 IPv4/IPv6 UDP/TCP 53
  -> 本机 steering: 127.0.0.1:5354
  -> 业务专属 route-code.cdn.dora.im
  -> 健康边缘重复 A/AAAA；没有可用边缘时为该业务的已配置源站

客户端 HTTPS -> 边缘 Traefik:443 -> ATS 127.0.0.1:8089 -> 业务源站

ATS RPC + HTTP + /proc
  -> 本地健康采样器 -> 127.0.0.1:9130 /_astats、/healthz
  -> 边缘 Traefik:80 的控制节点来源白名单
  -> Traffic Monitor -> 127.0.0.1:8087 /publish/CrStates
  -> steering 后台同时读取 CrStates 和边缘 /_astats

本地 recovery timer -> 独立确认 worker 故障 -> 有预算地重启或关闭整个 ATS cgroup
```

健康采样和 DNS 请求处理解耦。**DNS 请求不实时发 HTTP 探测，健康接口请求不启动额外的 traffic_ctl 采样**，避免探测放大故障。

## 2. hkg5 的完整故障链

### 2.1 从下载超时到本机 TCP 接收停顿

最初报错为 Lix narinfo 下载的 libcurl 错误 28：低于 1 字节/秒持续 30 秒。它是低速停滞保护，不是“下载总时长不得超过 30 秒”。

分层检查得到：A 记录为 `144.76.43.250`，本地和公共 DNS 一致；IPv4 路由经公网网关而非 DN42；绕过 DNS 的 IPv4/IPv6 TCP、TLS、HTTP 请求均可成功。本地 SmartDNS 的 AAAA 空结果是独立现象，不能据此解释整体失联。

抓包的关键证据是缓存服务器已经发送 TLS 数据，而 hkg5 反复回复 **TCP 接收窗口 win 0**。对端暂停发送，是本机暂时收不下数据，而非证明公网没有数据到达。

原始那次 30 秒超时没有同步抓包，因此不能追溯证明每一秒均由此机制导致，也不能排除当时的短时公网异常。本次实测确实存在本机 TCP/资源压力。

### 2.2 worker 致命退出与 manager 保留监听

10 月 24 日节点本地日志：

```text
23:54:04.413 Unable to access() directory '/etc/trafficserver/body_factory'
23:54:04.413 EMERGENCY: Please set 'proxy.config.body_factory.template_sets_dir'
23:54:05.421 Proxy is un-recoverable. Proxy will not be relaunched.
```

现场 `traffic_ctl server status` 为 `Proxy -- off`，`proxy.node.proxy_running=0`，只有 traffic_manager，没有处理 HTTP 的 traffic_server worker。

ATS 9.2.11 的源码调用链：

1. `HttpBodyFactory::reconfigure()` 在初始化阶段发现模板根目录不可读，调用 `Emergency`。
2. `Diags::error_va(DL_Emergency)` 经 `ink_emergency_va()` 以 `UNRECOVERABLE_EXIT=33` 退出。
3. `LocalManager::pollMgmtProcessServer()` 取得退出码，设置 `proxy_recoverable=false`。
4. manager 自动拉起路径要求该标志为真；不可恢复分支未关闭 HTTP listener。

边界：不是任意模板文件缺失都会致命；这里是**初始化阶段模板根目录不可读**。运行期对应分支仅警告。关闭定制错误页面也不能可靠绕过该目录检查。

### 2.3 为什么 CLOSE-WAIT 不释放

| 历史现场指标                     | 数值                          |
| -------------------------------- | ----------------------------- |
| 8089 listener 等待 accept 的队列 | 41,865                        |
| 允许的 listener backlog          | 55,720                        |
| 127.0.0.1:8089 CLOSE-WAIT        | 21,456                        |
| 这些 CLOSE-WAIT 的 inode         | 全部为 0，无对应用户态连接 fd |
| CLOSE-WAIT 接收内存估算          | 约 26 MiB                     |

manager 创建 listener 并传 fd 给 worker。worker 消失后，manager 仍留着 fd，内核仍可完成 TCP 握手。客户端等待不到 HTTP 响应，超时后发送 FIN；没有 worker 去 accept 和关闭子连接，它们停留在监听器持有的内核队列中。

```text
worker 退出 -> manager 保留 listener -> 内核完成握手
-> 无人 accept/read -> 客户端超时发送 FIN
-> 未 accept 子连接 CLOSE-WAIT -> listener 未关闭，队列资源仍保留
```

这不是“业务 worker 忘记 close 已接收连接”的普通泄漏。队列受 backlog 和内核限制约束，但旧上限足以积压数万连接。`tcp_fin_timeout` 不是 CLOSE-WAIT 的清理计时器；仅 DNS 降权或 config reload 也不会释放已经积压的队列。

恢复时需要关闭旧 listener：停止/重启整个 manager/worker cgroup，而非只向旧 manager 发 reload。

### 2.4 两种内存压力不能混为一谈

全系统 TCP 内存约 41,745 页，即 163 MiB；当时 `tcp_mem=6720 10080 13440` 页，高水位仅 52.5 MiB，使用约为高水位的 3.1 倍。该阈值与主机配置的 `environment.networkTune.ram=350` 有关。

另外，manager 用户态 heap 映射约 645 MiB，几乎全部在 swap。它与内核 socket 内存是两类占用，不能相加后声称全部来自 CLOSE-WAIT。

源码确认 manager 还存在长期消息保留机制：worker 不运行时，无法发送的事件重新入队而不释放；`BaseManager` 队列没有容量上限、去重或过期；reload 和 manager 主循环派生统计仍生产新消息。重新入队同一指针本身不复制 payload，增长来自新生产者。records push 也不能简单解释成“没有 ACK 所以每五秒重发全表”。

**无界消息积压的机制已确认，645 MiB 中的具体占比未做现场 allocator/队列归因。**新的保护策略不依赖把全部 heap 增长断言为已证实泄漏，而是避免死 worker 的 manager 长期存活，并限制 cgroup 内存。

同时测到约 76%-84% CPU steal、严重换页与高 PSI。这包含宿主机不给 vCPU 时间的因素，DNS 调度和进程重启不能修复供应商宿主机争用。

### 2.5 控制面已经发现，DNS 却仍发布故障节点

实时 `CrStates` 为 hkg5 的 `isAvailable=false`、`ipv4Available=false`、`ipv6Available=false`；权威 DNS 却仍返回 tyo0 五条、hkg5 八条 A，AAAA 还返回 hkg5 八条。

旧实现的断链有四层：

| 问题                                                           | 后果                              |
| -------------------------------------------------------------- | --------------------------------- |
| trafficrouter 无法穿过 trafficmonitor:trafficmonitor 0750 目录 | 读取 `crconfig.backup` 失败       |
| 读取失败或无健康节点就发布全部边缘                             | 故障信号反而触发 fail-open        |
| 即使可读也只筛选 REPORTED/ONLINE                               | 注册状态被误当成实时健康          |
| 权重仅来自静态数据                                             | CPU、内存、TCP 队列压力未形成反馈 |

`REPORTED` 表示纳入监控的注册状态，**不是本轮探测成功**。修改目录权限只能修第一层，不能修正错误的数据源。

另外，Monitor 使用 astats 解码器，需要 `ats/system`；边缘 `stats_over_http.so` 返回 `global`，而且实际物理 NIC 不一定叫 eth0。tyo0 也因此被错误判为不可用。旧 Monitor JSON 中的 `health_penalty_*`、`connection_time_*` 不被 TC 8.0.2 支持，未知字段被静默忽略，不代表真的实现了自动惩罚。

## 3. 数据面修复与本地自愈

### 3.1 配置修复

`lib/data/atc-records.nix` 统一基线，`edge.nix` 启动和同步后进行幂等修复：

- 缺失模板目录时关联锁定 ATS 包的 `body_factory`，保持 `/etc/trafficserver` 到可写配置目录的关系。
- 将旧无类型 records 修正为 `CONFIG <name> INT/STRING <value>`；移除失效别名及不合适的 config_dir 项，保留无关 t3c 配置。
- RAM cache 基线为 32 MiB；ATS listener backlog 固定 512，不再继承数万的全局队列上限。
- 显式关闭 exec_thread 自动拓扑推断；本机网络线程默认 `min(8, max(1, networkTune.cpus))`，避免 VPS 暴露巨大虚拟 CPU 拓扑。
- 保留 `stats_over_http.so /_astats`，由桥接器转换格式，不额外引入不匹配的 astats 插件。
- 缺失、空白或仅注释的 storage 使用现有 `services.trafficserver.storage` 声明补缺，默认 `/var/cache/trafficserver 256M`。ATS 自行创建目录 span 内的 `cache.db`；脚本不删除、截断或格式化已有缓存文件。
- t3c 缺少 Drive 参数时会生成空 storage，却仍可能生成 `hosting.config` 的 `volume=1`。同步前后成组保存/恢复 storage、volume、hosting；默认隐式 volume 0 不迁移到显式 volume 1。仅修复自动生成且引用不存在 volume 的 hosting，保留用户自定义和已有有效布局。
- 缓存 Cookie 策略为 `cache_responses_to_cookies=0`；`ignore_authentication`、`ignore_client_no_cache`、`ignore_server_no_cache` 均为 0。`required_headers=2` 对 200 响应要求明确过期时间或 max-age/s-maxage；不是所有状态码的 public-only 开关，也不以强制 TTL 绕过 no-store/private。

配置留在 `/var/lib/trafficserver/etc`，不把动态 remap 链接到只读 Nix Store。t3c 使用轻量输出 `pkgs.trafficcontrol.t3c`，不要求边缘安装整套控制面依赖。

回源 Host 隔离保持既有行为：全局 `proxy.config.url_remap.pristine_host_hdr=1`，每个 Delivery Service 的 header_rewrite 明确设置 `Host: <service>.<domain>`。否则源站 Traefik 可能把请求按机器域名送进 DERP 等默认服务。DNS 回退也要用原业务域名访问源站，不能只用源站 IP 请求后以为所有虚拟主机都可用。

### 3.2 真实 worker 健康桥接

`atc-edge-health` 独立运行，绑定 `127.0.0.1:9130`。一个后台生产者每五秒采样，先检查有超时的 `traffic_ctl server status`，再请求真实 ATS `127.0.0.1:8089/_astats`。必须取得有效 ATS 连接指标，不能把源站返回的任意 JSON 当成 worker 成功。

HTTP 有绝对截止时间、响应字节上限，不跟随跳转、不用公网 DNS 或代理。gzip/deflate 响应按 Content-Encoding 解码，编码体和解压体都限制为 2 MiB，拒绝截断、额外压缩成员、未知编码和解压超限；不能直接把压缩体按 UTF-8 JSON 解析。`/proc` 输入以 4 KiB 分块读取并保留总大小上限，CPU steal 使用增量计数，PSI 与 TCP 指标来自真实内核数据。首次 CPU 基线不足、缺指标、worker off 或采样过期都返回 HTTP 503，不伪造零压力。

就绪状态还要求真实 `proxy.process.cache.bytes_total>0`、remap 存在 map/regex_map 规则，以及当前配置 digest 与成功启动/reload 后记录的 `loaded_config_hash` 相符。配置尚未应用、缓存未初始化时不发布节点。**这些是 readiness 条件，不是杀 worker 的理由**：恢复器在桥接失败时另行检查 worker RPC 与真实 HTTP，避免配置等待或监控故障误触发重启。

输出契约为精确 `Content-Type: application/json`，不能附带 charset，因为 TC 8.0.2 部分路径做精确字符串比较：

```json
{
  "ats": {
    "proxy.process.http.current_client_connections": 1,
    "proxy.process.cache.bytes_total": 268066816
  },
  "system": {
    "inf.name": "eth0",
    "inf.speed": 700,
    "proc.net.dev": "eth0: 10 1 0 0 0 0 0 0 20 2 0 0 0 0 0 0",
    "proc.loadavg": "0.10 0.20 0.30 1/200 1234",
    "notAvailable": false
  },
  "cdn": {
    "schema": 1,
    "sampled_at": 1800000000.0,
    "ready": true,
    "memory_available_ratio": 0.25,
    "cpu_steal_ratio": 0.2,
    "cpu_pressure": 0.125,
    "memory_pressure": 0.0125,
    "tcp_memory_ratio": 1.25,
    "close_wait": 2,
    "listener_queue": 10,
    "listener_capacity": 512,
    "cache_capacity_bytes": 268066816
  }
}
```

上例是契约示例，不是当前生产测量值。逻辑 eth0 的字节计数来自实际默认路由 NIC；可用 `services.atc.edge.health.interface` 显式指定。带宽容量使用 `networkTune.bandwidth`，CPU steal、内存 PSI、TCP 页数比例并非从静态注册状态推算。

### 3.3 Traefik 入站保护

ATS 8089 和 bridge 9130 均只监听 loopback。公网 80/443 的 `/_astats`、`/healthz` 通过 RemoteAddr 白名单，仅允许控制节点和 loopback；不信任 X-Forwarded-For 作为来源判定。边缘 HTTP/HTTPS 禁止不可信 PROXY protocol，避免伪造传输层来源绕过白名单。

健康路由优先级 1000，HTTP entryPoint 默认重定向优先级降为 1，避免默认极高优先级的内部重定向抢走 Monitor 的 HTTP 请求。普通业务仍重定向至 HTTPS。

业务后端强制只保留一个 `127.0.0.1:8089`，去除模块合并造成的重复后端；Traefik 每五秒检查独立 9130 `/healthz`，失败时不给死 worker 转发新请求。探测不能递归经过公网业务路由。

### 3.4 有预算的恢复，不是无限重启

`atc-edge-recovery.timer` 开机约 20 秒首次触发，上一轮结束后十秒再检查。它独立于 Traffic Ops、Monitor 和 DNS：优先使用新鲜本地健康快照，桥接故障时再直接确认 worker，避免只因监控进程坏了而重启健康 ATS。

| 参数                    | 默认                             |
| ----------------------- | -------------------------------- |
| 新 ATS 启动宽限         | 30 秒                            |
| 活跃服务连续失败阈值    | 2 次                             |
| 滚动恢复窗口            | 600 秒                           |
| 最大 start/restart 尝试 | 3 次，失败和超时也计数           |
| 预算耗尽冷却            | 300 秒，必要时延长以满足滚动窗口 |
| systemctl 操作超时      | 105 秒                           |

状态在 `/var/lib/atc-edge-recovery/state.json` 持久化，操作前落盘并 fsync；锁避免重叠；服务或系统重启不会清空预算。状态损坏或时钟回退采取保守冷却，不当作无限重启许可。

预算耗尽时**停止整个 ATS cgroup，关闭 manager 的监听器**。冷却期即使外部重新启动也会再停止，以免失效 listener 持续积压。`Restart=no` 保证单一恢复负责人；`KillMode=control-group`、`OOMPolicy=stop`、启动/停止截止时间确保不只处理 manager PID。

systemd 的 StartLimitInterval/StartLimitBurst 设为 0，避免正常 Nix 配置激活的重启消耗第二套计数、使恢复器尚有预算却遭遇 start-limit-hit。真正的自动恢复上限仍由持久化的三次/600 秒预算控制，不是无限重启。状态中保留的过去 `cooldownUntil` 不代表仍在冷却，判断条件是当前时间小于该值。

这会在持续故障时牺牲该节点可用性，换取宿主机不被永久失效数据面拖垮；DNS 应将其摘除并转往其余健康边缘或已配置源站。

### 3.5 内存隔离与同步边界

不设 CPUQuota，但不能再宣称“无任何 cgroup 限额就是性能优化”。按 `networkTune.ram` 计算内存预算，保护系统其他服务：

| 边界                         | 默认公式                      | hkg5 ram=350 时      |
| ---------------------------- | ----------------------------- | -------------------- |
| ATS+t3c 总 slice MemoryMax   | max(128, floor(ram*0.75)) MiB | 262 MiB              |
| ATS manager+worker MemoryMax | max(96, floor(ram*0.55)) MiB  | 192 MiB              |
| ATS MemoryHigh               | floor(ATS MemoryMax*0.8) MiB  | 153 MiB              |
| ATS/总 slice SwapMax         | min(128, floor(ram*0.1)) MiB  | 35 MiB               |
| t3c MemoryMax                | max(64, floor(ram*0.3)) MiB   | 105 MiB              |
| 健康桥接/恢复                | 独立于 ATS slice              | 64/48 MiB，禁止 swap |

这些预算不是所有进程均预留这么多内存，且必须留意实际套餐可用内存、其他服务和内核占用。不要为消除告警直接抬高 TCP 高水位或无限放大队列；先关闭失效 listener，再根据稳定负载调优。

同步与启动共享 `/run/atc-edge-config.lock`；t3c 的下载、重试和运行时间均有界，禁止它自行操作 systemd。配置 hash 发生变化且 worker 为 on 时才 reload；worker off 时保留配置等待下一次启动，不继续向死 worker 的 manager 填 reload 事件。未变化文件不每三十秒无条件 reload。

TC 8.0.2 即使 `--service-action=none` 仍调用绝对路径 `/usr/sbin/service trafficserver status`。仅在 t3c mount namespace 内只读绑定状态适配器：从真实 traffic_manager PID 返回上游要求的 `Active: active`/`Main PID` 格式，其他服务或动作直接拒绝。宿主机通用 service 包装器不改变，`/run/systemd` 和 `/run/dbus` 仍不可访问；不要为通过状态查询而放开整个 D-Bus 管理权限。

密码只从 SOPS 运行时注入 `TO_PASS`，不放命令行或 Store。TC 8.0.2 t3c 不支持 `--traffic-ops-password-file`。同步服务运行 root 是 syncds 对部分文件的上游要求，ATS worker 仍使用 trafficserver 用户。账户当前为 operations 角色，**不是严格只读账户**。

## 4. 控制面监控契约与快照

Monitor 主配置和 Ops 凭据配置分别按 TC 8.0.2 两个结构体生成，保留字段白名单校验，删除上游不认识的健康惩罚和时延字段。密码仅在启动时写 `/run/traffic-monitor/traffic_ops.cfg`，0600，不写入 Store。

| 实际参数                     | 默认及用途                                         |
| ---------------------------- | -------------------------------------------------- |
| `http_timeout_ms`            | 3000 ms，总 HTTP 超时                              |
| `cache_polling_protocol`     | both，分别检查 IPv4/IPv6                           |
| `stat_polling`               | true，统计不能被关闭来制造健康                     |
| `heartbeat.polling.interval` | 5000 ms，实际可用性轮询                            |
| `health.polling.interval`    | 60000 ms，TC 8.0.2 中实际是统计轮询                |
| `peers.polling.interval`     | 20000 ms                                           |
| `health.connection.timeout`  | 3000 ms，上游覆盖单缓存总请求超时，并非仅 TCP dial |

Ops 初始化只调整所属 profile 的 parameter 关联，不删除或改写其他 profile 共用的行。旧 `stat.polling.interval` 解除关联。边缘逻辑接口 monitor=true，已有 IPv4/IPv6 地址均修为 service_address=true，避免 IPv6 地址存在但不被探测。

数据库初始化在 API 前完成；**CRConfig 快照由独立 `traffic-ops-snapshot.service` 在 API 启动后发布**，认证和 PUT 均有截止时间、有限重试，失败以非零状态可见，不再在 API 未启动时偷偷忽略失败。凭据经临时运行目录文件传给 curl，操作后清理。

控制面版本 `/version.json` 保留，边缘可从候选控制节点选择最大 epoch 并拒绝较老 epoch 的配置。不过 Flake 的 lastModified、Dirty 标记不是集群共识协议，也不是任意 dirty 修改都必然生成全局单调的版本；当前选举是顺序请求，不是并发投票。多控制节点的数据库复制、仲裁、证书和真实 HA 仍需单独设计。

## 5. 实时 DNS 调度与重复记录权重

### 5.1 入池条件与 freshness

steering 不再读取 Monitor 私有备份目录，也不再运行旧 `atc-dynamic-dns` zone 生成脚本。后台每五秒读取 loopback 的 `/publish/CrStates` 和每个边缘 HTTP `/_astats`，总 poll 预算三秒、socket 超时一秒、最多四个 HTTP worker。

每个地址族必须同时满足：

1. Monitor 对该节点 `isAvailable=true`，对应 `ipv4Available` 或 `ipv6Available=true`，字段必须是真正布尔值。
2. `lastPoll` 为合法带时区时间戳，且不超过二十秒。
3. 边缘 `cdn.schema=1`、`ready=true`，指标完整、有限、合法，`sampled_at` 不超过二十秒。
4. 本机内存 snapshot 和对应节点证据未到 monotonic 截止时间。

拒绝重复 JSON key、NaN、无限值、缺字段、非法 HTTP、超大响应与超时。没有本轮证据时**不沿用上轮健康**；poll 卡住后 DNS 线程也会按独立过期时间停止使用旧 snapshot。启动时不相信磁盘缓存的健康状态。

IPv4/IPv6 各自摘除和恢复：例如 hkg5 IPv6 不可用只删除它的 AAAA，不能因为 IPv4 正常继续发布坏 AAAA。当前性能采样通过 IPv4；因此 IPv4 统计通道断开时即使 IPv6 可以服务，也会保守地将该节点两族都摘除。这是现有有界采样策略的可用性取舍，不是完全双栈独立统计。

### 5.2 性能反馈、滞后与整数副本

性能压力只针对真实就绪节点。压力 P 取以下归一化指标的最大值，截断到 0..1：

- 可用内存低于总内存 15% 的程度，以及 memory PSI full avg10。
- CPU steal 比例、CPU PSI some avg10 的 0.6 倍。
- TCP 内存从高水位的 50% 到 100% 的程度。
- ATS CLOSE-WAIT 数量 / listener capacity、listener queue / capacity。

目标分数 `score=max(0.1, 1-0.9*P)`。普通压力保留最低分数，不因为 CPU 100% 就让所有仍然可用节点一起消失。明确 memory_available=0 或 listener queue>=capacity 时属于硬故障，权重归零。

每次新鲜成功证据推进时，降分 EWMA 系数为 0.5，恢复系数为 0.1，分差小于 0.03 不变，减少抖动。节点重新入池需连续三次**两个时间戳均推进的**成功快照；重复读同一个快照不能凑足恢复次数。恢复后六十秒 slow start，从 5% 起逐步放量。

```text
有效权重 = 基准整数权重 * 平滑压力分数 * slow-start 因子
副本数 = 有效权重 > 0 ? max(1, floor(有效权重 + 0.5)) : 0
```

因此权重 8 的节点恢复初期至少一条记录，满健康时八条；压力下副本数逐级减少；timeout/down 时直接零条。离散副本使小权重的微小变化不能全部体现，这是保留重复记录方式的必然粒度限制。

回答在保留重复副本的同时洗牌，不固定让配置列表第一台永远排在第一。基准权重必须为正整数，全部节点总和最多 256，限制 DNS 响应和内存成本。UDP 超过 512 字节或 EDNS 上限时置 TC 并让递归 DNS 用 TCP 取完整回答，不发送假装完整的部分权重池。

### 5.3 安全回退与业务隔离

各服务使用独立 `route-<service>.cdn.<domain>` 目标，避免所有服务共享 apex RRset，使源站回退和直达策略互相污染。

| 情况                                         | 回答                                        |
| -------------------------------------------- | ------------------------------------------- |
| 至少一个健康边缘                             | 对应族的重复加权边缘地址                    |
| 服务池为空、Monitor down、启动或全部证据未知 | 该业务 `data.services` 指定的已配置源站地址 |
| `originOnlyServices` 中的服务                | 始终直达该业务源站                          |
| 业务指向未知源站                             | SERVFAIL，不发布全部边缘                    |
| 指定边缘域名但该边缘故障                     | SERVFAIL，不回退另一个假冒该主机            |
| 配置没有对应地址族                           | NOERROR/NODATA + SOA                        |
| apex 没有健康边缘、也没有显式 apexOrigin     | SERVFAIL                                    |
| 未知名字/区域外请求                          | NXDOMAIN/REFUSED                            |

源站回退表示“回退到明确配置的源站”，**不是已做源站健康验证**。当前没有全业务 origin readiness 探测；源站失效仍可能返回失效源站地址，但绝不能把已知故障边缘伪装成健康。

Terraform 保留当前 chat 源站直达策略为 `cdn_origin_only_services=["chat"]`，输出 `originOnlyServices`；额外导出 `originNodes`，支持不在控制节点清单中的业务源站。本轮操作者已更新生成数据并验证 chat 直达源站。将来改变声明仍需重新生成输出，不能把旧数据的兼容空列表误当成新策略已完成迁移。

### 5.4 时效与算法边界

失败在下一次完成的 poll 中即可移除，默认约五秒周期加最多三秒预算；探测源本身也有采样延迟。证据过期边界默认二十秒。外部递归 DNS 和客户端仍可能缓存旧回答至 TTL=30，甚至 serve-stale，HTTP 长连接也不会迁移。**不能承诺所有互联网客户端秒级停用节点**。

CoreDNS 只 forward 到本机权威，无额外 cache 插件。状态与指标绑定 `127.0.0.1:9131`：`/status` 包含原因、分地址族权重、记录数、成功次数及过期状态；`/metrics` 包含 `atc_dns_snapshot_stale`、`atc_dns_edge_weight`、`atc_dns_edge_records` 和查询结果计数。当前只是导出接口，尚未配置中心抓取和告警规则。

此算法是有界、保守的反馈降权，不是严格闭环最优控制：没有真实请求率、尾延迟、每业务错误率或按用户区域的流量目标。DNS 重复记录被去重后，副本权重可能失效。需要严格比例时应另行评估真正 L7 weighted LB；不在本轮偷偷替换已明确要求的重复 RR 模式。

## 6. 人工交付与上线验收

### 6.1 Terraform 由操作者执行

本轮不触碰 `lib/data/data.json`，不运行 apply/plan、不处理 Terraform 解密密码。使用仓库已有开发环境和生成链，禁止访问全局 flake registry：

```bash
nix develop path:.
terraform-pipe
```

`terraform-pipe` 包含 Terraform 初始化/apply、输出更新、数据和 secrets 提取、格式化；还会对独立的 infrastructure-secrets 仓库 pull/commit/push。若不希望自动 Git 副作用，使用同一环境分步执行现有工具，并由操作者自行处理该仓库：

```bash
terraform-init
terraform-wrapper apply
terraform-update-outputs
terraform-outputs-extract-data
terraform-outputs-extract-secrets
```

不要绕过加密 state wrapper 用裸 `terraform apply`，也不要手改 data.json。生成后检查 diff，确认只包含计划内的 `originNodes`、`originOnlyServices` 及节点/服务变化，不把明文密码或 Terraform state 提交到本仓库。

### 6.2 分阶段部署

1. 确认当前业务源站可直达，chat 的临时直达行为已声明到生成数据；先评估 fallback 对源站容量的影响。
2. 部署控制节点，确认 Ops 初始化、API、快照服务成功以及 steering 可运行；边缘未升级时可能全部 fail-closed 到源站，这是预期迁移行为。
3. 逐台部署边缘，先完成本机 worker/HTTP/bridge 验收，再观察 Monitor 与 DNS 入池，不同时停掉所有边缘。
4. 必要时反过来先升级边缘桥接，再切换控制调度，缩短全池源站回退时间；在旧调度仍发布坏节点的情况下不能只等待自动平衡。
5. 完成以下 runtime 漂移核对后，才算整个生产闭环验收结束。

部署示例，使用锁定输入和本地构建，当前只上线两台验收节点：

```bash
nixos-rebuild switch --flake path:.#fra0 --target-host root@fra0 --no-reexec --builders ''
nixos-rebuild switch --flake path:.#sjc0 --target-host root@sjc0 --no-reexec --builders ''
```

不启用 `--use-substitutes` 可避免资源紧张目标再次直接高并发查询缓存，但不解决宿主机 CPU steal。非 rebuild 的远程操作用 `timeout 25s ssh ...`，只做有限重试；等待健康轮询和 slow start 用可见的定时唤醒，不让单个命令长时间挂起。

### 6.3 必须核对既有运行时覆盖

历史发现的覆盖包括 `/run/systemd/system/atc-dynamic-dns.service.d/90-chat-connection-recovery.conf`、`/run/chat-dns-recovery.sh` 和 hkg5 的 `/run/traefik-recovery.toml`。授权迁移期间只归档这些明确属于故障恢复的覆盖：fra0 在 `/var/lib/traffic_router/retired-20261103`，hkg5 在 `/var/lib/traefik/atc-retired-20261103`。没有删除其他人的 override。hkg5 的归档发生于改为两节点验收之前，不表示其永久新配置已上线。

```bash
systemctl cat traffic-router atc-dns-steering traffic-monitor traffic-ops-snapshot
systemctl cat trafficserver atc-edge-health atc-edge-recovery atc-t3c-sync traefik
systemctl show trafficserver -p ExecStart -p DropInPaths -p KillMode -p Restart
systemctl show traefik -p ExecStart -p DropInPaths
systemctl cat atc-dynamic-dns.service
```

迁移 chat 的声明行为后，由操作者确认并停用旧 DNS timer/服务、移除**仅属于这次故障恢复的**旧 drop-in，再 daemon-reload。不能盲目删除整个 `/run/systemd/system` 或其他服务 override。Traefik 若还加载临时文件，新生成健康路由不会生效；必须核对实际 ExecStart、动态文件和监听器。

### 6.4 边缘本机验收

```bash
traffic_ctl server status
curl --max-time 3 -sS http://127.0.0.1:8089/_astats | jq '.global | keys | length'
curl --max-time 3 -sS http://127.0.0.1:9130/healthz | jq '{system, cdn}'
systemctl show trafficserver -p KillMode -p MemoryHigh -p MemoryMax -p MemorySwapMax
ss -lntp '( sport = :8089 )'
ss -tan state close-wait '( sport = :8089 )'
journalctl -u atc-edge-recovery -u atc-t3c-sync --since '-10 min' --no-pager
```

预期：Proxy on，ATS global 指标非空，bridge ready=true，采样时间新鲜；8089/9130 不暴露公网；listener 队列不再数万积压；config 未变化时不重复 reload。确认原模板目录、typed records 和单网络线程生效，不能只看 `systemctl active`。

从控制节点来源请求边缘 IPv4 `http://<edge-ip>/_astats`，应为 200 和 `ats/system/cdn`，**不得是 HTTP 重定向**；非白名单来源应拒绝。双栈节点还需分别测 IPv6 HTTP/HTTPS 路径。

### 6.5 控制面与权威 DNS 验收

```bash
systemctl status traffic-ops-snapshot traffic-monitor atc-dns-steering traffic-router
curl --max-time 3 -sS http://127.0.0.1:8087/publish/CrStates \
  | jq '.caches | with_entries(.value |= {isAvailable,ipv4Available,ipv6Available,lastPoll,status})'
curl --max-time 3 -sS http://127.0.0.1:9131/status | jq .
curl --max-time 3 -sS http://127.0.0.1:9131/metrics
dig @94.249.174.75 code.cdn.dora.im A +noall +answer
dig @94.249.174.75 code.cdn.dora.im AAAA +noall +answer
dig @94.249.174.75 route-code.cdn.dora.im A +tcp +noall +answer
dig @94.249.174.75 chat.cdn.dora.im A +noall +answer
```

权威地址只是历史 fra0 示例，拓扑变化后使用新生成地址。验证重复记录必须直接查权威并保留完整回答，不能仅查可能去重的公共递归服务器。

当前权威监听地址为公网 IP，**`dig @127.0.0.1` 在 fra0 查询的是本机递归缓存，不是这套权威调度器**。它可能仍返回旧源站地址和衰减 TTL，造成“/status 已有五副本，DNS 却只有源站”的误判。验收使用 `@94.249.174.75`，当前权威 TTL 实测 30 秒。

受控故障演练应在可回退源站、其他节点已验收后执行：使一台边缘健康接口超时，验证其对应所有 A/AAAA 副本在新 snapshot 中为零；恢复后需新鲜三轮成功再逐级恢复副本；Monitor 整体不可用时应只回退已配置源站，不能出现全节点 fail-open。重启 ATS 会中断该节点存量会话，因此不可在繁忙生产中未经维护窗口随意演练。

同时观察 `/proc/net/sockstat`、`tcp_mem`、CPU steal、PSI、swap、接口吞吐。原 listener 关闭后 TCP 内存应下降，但全系统 TCP 内存不必立即清零；其他服务同样消耗 socket 内存。

## 7. 回归验证与后续方案

| 测试                            | 覆盖                                                                                                                 |
| ------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `tests/atc-edge-health.py`      | worker off/RPC 超时、压缩响应/解压上限、单生产者、缓存/remap/reload 就绪、PSI/TCP、过期、恢复预算/冷却/损坏/时钟回退 |
| `tests/atc-steering.py`         | 实时健康、分地址族、重复权重、timeout 全副本移除、压力降副本、慢恢复、源站直达/回退、UDP/TCP/EDNS 与 CoreDNS 转发    |
| `tests/atc-monitor-contract.py` | 生成 Nix 配置、TC 8.0.2 字段、profile 迁移、双栈 service 地址、API 后快照和 Traefik 优先级/来源防护                  |
| `tests/atc-regression.py`       | 旧 records 修复、保守缓存策略、存储补缺、storage/volume/hosting 回滚、缓存 inode 保持、模板软链、幂等及基线 SQL 迁移 |

Python 和 dnslib 使用锁定的 nixpkgs 输入，示例：

```bash
nix shell --impure --expr 'let f = builtins.getFlake (toString ./.);
  p = import f.inputs.nixpkgs { system = builtins.currentSystem; };
  in p.python3.withPackages (ps: [ ps.dnslib ])' \
  -c python3 -B tests/atc-steering.py
```

`ATC_TEST_COREDNS` 指定锁定 CoreDNS 二进制可启用真实 loopback 前门集成测试。Monitor 测试的 `--tc-source` 校验锁定上游源码；`--pg-socket` 只能指向 `/tmp/kilo` 的一次性 PostgreSQL，临时表事务回滚验证幂等和共享 parameter 安全，**禁止连接生产数据库执行整个 init 脚本**。离线测试不替代线上端到端验收。

后续方案及代价：

1. **供应商层根治 CPU steal**：迁移宿主机、CPU 有保障套餐或更换节点；应用层无法凭配置修复宿主机长期争用。
2. **完善可观测性**：将 steering/edge 状态接入现有监控，告警覆盖“DNS 仍发布 Monitor down”“恢复预算耗尽”“快照过期”“CPU steal/TCP pressure”；目前只提供状态接口，没有宣称已装好告警闭环。
3. **更精确负载调度**：引入实际带宽利用率、请求率、错误率和尾延迟，再做容量校准及每业务保护；不能根据单一快照断言已找到全网最优平衡。
4. **严格流量比例或就近路由**：另行设计 L7 weighted LB、GeoIP/ECS 或 Anycast；增加成本、控制面依赖与网络复杂度，不在本轮替换重复 DNS 记录方式。
5. **上游 ATS 改善**：评估升级及不可恢复 worker 退出时关闭 listener/有界事件队列的修复。当前是 NixOS 侧进程生命周期和资源兜底，不声称已修补 ATS 源码队列。

### 7.1 上游源码索引

- [ATS 9.2.11 HttpBodyFactory.cc](https://github.com/apache/trafficserver/blob/9.2.11/proxy/http/HttpBodyFactory.cc)：初始化目录检查与 Emergency。
- [ATS 9.2.11 LocalManager.cc](https://github.com/apache/trafficserver/blob/9.2.11/mgmt/LocalManager.cc)：exit33、listener、processEventQueue。
- [ATS 9.2.11 traffic_manager.cc](https://github.com/apache/trafficserver/blob/9.2.11/src/traffic_manager/traffic_manager.cc)：自动拉起条件与派生统计主循环。
- [ATS 9.2.11 BaseManager.cc](https://github.com/apache/trafficserver/blob/9.2.11/mgmt/BaseManager.cc)：消息分配与队列。
- TC 8.0.2 锁定源码：`traffic_monitor/config/config.go`、`handler/handler.go`、`cache/astats.go`、`manager/monitorconfig.go`、`poller/poller_type_http.go`、`lib/go-tc/servers.go`，分别对应字段、凭据、格式、间隔、总请求超时及 service 地址族构造。

## 8. 上线修补与两节点功能验收

### 8.1 上线中发现的额外问题

1. **Traefik PROXY protocol 启动条件**：3.7.15 在启用了 PROXY listener、`insecure=false` 且 `trustedIPs` 为空时拒绝启动。配置改为显式仅信任 `127.0.0.1/32` 和 `::1/128`，公网来源仍不能伪造 PROXY 地址。回归检查同时验证 false 与非空 loopback 白名单，不能只检查 false。
2. **sysctl 大读取产生 ENOMEM**：原 `read_bytes()` 向 `/proc/sys/net/ipv4/tcp_mem` 和 `somaxconn` 发起单次 8 MiB 读取。Linux 6.18 `proc_sys_call_handler()` 在 count 达到 KMALLOC_MAX_SIZE 时直接返回 ENOMEM；实测 4,194,303 字节成功、4,194,304 字节失败。这不是健康服务的 64 MiB cgroup 耗尽，`oom/max/oom_kill` 均为零。修复为 4 KiB 分块读取，保留 8 MiB 总上限；不能全局降总上限，因为真实 `/proc/net/route` 超过 1 MiB。测试增加大单次 read 拒绝与累计超限模拟。
3. **一次性服务未随配置更新重跑**：Ops 初始化和快照的 oneshot 增加 `RemainAfterExit=true`，使 NixOS 能在配置变化时重新执行幂等 seed/快照；否则 unit 存在不代表新参数已写入。
4. **部署编排不能等同于激活成功**：Colmena 停在闭包推送阶段时，独立验证发现闭包可能已复制完成、系统仍为旧 profile。必须分开检查传输、profile 和 `/run/current-system`；不能根据终端无新输出判断编译失败，也不能根据新 profile 存在判断服务已更新。除 `nixos-rebuild` 外，操作命令最多 30 秒，超时终止后有限重试，不挂着等待。
5. **同步沙箱的状态查询失败**：t3c 关闭服务动作后仍读取绝对 SysV 状态路径，原包装器访问被屏蔽的 D-Bus，导致 exit 138 和配置一直 pending reload。使用仅在同步沙箱内的只读状态适配器后，配置同步成功，`traffic_ctl config status` 返回 `Configuration is current`。
6. **缓存布局三文件不一致**：只恢复空 storage 和 volume 不够。t3c 的 hosting 仍指向不存在的 volume 1，日志明确提示 `bad volume number [1]` 和 cache disabled。修复为三文件成组保留，并纠正默认隐式 volume 0 对应的自动生成错误 hosting，不重建已有缓存。
7. **压缩统计被误当成 JSON**：同样的恢复沙箱里直接 probe 复现 UTF-8 解码错误 `0x9c`；HTTP 头为 `Content-Encoding: deflate`，响应 4,825 字节，而普通无 Accept-Encoding 请求为 35,924 字节 JSON。gzip/deflate 有界解码后，同一沙箱 probe 成功，避免误重启健康 worker；liveness 失败日志仅输出类型和受限原因，不记录响应正文或秘密。

### 8.2 已观测结果与当前边界

- hkg5 通过已认证的 SSH 系统总线通道停止旧 ATS 后，8089 CLOSE-WAIT 实测为 0；`sockstat` 的 TCP mem 为 27 页，SSH 命令重新能执行。此结果验证了关闭 manager listener 的必要性，**不代表永久修复已经部署完成**。
- tyo0 修补后曾达到 `Proxy -- on`、bridge `ready=true`，HTTPS 业务返回正常鉴权响应；恢复计时器重新启用后失败计数归零。此为历史验证，不再作为当前功能验收节点。
- fra0 的新 Ops 初始化和快照已观察到 active/exited/success，steering 能对 timeout/down 节点发布零副本；曾出现的 `metrics_read_error` 已转为压力降权并重新入池，尚未证明历史每次失败的具体传输原因，不能武断归咎 UID、sandbox 或 1 秒 timeout。
- 部署中曾出现 `Cache Disabled`，因此 worker、TLS 和健康状态通过**不等于缓存命中通过**。本轮已在 sjc0 单独验证真实容量、命中和禁缓存场景，具体证据见 8.4。

### 8.3 测试拓扑与通过标准

`terraform/cdn.tf` 当前声明控制节点仅 `fra0`，加速节点为 `sjc0`、`fra1`、`hkg5`，基准整数权重分别为 5、5、8；`chat` 继续源站直达。功能验收先使用 `fra0/sjc0`，全部通过前不继续部署或测试 hkg5。不增加另一份 Nix 拓扑来绕过生成链。操作者生成输出后，应检查 `cdn.controlNodeNames=["fra0"]`、`cdn.edgeNodeNames=["sjc0","fra1","hkg5"]`，并确认真实地址非空，再先部署两台验收节点。拓扑中已声明但未就绪的节点必须保持零权重；旧注册记录即使仍在 Ops 数据库中，也不应被调度器自动加入新池。

通过标准如下，每项需要实际运行证据：

1. ATS worker 为 on，typed records、模板目录及 loopback listener 正确；桥接连续采样成功，没有 ENOMEM、过期或伪造零指标。
2. TLS 和至少一个真实业务回源有效；响应中的登录要求、Cache-Control、Host 与认证隔离未被改变。
3. 缓存有可写有效存储，可缓存测试资源第二次请求增加 hit 计数；不可缓存或私有响应不能误当作 hit 成功。
4. Monitor 的实时 IPv4/IPv6 状态与节点实际地址族相符，steering 只发布已就绪的声明节点；首轮验收确认 sjc0 可用，未就绪的 fra1/hkg5 为零权重，已移出拓扑的 tyo0 不再发布。
5. 稳定健康并完成 slow start 后保留重复 A/AAAA 副本；资源压力时减少副本，timeout/down/过期时全部副本为零。
6. 健康桥接停止时，DNS 摘除节点并回退该业务源站；root 直接探测仍成功时，自愈不能误重启健康 ATS。恢复后需要新鲜三轮成功并逐级加回。
7. 受控 worker 故障时，本地自愈在预算内恢复整个 ATS，监听队列无持续积压；预算、冷却和状态损坏边界以自动测试验证，避免在生产制造重启风暴。
8. 控制 Monitor 不可用时不得发布全部边缘；`chat` 始终直达配置源站。演练后所有暂停的测试服务恢复，并保留可回滚 profile。

上述功能全部通过后，再对已声明的 hkg5 按逐台部署流程验收，不需要再次把它加入节点清单。当前不继续对 hkg5 推送系统、重启服务或做性能探测；Terraform 输出仍由操作者更新。

### 8.4 两节点实测记录（2026-11-03）

仅在 fra0/sjc0 执行本轮功能测试；hkg5/fra1 没有在此轮部署或探测实验。源站为 fra0 `94.249.174.75` / `2a0e:6a80:3:b60::`，测试边缘为 sjc0 `45.143.130.230` / `2604:a840:101:2d9::a`。

| 场景            | 实测证据                                                                                                | 结果                                |
| --------------- | ------------------------------------------------------------------------------------------------------- | ----------------------------------- |
| 真实磁盘缓存    | `cache.db` 逻辑大小 268,435,456 字节，ATS 可用容量 268,066,816；cache enabled、Proxy on                 | 通过，不是仅配置 RAM cache          |
| 公开资源        | HTTPS `m.dora.im/_matrix/client/versions` 连续 200，Age 从 1 到 2，fresh-hit 从 0 到 2                  | 通过，实际 MISS 到 HIT              |
| 请求 Cookie     | 新 key 两次 GET 携带测试 Cookie 均 200、Age 0，fresh-hit 保持 2                                         | 通过，未存入缓存                    |
| 同 key 对照     | 去掉 Cookie 后同 query 可缓存；随后 live worker 的 fresh-hit 为 3                                       | 排除“该 URL 本来不可缓存”的误判     |
| 客户端 no-store | 新 key 两次 `Cache-Control: no-cache, no-store` 请求均 200、Age 0，fresh-hit 不增                       | 通过                                |
| 响应 no-store   | login 测试路径返回 404 和 `no-cache, no-store, must-revalidate`，两次 live worker fresh-hit 均为 3      | 通过，包括负响应；不以 Age 单独判断 |
| 双栈权威权重    | 稳定后五条重复 A 和五条重复 AAAA，均为 sjc0；/status 两族 records=5                                     | 通过，保持重复记录方式              |
| 未就绪节点      | fra1/hkg5 两族 records=0，tyo0 已不在生成池                                                             | 通过，声明存在不等于可用            |
| chat 直达       | 权威 `route-chat` A 始终为 fra0                                                                         | 通过                                |
| 健康桥接故障    | 停桥接后两族全部摘除、回源站；worker PID 738095 不变、预算 attempts=[]                                  | 通过，没有误重启健康 worker         |
| 桥接恢复        | 独立保护/手动确认恢复后，新鲜三轮成功再逐级恢复至五副本                                                 | 通过，没有使用旧快照凑次数          |
| worker 故障     | 23:36:57 CST 本地恢复记录 restart、attempts=1；PID 738095 到 772129、Proxy on、cache 恢复、CLOSE-WAIT=0 | 通过，早于 90 秒兜底服务执行        |
| Monitor 故障    | 停 Monitor 后 DNS/steering 仍 active；所有节点为 monitor_read_error/零副本，仅返回源站，chat 不变       | 通过，无全节点 fail-open            |

worker 演练的兜底脚本另有一次 **测试设施问题**：23:38:04 的 transient service 缺少裸 `timeout` 的 PATH，因此错误触发了额外重启，PID 变为 774453。该动作不是自愈证据，不算入上表成功判定；独立自愈已在兜底之前证实。所有演练 timer/service 已停止清理。今后的安全保护命令必须使用绝对程序路径或显式 PATH，不能因为交互 SSH 中命令存在就假设 transient service 也存在。

测量缓存计数时优先读 live `/_astats`，manager 的 metric 数据有传播延迟。不要把立即读取的未变化计数当成没命中，也不要把源站带回的 Age 当成唯一证据。

本轮自动检查共 64 项通过：健康/恢复 24、DNS/CoreDNS 21、records/storage 11、Monitor 契约 8。Monitor 完整运行曾触及 25 秒终止限，剩余快照案例单独运行通过，没有提高单命令上限。临时 PostgreSQL 的可选测试本轮跳过；此前隔离事务的幂等测试通过，但不把旧结果充作本轮重跑。启动限额由持久化预算控制，预算/冷却/损坏/时钟回退边界用自动测试覆盖，没有在生产刻意制造三次失败风暴。

演练后的最终检查：fra0 的 Monitor、steering、CoreDNS 全部 active；sjc0 的 worker、健康服务和恢复计时器 active，正常同步返回 success，缓存容量仍为 268,066,816 字节，CLOSE-WAIT 与监听积压为零。权威重新返回 sjc0 的五条 A、五条 AAAA，chat 返回源站；两台均没有残留 `atc-test-*` 计时器。hkg5/fra1 保持未就绪零权重，本轮不对它们部署。

### 8.5 验收范围与残留风险

- 接入 HTTPS、回源响应和匿名/测试 Cookie 缓存规则已验证；没有用真实个人凭据测试所有登录业务，也没有完成每个应用的授权安全审计。
- 源站 TLS 链校验仍需专门审计：历史日志出现过 `Action=Continue` 的 issuer 验证警告，不能把客户端 TLS 成功写成端到端严格校验已通过。
- sjc0 的非 CDN `matrix-rtc-jwt.service` 仍存在独立启动失败，会使全系统 activation 返回 status 4；CDN 的实际 profile 和单元需另行复核。fra0 Zotero 曾有启动期临时告警，不把非 CDN 故障当成缓存/调度未部署，也不在本轮擅自修改这些服务。
- 本轮不是压力基准、GeoIP 测试或三节点真实流量比例测试；重复 RR 的递归去重问题、外部 TTL/serve-stale 与 HTTP 长连接边界仍适用。
- hkg5 的供应商 CPU steal 和永久部署验证没有在本轮解决。源代码准备好不等于该慢节点已经完成上线。
