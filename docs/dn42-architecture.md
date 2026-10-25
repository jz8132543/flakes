# DN42 全互联 SD-WAN 架构与多网络组件隔离实战指南

## 一、 宏观架构总览与分层解耦愿景

本系统基于 **NixOS Flakes** 声明式系统架构，构建了一套兼具**零接触编排（Zero-Touch）**、**高可用多主控动态 SD-WAN**、**eBPF Fake-TCP 协议穿透**、**Babel ETX+RTT 联合动态选路**、**原生 CoreDNS 权威专网解析**、**Mihomo L7 双链路订阅分发**以及**跨层网络绝对隔离**的现代化网络基础设施。

### 1.1 分层架构与核心职责边界

```
┌──────────────────────────────────────────────────────────────────────────┐
│ 7. 可观测性层: Grafana Material ECharts / NodeGraph / Textfile Collector │
├──────────────────────────────────────────────────────────────────────────┤
│ 6. L7 代理分流层: Mihomo (公网 VLESS / Reality + 内网 .dn42 SOCKS5 裂变) │
├──────────────────────────────────────────────────────────────────────────┤
│ 5. 专网权威 DNS 层: ATC CoreDNS (dora.dn42 正向 + rDNS IPv4/IPv6 PTR)     │
├──────────────────────────────────────────────────────────────────────────┤
│ 4. IGP 动态路由层: BIRD 2 (Babel: type wireless, ETX + RTT 联合寻优)     │
├──────────────────────────────────────────────────────────────────────────┤
│ 3. 抗封锁与网络隔离层: eBPF Fake-TCP (Mimic) + nftables raw notrack + Policy │
├──────────────────────────────────────────────────────────────────────────┤
│ 2. SD-WAN 动态控制面: 多主控 (fra0/sjc0/cu) + 多端点 XFRM 并发探路 Agent │
├──────────────────────────────────────────────────────────────────────────┤
│ 1. 基础设施编排层: Terraform (dn42.tf, hosts.tf) -> data.json 单一数据源  │
└──────────────────────────────────────────────────────────────────────────┘
```

| 架构层级                | 核心组件与模块路径                                               | 核心职责与设计边界                                                                                                                                                  |
| :---------------------- | :--------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **1. 基础设施编排层**   | `terraform/dn42.tf`<br>`lib/data/data.json`                      | **新增节点零配置**：根据机器列表自动推导节点 ID、分配 `172.20.232.<id>` 与 `fd53:90fd:4bb6:<id>::1`；单覆盖字典声明；剥离变更易碎的临时时间戳。                     |
| **2. SD-WAN 控制面**    | `dn42/mesh.nix`<br>`dn42-sdwan-agent`<br>`dn42-sdwan-controller` | **三主控互备 + 多端点全网并发探路**：纯 Bash+jq+socat 轻量实现，零 Python 依赖。支持单主机多公网线路（如 cu 的 4 条端点）全网自动展开为独立 XFRM 网卡。             |
| **3. 协议穿透与隔离层** | `pkgs/mimic/`<br>`dn42/base.nix`<br>`overlay-isolation.nix`      | **Fake-TCP 穿透 + 内核协议栈隔离**：将 UDP 4500 包装为伪 TCP 突破运营商封锁；nftables raw notrack 杜绝 conntrack 丢包；Priority 80/81/90 策略路由保障底层隧道直通。 |
| **4. 内部动态路由层**   | `dn42/mesh.nix` (BIRD 2)                                         | **ETX 丢包率 + RTT 往返时延联合寻优**：通配接口 `dn42x-*` 采用 `type wireless`，实时感知线路丢包与 Bufferbloat 拥塞，秒级无缝倒换。外部 eBGP 严格隔离。             |
| **5. 专网权威 DNS 层**  | `services/networking/dn42/base.nix` (dnsmasq)                    | **原生树状 DNS 权威解析**：由 DN42 模块内的 dnsmasq 托管 `dora.dn42` 及反向解析 PTR Zone，与 ATC CDN 的 Traffic Router 完全解耦，不共享代码与端口。                 |
| **6. L7 代理与分流层**  | `services/sub.nix`<br>`desktop/mihomo.nix`                       | **双链路节点裂变与免打标跨端通用**：自动裂变公网与 `.dora.dn42` 节点；修复 TUN 路由自捕获死锁；保障手机端（Box for KernelSU）免打标全局可用。                       |
| **7. 实时监控层**       | `metrics/client.nix`<br>`hosts.json`                             | **Material Design 拓扑大屏**：纯 Bash textfile 采集器导出吞吐/延迟/丢包；ECharts 拓扑流光图在线变绿、离线变红，全数据驱动无硬编码。                                 |

---

## 二、 核心子系统深度剖析与实现细节

### 2.1 零接触编排与数据管线 (`terraform/dn42.tf`)

#### 1. 自动化默认值与单一覆盖字典模式

传统 DN42 配置往往需要为每台机器编写数十行重复的端口、密钥、IP 配置。本架构在 `terraform/dn42.tf` 中实现了完全自动化的确定性推导：

- **节点 ID 自动推导**：直接读取 `local.hosts[name].host_indices[0]`，自动映射出唯一节点 ID（1 ~ 99）。
- **确定性内网 IP**：IPv4 固定为 `172.20.232.<id>`，IPv6 固定为 `fd53:90fd:4bb6:<id>::1`。
- **单一覆盖字典 (`dn42_overrides`)**：绝大多数主机仅需出现在 `hosts.tf` 中，`dn42.tf` 无需添加任何资源块；仅当节点拥有多线路端点（如 `cu` 的 4 条线路）或充当主控时，才在 `dn42_overrides` 中按需声明。

#### 2. 剥离 `build_time` 消除 Terraform 伪变更

- **痛点**：此前在 Terraform 中通过 `TF_VAR_dn42_build_time = $(git log -1 --format=%ct)` 注入构建时间，导致即使基础设施无任何变动，每次执行 `terraform apply` 都会导致 `data.json` 全量变更，掩盖真实基础设施 diff。
- **解法**：彻底从 `dn42.tf` 与 `devshell/terraform.nix` 移除 `build_time` 输出；节点版本号转由 Nix Flake 原生的 `self.lastModified`（Git 提交时间戳）驱动。此举实现了：**Terraform 只描述物理拓扑（静），Nix 编译期自动捕获版本号（动）**。

