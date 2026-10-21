# Infrastructure & Network Documentation

本目录包含本仓库全套基础设施、网络架构与服务集成的技术文档与运维实战指南。

## 目录索引

- [Apache Traffic Control (ATC) 分布式 CDN 架构与动态同步运维实战指南](./cdn-architecture.md)
  - **一、 宏观架构总览与分层解耦愿景**（五层架构全景图、各层职责边界）
  - **二、 核心子系统深度剖析与实现细节**
    - 2.1 基础设施交付编排 (`terraform/cdn.tf`)
    - 2.2 中心控制面与元数据大脑 (`nixos/modules/services/atc/ops.nix`)
    - 2.3 动态调度与智能解析面 (`nixos/modules/services/atc/router.nix`, CoreDNS, GeoIP2, DoH)
    - 2.4 边缘数据面与可写动态解耦 (`nixos/modules/services/atc/edge.nix`, Apache Traffic Server)
    - 2.5 轻量打包构建与专用产物导出 (`pkgs/trafficcontrol/default.nix`)
    - 2.6 跨大洲国际链路单边内核调优 (`nixos/modules/services/atc/tuning.nix`)
  - **三、 关键机制与工程挑战解决**
    - 3.1 毫秒级微轮询与防惊群机制 (`syncds`)
    - 3.2 零停机热重载与存量连接保护 (Hitless Reload)
  - **四、 运维操作实战指南**
    - 4.1 业务域名声明式接入流程
    - 4.2 边缘节点扩容指南
  - **五、 验证与排障速查表**
    - 5.1 验证检查清单
    - 5.2 常见排障排错速查表

- [DN42 全互联 SD-WAN 架构与多网络组件隔离实战指南](./dn42-architecture.md)
  - **一、 宏观架构总览与分层解耦愿景**（七层架构全景图、各层职责边界）
  - **二、 核心子系统深度剖析与实现细节**
    - 2.1 零接触编排与数据管线 (`terraform/dn42.tf`, 剥离 `build_time`)
    - 2.2 SD-WAN 动态控制面与自愈 Agent (`dn42/mesh.nix`)
    - 2.3 多端点全路径探路与无冲突对称 `if_id` 数学算法
    - 2.4 内核协议栈隔离与 Mimic (Fake-TCP) 无补丁穿透
    - 2.5 内部动态路由层：BIRD 2 Babel 动态选路与 ETX+RTT 算法
    - 2.6 专网权威 DNS 与反向解析体系 (`atc/router.nix`, CoreDNS, 官方 Registry 规范)
  - **三、 跨层多网络组件冲突与终极解决方案**
    - 3.1 冲突背景：DN42, Tailscale, EasyTier, Mihomo TUN 的重叠战场
    - 3.2 冲突一：Mihomo TUN 路由自捕获死锁（Routing Loop 根治方案）
    - 3.3 冲突二：fwmark 0x1 与 Android (Box for KernelSU) 全局断网
    - 3.4 冲突三：本地 127.0.0.1:53 Fallback 循环死锁
    - 3.5 冲突四：底层网络策略路由 (Policy Routing) 与防火墙隔离
  - **四、 关键配置与运维指南**
    - 4.1 节点扩展最佳实践（零接触新增节点）
    - 4.2 常用排障排错速查表