#### 3. if_id 编码约束断言

在 `terraform/dn42.tf` 中植入编译器级断言：

```hcl
data "assert_test" "dn42_node_id_range" {
  test  = length([for name, node in local.dn42_nodes : name if node.id < 1 || node.id >= 100]) == 0
  throw = "dn42 node id must be within 1..99 (symmetric if_id encoding min*1000 + max*10 + k)"
}

data "assert_test" "dn42_endpoint_count" {
  test  = length([for name, node in local.dn42_nodes_normalized : name if length(node.endpoints) > 9]) == 0
  throw = "dn42 node must publish at most 9 endpoints (symmetric if_id encoding min*1000 + max*10 + k)"
}
```

---

### 2.2 SD-WAN 动态控制面与自愈 Agent (`dn42/mesh.nix`)

#### 1. 三主控高可用与轻量注册中心 (`dn42-sdwan-controller.service`)

- **部署位置**：默认常驻在拥有稳定公网双栈 IP 的 `fra0`、`sjc0`、`cu` 节点上，监听 `TCP 54500`。
- **极简零依赖实现**：使用系统原生 `socat` + `jq`，利用 `flock` 保证写安全，内存开销 < 5MB。
- **主控互同步算法**：各主控定时通过 `--pull-peers` 相互抓取对方的 `/peers`，基于 `build_time`（`self.lastModified`）单调递增原则合并：
  $$\text{Merged}[k] = \begin{cases} \text{Remote}[k], & \text{if } \text{Remote}[k].\text{build\_time} \ge \text{Local}[k].\text{build\_time} \\ \text{Local}[k], & \text{otherwise} \end{cases}$$
- **抗灾韧性**：即使全部三台主控同时宕机，各节点本地均有 `/var/lib/dn42-sdwan/peers.json` 持久化缓存以及 Flake 编译期内嵌的 `bootstrapPeersJson`，存量隧道毫秒不中断。

#### 2. 自愈 Agent (`dn42-sdwan-agent.service`)

- **定时调度**：每 30 秒执行一次同步。
- **自愈式握手补偿**：
  为避免死机节点（如离线 VPS）阻塞 agent，导致系统级定时器停摆，设计了带超时的非阻塞握手探测：
  ```bash
  EXISTING_SAS=$(swanctl --list-sas 2>/dev/null | grep -oE '^[a-z0-9-]+:' | tr -d ':' | sort -u || true)
  for inst in "${ALL_TUNNEL_INSTANCES[@]}"; do
    IFS=';' read -r _ _ t_conn _ _ _ t_saction _ _ _ _ <<< "$inst"
    [ "$t_saction" = "start" ] || continue
    # 仅对尚未建立 IKE_SA 的连接补发握手，绝不干扰已建立的存量隧道（避免 rekey 抖动）
    if ! printf '%s\n' "$EXISTING_SAS" | grep -qx "$t_conn"; then
      timeout 8 swanctl --initiate --child "$t_conn" 2>/dev/null || true
    fi
  done
  ```
- **增量热重载**：仅在 `/run/swanctl/conf.d/` 生成的配置文件内容与既有配置发生哈希变化时，才触发 `swanctl --load-all`，实现配置无感刷新。

---

### 2.3 多端点全路径探路与无冲突对称 `if_id` 算法

#### 1. 核心业务痛点

`cu` 节点拥有 4 条独立公网线路：移动 IPv4 (`cm4`)、电信 IPv4 (`ct4`)、移动 IPv6 (`cm6`)、电信 IPv6 (`ct6`)。传统 SD-WAN 只允许配置单一 IP，导致其他节点只能二选一建链，无法感知其余线路的通断与时延。

#### 2. 对称 `if_id` 数学算法

Linux 内核的 XFRM 虚拟网卡（`xfrm_interface`）依赖 32 位整型 `if_id` 将加解密流量与网卡精确绑定。
设本机节点 ID 为 $A$，对端节点 ID 为 $B$，目标子线路在对端端点数组中的 1-based 序号为 $k$（$k \in [1, 9]$）：

$$\text{if\_id} = \min(A, B) \times 1000 + \max(A, B) \times 10 + k$$

**数学性质**：

1. **完全对称性**：$\min(A, B)$ 与 $\max(A, B)$ 保证了两端算出的基准数值完全相同，不受发起方与接收方身份影响。
2. **多线路正交性**：$+ k$ 确保了同一对主机之间的多条物理链路拥有完全隔离的内核 XFRM 接口。
3. **零冲突域**：在节点 ID $\le 99$ 且端点数 $\le 9$ 的约束下，任意两对主机或两条子线路的 `if_id` 绝不碰撞。

#### 3. Initiator 与 Responder 接口对称展开算法

为了保证两端的内核 XFRM 接口集合完全镜像闭合，Agent 统一执行单循环展开：
设对端已发布端点数为 $N_{\text{peer}}$，本机发布端点数为 $N_{\text{self}}$，循环上限为 $K_{\max} = \max(N_{\text{peer}}, N_{\text{self}})$：

- **当 $k \le N\_{\text{peer}}$ 时（发起端 Initiator）**：
  创建网卡 `dn42x-<peer>-<ep_name>`，配置 `remote_addrs = ep.addr`，`start_action = start`，主动向对端第 $k$ 个公网端点并发建链。
- **当 $N\_{\text{peer}} < k \le N\_{\text{self}}$ 时（被动端 Responder）**：
  创建网卡 `dn42x-<peer>-r<k>`，配置 `remote_addrs = %any`，`start_action = none`，监听并接收入站的对应 `if_id` SA。

#### 4. 接口版本残留与强制重建保护

针对节点升级后旧接口占用错误 `if_id` 导致 Child SA 无法绑定的顽疾，在网卡创建前增加了深度探测：

```bash
cur_if_id=$(ip -d link show "$t_iface" 2>/dev/null | grep -oE 'if_id 0x[0-9a-f]+' | grep -oE '0x[0-9a-f]+' || true)
if [ -z "$cur_if_id" ] || [ "$(( cur_if_id ))" -ne "$t_if_id" ]; then
  # 杜绝 EEXIST：若有残留网卡占用了目标 if_id，先行强制清除
  old_dev=$(ip -d link show type xfrm 2>/dev/null | awk -v id="if_id 0x$(printf '%x' "$t_if_id")" '
    /^[0-9]+: dn42x-/ { iface=$2; sub(/:.*/,"",iface); sub(/@.*/,"",iface) }
    $0 ~ id { print iface }
  ' || true)
  if [ -n "$old_dev" ] && [ "$old_dev" != "$t_iface" ]; then
    ip link del "$old_dev" 2>/dev/null || true
  fi
  [ -n "$cur_if_id" ] && ip link del "$t_iface" 2>/dev/null || true
  ip link add "$t_iface" type xfrm dev lo if_id "$t_if_id" 2>/dev/null || true
fi
```

---

### 2.4 内核协议栈隔离与 Mimic (Fake-TCP) 无补丁穿透

#### 1. 突破运营商封锁的物理原理

国内部分省份运营商（如某些城域网、校园网、移动 4G/5G）会对出入站 `UDP 4500` 和未知高端口 UDP 施加严格的丢包、QoS 限速甚至阻断。
**Mimic** 通过 eBPF（XDP + TC）在物理网卡最底层拦截 IPsec ESP/NAT-T 报文，将其伪装成标准 TCP 三次握手及带 ACK 序列号的 Fake-TCP 流；对端在网卡驱动层将其还原回原始 UDP，使得流量在公网呈现为普通 TCP 连接。

#### 2. 云主机驱动兼容与 ethtool 卸载清洗

- **XDP SKB 模式**：云厂商 VPS 普遍使用 `virtio_net` 虚拟网卡，Native XDP 往往不支持尾部扩展（12 字节 Mimic 标记）。强制使用 `--xdp-mode skb` 保证 100% 宿主机兼容。
- **硬件分段卸载彻底清洗**：
  在网卡启动前通过 `ethtool` 强制关闭网卡硬件聚合与分段：
  ```bash
  ethtool -K "$IFACE" gro off rx-gro-hw off lro off gso off tso off tx off rx off
  ```
  **原因**：若开启 GRO，内核在 XDP 之前就会把多个 Fake-TCP 报文聚合成超大段，破坏 Mimic 的 12 字节包尾魔数；关闭后确保内核在进入网络栈前完成干净的单包还原。

#### 3. netfilter 连接跟踪规避 (`raw notrack`)

Fake-TCP 报文并没有真正经过 Linux 内核协议栈的 TCP 握手。如果不做干预，内核的 `nf_conntrack` 模块会将其判定为 `INVALID` 状态并丢弃。
在 `nixos/modules/services/networking/dn42/base.nix` 中，通过 nftables 在优先级 `-300`（raw 阶段）对全集群所有隧道端口注入 `notrack`：

```nftables
table inet dn42-raw-notrack {
  chain raw_prerouting {
    type filter hook prerouting priority raw; policy accept;
    udp sport { 500, 4500, 50568 } notrack
    udp dport { 500, 4500, 50568 } notrack
    tcp sport { 500, 4500, 50568 } notrack
    tcp dport { 500, 4500, 50568 } notrack
  }
}
```

---

### 2.5 内部动态路由层：BIRD 2 Babel 动态选路模型

在 `mesh.nix` 中，通配所有 XFRM 网卡应用 Babel 配置：

```text
protocol babel dn42_babel {
  interface "dn42x-*" {
    type wireless;
    rxcost 256;
    hello interval 2 s;
    update interval 8 s;
    send timestamps yes;
    rtt min 10 ms;
    rtt max 300 ms;
    rtt cost 512;
    rtt decay 84;
    extended next hop yes;
  };
}
```

#### 1. 为什么必须选 `type wireless`？

- Babel 的默认 `type tunnel` 模式主要针对稳定隧道，采用粗粒度离散采样，只要丢包率低于 25%，其 Metric 几乎不会增加，无法感知中度丢包。
- `type wireless` 开启了 **ETX (Expected Transmission Count)** 连续丢包率算法：
  $$\text{Metric}_{\text{base}} = \frac{\text{rxcost}}{d_f \times d_r}$$
  其中 $d_f$ 为前向交付率，$d_r$ 为反向交付率。哪怕链路产生 5% 的偶发丢包，Metric 也会平滑上升，使 BIRD 敏锐规避丢包严重的线路。

#### 2. RFC 9079 时间戳测距与反向链路确认（IHU）

- **两步确认机制**：
  本机发送 Hello 附带时间戳 $t_1$；对端收到后必须在回送给本机的 **IHU (I Hear You)** 报文中原样回显 $t_1$ 并附带接收时刻 $t_2$。本机收到 IHU 时刻为 $t_3$，端到端 RTT 即为：
  $$\text{RTT} = t_3 - t_1$$
- **65535 根因揭秘**：若两端接口 `if_id` 不一致或单向被防火墙拦截，导致 IHU 报文无法送达，本机的 `txcost` 永远为 0，BIRD 状态机（`proto/babel/babel.c:600`）就会将 Metric 判定为不可达的顶格值 `BABEL_INFINITY (65535)`。

#### 3. Bufferbloat 拥塞自愈与衰减模型

综合 Metric 计算公式为：
$$\text{Metric} = \frac{256}{d_f \times d_r} + 512 \times \text{clamp}\left(\frac{\text{RTT} - 10}{290}, 0, 1\right)$$

- 低于 10ms：完美直连，无延迟惩罚（RTT Cost = 0）。
- 10ms ~ 300ms：根据时延线性增加惩罚。当一条小水管满载产生排队延迟（Bufferbloat）导致 RTT 飙升至 200ms 时，其 Metric 将增加约 335，BIRD 立即自动将流量切往备用端口。
- `rtt decay 84`：采用 EWMA 平滑指数衰减，防止偶发网络毛刺引起路由震荡（Route Flapping）。

---

### 2.6 专网权威 DNS 与反向解析体系 (`atc/router.nix`)

彻底摒弃静态 `/etc/hosts` 注入，全面切换为标准树状 DNS 解析架构：

```
                    【客户端 / Mihomo】
               查询 *.dora.dn42 / 反向 PTR
                            │
              nameserver-policy: 172.20.232.1:53
                            ▼
              【fra0: ATC CoreDNS 权威服务器】
          (同时监听公网 IP 与 DN42: 172.20.232.1:53)
                            │
       ┌────────────────────┼────────────────────┐
       ▼                    ▼                    ▼
  [正向 Zone]         [IPv4 反向 Zone]     [IPv6 反向 Zone]
  dora.dn42.zone     0/26.232.20.172.in-  6.b.b.4.d.f.0.9...
                     addr.arpa.zone       ip6.arpa.zone
```

1. **ATC CoreDNS 权威多 Zone 承载与 Anycast 递归联动**：
   - 监听地址绑定至 `172.20.232.1:53` 与 `[fd53:90fd:4bb6:1::1]:53`；
   - 自动生成 `dora.dn42` 正向解析，包含集群所有主机的双栈 A / AAAA 记录，并支持在 `terraform/dn42.tf` 中声明自定义别名 (CNAME) 与独立 A / AAAA 解析；
   - 自动生成 `0/26.232.20.172.in-addr.arpa`（IPv4 PTR）与 `6.b.b.4.d.f.0.9.3.5.d.f.ip6.arpa`（IPv6 PTR）；
   - **DN42 全局根转发**：配置 `dn42:53` Server Block，仅针对非 `dora.dn42` 的其他所有 DN42 域名（如 `*.dn42`），自动 forward 至 DN42 官方 Anycast 根与递归服务器（`172.20.0.53`、`172.23.0.53`），实现完整的 DN42 内网递归解析。
2. **DN42 官方 Registry 合规注册（PR #7554 已合并）**：
   - 官方主仓库 `dn42/registry:master` 已成功合并我们的 PR #7554；
   - 在 `data/dns/dora.dn42` 中声明权威名称服务器：
     ```text
     domain:             dora.dn42
     admin-c:            TIPPY-DN42
     tech-c:             TIPPY-DN42
     mnt-by:             TIPPY-MNT
     nserver:            ns1.dora.dn42 172.20.232.1
     nserver:            ns1.dora.dn42 fd53:90fd:4bb6:1::1
     source:             DN42
     ```
   - 在 `data/inetnum/172.20.232.0_26` 和 `data/inet6num/fd53:90fd:4bb6::_48` 中声明反向委派：`nserver: ns1.dora.dn42`；
   - 全球 Anycast DNS（`172.20.0.53` / `172.23.0.53`）已原生支持向我们的 CoreDNS 递归解析 `*.dora.dn42`。

3. **全网多层级 DNS 解析统一协同矩阵**：
   所有节点、客户端与应用层服务，对 DN42 与 Tailscale 的域名解析均遵循统一的分流拓扑：
   | 解析层级 / 组件  | 运行节点 / 监听端口         | 内部域名 (`*.dora.dn42`)              | DN42 全局域 (`*.dn42`)                       | Tailscale 域 (`*.ts`)        |
   | :--------------- | :-------------------------- | :------------------------------------ | :------------------------------------------- | :--------------------------- |
   | **CoreDNS**      | `fra0` (53, DN42 IP)        | 本地权威 Zone 直解                    | 转发至 Anycast `172.20.0.53` / `172.23.0.53` | - (专网隔离)                 |
   | **SmartDNS**     | 全集群节点 (127.0.0.1:5335) | `172.20.232.1` (权威) + `172.20.0.53` | Anycast `172.20.0.53` / `172.23.0.53`        | `100.100.100.100` (MagicDNS) |
   | **Dnsmasq**      | 全集群节点 (127.0.0.1:53)   | `172.20.232.1` + `172.20.0.53`        | Anycast `172.20.0.53` / `172.23.0.53`        | `100.100.100.100@tailscale0` |
   | **AdGuard Home** | 边缘服务节点 (0.0.0.0:5300) | `[/dora.dn42/]172.20.232.1` + Anycast | `[/dn42/]172.20.0.53` / `172.23.0.53`        | `[/ts/]100.100.100.100`      |
   | **Mihomo (TUN)** | 移动端 / 客户端订阅         | `172.20.232.1:53` + `172.20.0.53`     | `172.20.0.53` + `172.23.0.53`                | `100.100.100.100:53`         |

---

## 三、 跨层多网络组件冲突与终极解决方案

本系统同时运行了 **DN42 (XFRM+Babel)**、**Tailscale**、**EasyTier** 以及 **Mihomo (TUN)**。各组件在 Linux 内核网络栈中争夺默认路由、`iptables/nftables` 链和 DNS 端口。以下为遭遇的致命冲突与根治方案：

### 3.1 冲突一：Mihomo TUN 路由自捕获死锁与断网雪崩（Routing Loop）

#### 1. 深度病因剖析

Mihomo TUN 开启后，会在内核中创建虚拟网卡 `Meta`，并向策略路由表 `table 2022` 写入全局接管路由（`0.0.0.0/1`、`128.0.0.0/1` 和 `::/1`）。

- **为什么必须设为 `auto-detect-interface: false`？**
  如果开启 `auto-detect-interface: true`，Mihomo 会自动嗅探系统默认网关（如 Wi-Fi 网卡 `wlp4s0`），并在所有出站代理 Socket 上强行执行 `setsockopt(fd, SOL_SOCKET, SO_BINDTODEVICE, "wlp4s0")`。
  一旦 Socket 被绑定到特定物理网卡，**该流量将彻底绕过内核路由表（FIB）**。本来应该发往 `172.20.232.1:1080`（DN42 SOCKS5 节点）的流量被强行甩给家用路由器丢弃，导致**所有 DN42 节点必死**。
- **Netfilter 标记滞后性导致的自捕获死锁（Initial Route Lookup 陷阱）**：
  在 Linux 网络栈中，本机进程发起 `connect()` 时，**内核初始选路（Initial Route Lookup）与源 IP 挑选发生在 Netfilter mangle 链之前**：
  1. Mihomo（UID 998）发起的代理建连请求在未打标时（`mark == 0`）即执行初次选路；
  2. 因未命中针对 mark 的规则，命中了优先级 9003 的 TUN 规则（`from 0.0.0.0 iif lo lookup 2022`）；
  3. 内核直接选定 `dev Meta` 为出站设备，并将源 IP 固化为 TUN 接口地址 **`198.18.0.1`**；
  4. 随后包进入 Netfilter 打上 `0x1`，但 `ip_route_me_harder` 无法为已被选定为 `198.18.0.1` 的 TCP SYN 包更改源 IP；
  5. 目的地为节点公网 IP（如 `45.143.130.230:8555`）的包进入 TUN，被 Mihomo 误当作待代理的非 CN 流量，**再次触发外联，形成指数级自捕获死循环，数十秒内产生数万并发连接，CPU 瞬间 100%、内存暴涨至 2GB+**。
- **断网 / Wi-Fi 漫游时的雪崩机制**：
  当 Wi-Fi 断开或漫游切换热点瞬间，物理网卡的 `default` 路由暂时消失。Mihomo 尝试重连节点时在 `main` 表中查无路由，全量掉入 TUN 产生自环风暴；海量并发占死 CPU 与内核 Socket 缓冲区，导致 NetworkManager 无法配置网络（`Resource temporarily unavailable`），连通性检查（Captive Portal）超时导致 Wi-Fi 频发 `DEAUTH` 断开，陷入无法自愈的震荡。

#### 2. 终极根治方案：内核 UID 级策略路由与断网熔断

无需在订阅配置中手动维护任何公网节点的 IP 排除列表，在操作系统内核层（`nixos/modules/desktop/mihomo-routing.nix`）实现前置拦截：

1. **多端订阅（`sub.nix`）彻底解耦**：
   - 保持 `auto-detect-interface = false;`（兼顾手机与 DN42 多路径选路）；
   - 绝不往 `route-exclude-address` 注入动态节点公网 IP（新增节点零变更、零构建）；
   - 移除 `proxy-server-nameserver`，交由 `nameserver-policy` 分流树处理，杜绝公网 DNS 抢答造成的 NXDOMAIN 负缓存死锁。
2. **Priority 8980: UID 级前置路由拦截（Initial Route Lookup 阶段介入）**：
   ```bash
   ip -4 rule add uidrange 998-998 lookup main priority 8980
   ip -6 rule add uidrange 998-998 lookup main priority 8980
   ```
   **物理机理**：Linux 内核在进程调用 `connect()` 的第 0 毫秒就知晓 `sock->sk_uid == 998`。
   在选择出站网卡和源 IP 之前，该规则强制让 Mihomo 进程查 `main` 表：
   - 连公网节点：自动匹配 Wi-Fi/物理网卡，源 IP 正确绑定为物理 IP；
   - 连 DN42 节点：自动匹配 `dn42x-*` 隧道，源 IP 正确绑定为 `172.20.232.x`；
   - `dev Meta` 与 `198.18.0.1` 绝无机会被选为出站设备！
3. **Priority 8985: 断网硬熔断保护（彻底杜绝 CPU 100% 与网络锁死）**：
   ```bash
   ip -4 rule add uidrange 998-998 unreachable priority 8985
   ip -6 rule add uidrange 998-998 unreachable priority 8985
   ```
   **物理机理**：当 Wi-Fi 断开、`main` 表没有默认网关时，Mihomo 的所有外部建连请求在命中 8980 失败后，**立即命中 8985 熔断规则**，内核在 0ms 瞬间返回 `ENETUNREACH`（Network is unreachable）报错。
   出站连接立刻失败并等待，**绝不可能穿透掉入 priority 9003 (`table 2022` / TUN)**！
   彻底消除了断网漫游时的自捕获死循环风暴，CPU 占用稳定为 0%，Wi-Fi 秒级完成漫游重连。
4. **Priority 8996 / 8998: 本机出站 TUN 接管与 SSH/组播恒定旁路**：
   - **病因（代理全绿却打不开 Google）**：Mihomo `auto-route` 在 `stack: system` 下只生成 `not from all iif lo` / `from 0.0.0.0 iif lo` 规则，同时它会追加一条 DNS 保护规则 `9002: not from all dport 53 lookup main suppress_prefixlength 0`。该规则把所有**非 DNS** 的本机出站全部旁路进 `main` 表，于是 `Meta` 网卡与 `oifname "Meta" ... redirect to :32337` 的计数器恒为 0——浏览器流量根本不进 TUN，只能直连被污染的 DNS 结果（如 `www.google.com -> 104.244.42.197` / `2001::1`）并超时。表象极具迷惑性：`curl --proxy 127.0.0.1:7890` 与 WebUI 全部正常，唯独不走代理的应用打不开境外站点。
   - **Priority 8996**：SSH 端口与组播地址直连 `main` 表。SSH 旁路由原先依赖 nftables `route_output` 打标（受 route hook 与 nat redirect 先后时序影响）升级为 **FIB 级恒定生效**；组播（`224.0.0.0/4`、`ff00::/8`）则避免 mDNS / SSDP 发现报文被丢进 TUN、源地址被篡改成 `198.18.0.1`。
     ```bash
     ip -4 rule add to 224.0.0.0/4 lookup main priority 8996
     ip -6 rule add to ff00::/8 lookup main priority 8996
     ip -4 rule add ipproto tcp dport 22 lookup main priority 8996
     ```
   - **Priority 8998**：`not fwmark 0x1/0x1 lookup 2022`，把其余未打标的本机出站**在初始选路阶段就交还给 TUN**。其优先级高于 9002，因此能穿透那条 DNS 保护规则；而 8980/8985/8990/8995 与 DN42 的 80/81/90 均位于更前优先级，防回环、断网熔断、专网直通语义完全不变。
   - **为什么不会误伤专网与本地流量**：`table 2022` 对 `172.20.0.0/14`、`10.0.0.0/8`、`100.64.0.0/10`、`fd00::/8` 及国内公共 DNS 地址本就没有路由，查询失败后内核按优先级**续降**到 `main` 表；IPv4 广播、环回与 IPv6 链路本地组播由 `local` 表（priority 0）先行接管；ICMP/PMTUD 由 priority 90 放行；容器流量位于独立 netns，不受主机策略路由影响。
   - **宕机不雪崩**：Mihomo 停止时 `Meta` 随之消失、`table 2022` 清空，未打标流量自动续降 `main` 表直连（实测百度 200、DNS 解析正常），重启后境外访问立即恢复，完全符合"关掉 Mihomo 时直连不断网"的设计预期。

---

### 3.2 冲突二：fwmark 0x1 与 Android (Box for KernelSU) 全局断网

#### 1. 深度病因剖析

- Linux 桌面系统只有一张主路由表与少量策略表，给进程打上 `fwmark 0x1` 导向 `table main` 是标准的防回环实践；
- 但 Android 操作系统为了支持多用户隔离、双卡流量计费、热点与 Wi-Fi 切换，内部维护了 40 多张基于 UID 的策略路由规则。Box for KernelSU 本身在底层也依赖特定的 mark（如 `0xff`）防回环；
- **如果在共享的 `mihomo.yaml` 订阅中强行塞入 `routing-mark: 1`**：手机上 Mihomo 发出的所有网络连接都会被打上全局 `0x01` 标记，彻底破坏 Android 底层基于 UID 的网络策略判定，导致手机连入 Wi-Fi 后被系统防火墙无差别 drop，产生**手机全局断网**。

#### 2. 终极解法

- **多端订阅配置文件（`sub.nix`）内部严禁出现 `routing-mark` 配置**；
- 电脑端（NixOS）的防回环能力完全由系统级 `mihomo-routing.nix`（通过 nftables `skuid 998` 匹配守护进程）在操作系统层面独立承载；
- 手机端交给 Box for KernelSU 自身的 VpnService / iptables 机制自闭环，一套订阅在手机与电脑间完美通用。

---

### 3.3 冲突三：本地 127.0.0.1:53 Fallback 循环死锁

#### 1. 深度病因剖析

在手机（Box for KernelSU）上的拓扑关系为：
$$\text{App} \xrightarrow{\text{DNS}} \text{AdGuardHome (:53)} \xrightarrow{\text{上游}} \text{Mihomo (:1053)}$$
如果订阅配置将 `fallback` 或 `nameserver` 填上了 `127.0.0.1:53`：

1. 手机 App 发送查询给 AdGuardHome (`:53`)；
2. AdGuardHome 过滤广告后交给上游 Mihomo (`:1053`)；
3. Mihomo 解析境外域名触发 fallback，向 `127.0.0.1:53` 发包；
4. AdGuardHome 收到后又当作新查询塞给 Mihomo (`:1053`)；
5. **死锁达成**：UDP 报文在 53 与 1053 端口间以每秒数千次频率死循环，CPU 瞬间 100%、端口耗尽、手机彻底断网。

#### 2. 终极解法：分层 Fallback 各司其职

- **彻底从共享订阅中清除 `127.0.0.1`**；
- **手机的容灾**：直接在 AdGuardHome 上游设置中，将备用（Fallback）上游填为公共 DNS（`223.5.5.5`）；Mihomo 异常时 AGH 自动回退，永不成环；
- **电脑的容灾**：电脑系统的 `/etc/resolv.conf` 指向本地 Dnsmasq，Dnsmasq 内置了向 DHCP/局域网 DNS 的向下回退机制，根本无需 Mihomo 插手。

---

### 3.4 冲突四：底层网络策略路由 (Policy Routing) 与防火墙隔离

为防止 ESP 底层报文、IKE 协商包以及 Mimic Fake-TCP 报文被上层 TUN 捕获，在 `dn42/base.nix` 中部署了独立于任何上层应用的 3 条底层策略路由：

```
Priority 80:  ip rule add ipproto esp lookup main            (v4 + v6)
Priority 81:  for proto in udp tcp; do for port in <allClusterTunnelPorts>; do
                ip rule add ipproto $proto sport $port lookup main
                ip rule add ipproto $proto dport $port lookup main
              done done                                      (v4 + v6)
Priority 90:  ip rule add to 172.20.0.0/14 lookup main
              ip rule add to 10.0.0.0/8 lookup main
              ip rule add to 172.31.0.0/16 lookup main
              ip rule add ipproto icmp lookup main          (PMTUD 差错报文)
              ip -6 rule add to fd00::/8 lookup main
              ip -6 rule add to fe80::/10 lookup main
              ip -6 rule add ipproto ipv6-icmp lookup main   (Packet Too Big)
```

- **Priority 80**：保障 ESP 密文报文查 main 表直出主网卡。
- **Priority 81**：针对全网所有隧道端口（500, 4500, 5056x），对 UDP 和 TCP 双协议双向豁免，确保底层 Mimic Fake-TCP 握手包绝不落入任何 TUN 网卡。
- **Priority 90**：保障 DN42 内网流量与 PMTUD 差错报文走 BIRD 最优路径，防止被代理接管。
- **职责单点权威化与严禁误删 8980**：
  - 此前 `overlay-isolation.nix` 曾误包含 `while ip -4 rule del priority 8980 ...` 清理旧 table 200 的逻辑。但这直接导致了致命的级联瘫痪：删掉 `8980`（`uid 998 lookup main`）后，仅留下 `8985`（`uid 998 unreachable`），导致 Mihomo (UID 998) 自身发出的所有直连和代理请求被内核当场处死，TUN 捕获流量后全机彻底断网！
  - 现已彻底规范：`overlay-isolation.nix` 严禁碰触 `Priority 8980`；同时 `Priority 80/81/90` 全权由 `dn42/base.nix` 单点维护（其拥有完整的集群端口表），`overlay-isolation.nix` 仅专注于 `Priority 8990`（Overlay 标记流量直通 main 表）；所有规则写入均附加 `2>/dev/null || true`，保证绝对幂等安全。
- **Mesh 信任防火墙**：在 nftables 链注入放行规则，来自 `dn42` 与 `dn42x-*` 虚拟网卡的内网流量全局放行，使 `.dora.dn42` SOCKS5 代理、SSH、DNS 开箱即用，公网端口依然受到严密防护。

---

### 3.5 冲突五：开机时序与守护进程挂起死锁（NetworkManager-wait-online 与虚拟网卡干扰）

#### 1. 深度病因剖析

在桌面/笔记本（如 ARX8）环境中，大量基础服务依赖 `network-online.target`（包括 `mihomo.service`、`strongswan-swanctl.service`、`traefik.service`、`tcp-brutal-china-rules.service` 等）。
开机时出现“概率性连不上外网”，其关键根因在于：

1. **NetworkManager 默认纳管了虚拟网卡**：NetworkManager 默认会去监控 `dn42`（dummy 网卡）以及动态创建的 `xfrm*`、`Meta`、`tailscale0` 等。这些网卡在开机瞬间尚未完成密钥协商或未分配常规 DHCP IP，导致 NetworkManager 将其视为“未稳定接口”；
2. **`nm-online -s` 的设计缺陷**：`NetworkManager-wait-online.service` 默认执行 `nm-online -s -q`（等待全网卡启动稳定）。由于虚拟网卡状态未达标，该命令会**硬等 60 秒直至超时失败**；
3. **级联雪崩**：在开机整整 60 秒内，`network-online.target` 无法到达，导致 `mihomo.service` 迟迟无法启动。用户登录桌面发起网络请求时，既无代理也无 TUN；若直接强行关闭 `NetworkManager-wait-online.enable = false`，又会导致 `strongswan`、`mihomo` 在 Wi-Fi 尚未连通、尚未获取物理 IP 前盲目抢跑，引发启动崩溃。

#### 2. 终极根治方案：黑名单排除虚拟接口 + 物理网卡快速连通探测

在 `nixos/modules/desktop/network-manager.nix` 中：

1. **黑名单彻底排除虚拟网卡**：
   ```nix
   networking.networkmanager.unmanaged = [
     "interface-name:dn42*"
     "interface-name:xfrm*"
     "interface-name:Meta"
     "interface-name:tailscale*"
     "interface-name:easytier*"
   ];
   ```
   - **为什么不影响 strongswan 与 IPsec SA？**
     `unmanaged` 是 NetworkManager 专属指令，意思是“NetworkManager 不要给这些网卡发 DHCP，不要尝试重命名或修改其 MTU”。这些网卡是由内核与 `strongswan`、`bird`、`mihomo` 自行创建并管理的，禁止 NetworkManager 插手介入不仅毫无负面影响，反而是生产环境防止 IP 被冲掉的标准保护措施。
2. **恢复原生 wait-online 快速通过**：
   一旦虚拟网卡通过 `unmanaged` 排除，NetworkManager 不再无意义死等虚拟接口，原生的 `nm-online -s -q` 在物理接口连接后瞬间（0.02 秒）成功返回，无需缩短超时或暴力关闭，`network-online.target` 安全准时到达。

---

### 3.6 冲突六：全系统 DNS 并发竞速与防污染架构（国内外通用）

#### 1. 深度病因剖析

在公共基础网络模块（`network-base.nix`）中：

- **此前配置**：SmartDNS 将 `1.1.1.1` 和 `8.8.8.8` 设为主用 DoH，而将国内服务器（`223.5.5.5`）打上了 `-fallback`；同时 Dnsmasq 配置了 `strict-order = true`；
- **致命痛点**：
  1. 在国内机器上，发往 `1.1.1.1` 的 DoH 直连 100% 超时阻断。由于 `-fallback` 的存在，SmartDNS 必须等主用服务器超时 3~5 秒后才回退到国内 DNS，Dnsmasq 串行排队超时，导致浏览器经常直接报错 `DNS_PROBE_FINISHED_NO_INTERNET`；
  2. 超时后国内 DNS 返回了受 GFW 污染的假 IP，被 Dnsmasq 和系统长期缓存。

#### 2. 终极根治方案：“国内外全并发竞速 + 代理端 Sniffer 远端解析”

1. **SmartDNS 移除 `-fallback`，国内外全量并发**：
   - 在 `network-base.nix` 中移除国内服务器的 `-fallback` 标记，Dnsmasq 移除 `strict-order`；
   - **国外服务器**（fra0/tyo0 等）：直连 1.1.1.1/8.8.8.8 仅需 1~5ms 秒回，自动获选最快无污染 IP；
   - **国内服务器/笔记本**：阿里/腾讯 DNS 仅需 10ms 秒回，彻底消除 DNS 阶段的几秒级超时与卡顿。
2. **Mihomo 接管国外请求并强制使用远端无污染解析（“不听本地 Dnsmasq”）**：
   - **关掉 Mihomo 时**：本地 Dnsmasq 正常处理所有境内外解析，直连不断网；
   - **开启 Mihomo 时**：即使 Dnsmasq 返回了被 GFW 污染的假 IP，浏览器向该 IP 发起 TCP 连接瞬间，Mihomo TUN 内核网卡捕获数据包，通过 **Sniffer（嗅探器）** 在握手阶段提取出真实域名（如 `google.com`）；
   - Mihomo 直接剥离、丢弃本地受污染的假 IP，在 VLESS / Reality 协议层直接携带原始域名发送给海外境外节点（如 `fra0`）；
   - 由境外节点在海外当地使用纯净 DNS 完成权威解析并连接，彻底解决 DNS 污染与死锁。

---

### 3.7 冲突七：Meta 网卡 198.18.0.1 污染 SD-WAN 端点与 if_id 镜像死锁

#### 1. 深度病因剖析

在开启 Mihomo TUN 后，内核中新增了 `Meta` 网卡，其分配有 RFC 2544 基准测试保留段 IP `198.18.0.1/30`（scope global）。由于该段不属于 RFC 1918 常规私网（`10.`、`172.16-31.`、`192.168.`），引发了灾难性的级联死锁：

1. **虚假公网 IP 注册**：`dn42-sdwan-agent` 在自探测本机公网 IP 时，未排除 `Meta` 与 `198.18.*` 段，误将 `198.18.0.1` 当作物理公网 IPv4 发布至三主控 SD-WAN 注册中心；
2. **对端强校验拒连 (`AUTH_FAILED`)**：全网节点同步注册表后，将连接配置的 `remote_addrs` 锁死为 `198.18.0.1`。当 ARX8 从真实 NAT 出站发起 IKE 握手时，对端强校验发现源地址不匹配，无差别返回 `AUTH_FAILED`，全网隧道集体中断；
3. **多端点展开算法失衡引发 if_id 错位**：ARX8 因多出一个虚假的 `auto_v4` 端点（端点数从 1 变为 2），触发了 `mesh.nix` 为对端预留 responder 被动接口（`dn42x-*-r2`）的逻辑。该逻辑在循环末尾用 `ip -6 route replace` 将对端 IPv6 路由强行指向了**尚未建链、没有 SA 的 r2 网卡**，导致 ping 对端时内核当场返回 `Destination unreachable: Address unreachable`；同时导致两端生成的 `if_id` 一个为 1311、一个为 1312，产生单向通、反向丢的严重错位；
4. **Strongswan 自身选路污染**：Strongswan 在未设置 `ignore_routing_tables = 2022` 时，自身出站查询会被 table 2022 误导，把 `from 198.18.0.1` 写入 IKE 报文头；
5. **Babel RTT 阈值过窄**：跨国链路（如国内至法兰克福）日常 RTT 为 320-340ms，原默认 `rttMax = 300` 导致 Babel 将正常延迟判定为不可用（Metric 65535），拒绝下发内网路由。

#### 2. 终极根治方案：四重隔离与端点净化

1. **网卡与 IP 探测彻底绝缘**：在 `mesh.nix` 的 `DISCOVERED_IPS` 过滤链中，将 `meta.*`、`Meta.*`、`tailscale.*`、`docker.*`、`podman.*` 以及 `198.18.*`、`198.19.*`、`100.*` 彻底排除，确保纯 NAT 客户端绝不上报虚假 IPv4 端点；
2. **主路由保护**：`mesh.nix` 限制仅在 `t_saction = "start"`（主动发起端）时才接管 peer IPv4 与对端 IPv6 路由，被动端（responder / `r2`）仅配置本端地址，严禁越权覆盖；
3. **Strongswan 协议栈绝缘**：在 `charon.conf` 恢复 `interfaces_ignore = Meta, ...`、`ignore_routing_tables = 2022` 与 `plugins.socket-default.fwmark = 0x1`，从内核与 socket 层面杜绝 charon 接触代理路由表；
4. **Babel RTT 上限放宽**：将 `rttMax` 默认值放宽至 `500ms`，完全容纳跨大洲长肥管道的物理延迟，恢复内网路由的正常收敛。

---

## 四、 关键配置与运维指南

### 4.1 节点扩展最佳实践（零接触）

未来若向集群中加入新节点 `tyo2`：

1. 在 `terraform/hosts.tf` 中追加机器定义（主机名、公网解析记录、host_indices 等）；
2. 执行 `terraform-pipe`（或 `terraform apply`）：
   - 自动分配确定性 ID 与 DN42 内网 IPv4 / IPv6；
   - 自动生成密钥与默认端口；
   - `build_time` 绝不会产生任何无意义的全量 Diff；
3. NixOS 执行部署：
   - 全网 SD-WAN Agent 自动拉取新节点端点并建立 XFRM 隧道；
   - BIRD Babel 自动测速并下发最优选路；
   - ATC CoreDNS 自动生成 `tyo2.dora.dn42` 正反向解析记录；
   - Mihomo 订阅自动裂变出公网 `tyo2` 与专网 `tyo2-DN42` 节点。

### 4.2 常用排障排错速查表

| 排查目标              | 命令                                                                                                      | 预期健康指标                                                           |
| :-------------------- | :-------------------------------------------------------------------------------------------------------- | :--------------------------------------------------------------------- |
| **Babel 邻居与 RTT**  | `sudo birdc show babel neighbors`                                                                         | Metric 为健康值（300 ~ 700），RTT > 0，Expires 稳定倒数                |
| **Babel 路由表**      | `sudo birdc show route protocol dn42_babel`                                                               | 包含集群各节点 `/32` 与 `/128` 路由，下一跳指向最优 `dn42x-*`          |
| **IPsec SA 状态**     | `sudo swanctl --list-sas`                                                                                 | `ESTABLISHED`，报文计数器 `in` 与 `out` 双向稳定增长                   |
| **XFRM 接口状态**     | `ip -d link show type xfrm`                                                                               | `if_id` 符合公式，MTU 1360，状态为 UP                                  |
| **策略路由规则**      | `ip rule` / `ip -6 rule`                                                                                  | 包含 Priority 80, 81, 90 及 8980, 8985, 8990, 8996, 8998               |
| **Mihomo 防熔断规则** | `ip rule \| grep 898`                                                                                     | 必须同时存在 `8980: lookup main` 与 `8985: unreachable`，严禁遗漏 8980 |
| **Mihomo TUN 接管**   | `ip route get <境外IP> dport 443`<br>`sudo nft -a list chain inet mihomo output`                          | 应返回 `dev Meta table 2022`；redirect 计数器持续增长                  |
| **开机网络在线状态**  | `systemctl status NetworkManager-wait-online`                                                             | `active (exited)` 且耗时 < 1 秒，无超时卡死                            |
| **SmartDNS 本地响应** | `dig @127.0.0.1 -p 5335 www.baidu.com`                                                                    | Query time < 30ms，并发竞速秒回                                        |
| **CoreDNS 权威解析**  | `dig @172.20.232.1 dora.dn42 SOA +short`<br>`dig @172.20.232.1 tyo0.dora.dn42 +short`                     | 返回 `ns1.dora.dn42.` 与对应节点内网 IP                                |
| **Mihomo 节点延迟**   | `curl -s http://127.0.0.1:9090/proxies/<name>/delay?timeout=5000&url=http://www.gstatic.com/generate_204` | 返回 `{"delay": <ms>}`，无超时或 DNS 失败                              |
