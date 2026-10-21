# Infrastructure & Network Documentation

本目录包含本仓库全套基础设施、网络架构与服务集成的技术文档与运维实战指南。

## 目录索引

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

- [WinApps 无缝 Windows 子系统与 Office 集成技术文档](./winapps-architecture.md)
  - **一、 总体架构**（Linux 桌面、Home-Manager、NixOS 服务与 Podman 容器分层图）
  - **二、 核心功能特性**（Tiny10 极简基底、0% CPU 闲置、HiDPI 缩放、打印机穿透、MAS 静默激活）
  - **三、 文件结构与模块职责划分**（系统级 options、compose 生成器、OEM 激活流水线、桌面端配置）
  - **四、 核心问题排查与技术解决方案记录**（DN42 路由溢出、Tiny10 下载中断、开机假就绪挂起、MIME WPS 回退、xrdp 冲突）
  - **五、 日常运维与使用指南**（编译部署、状态检查、Office 自动化安装流程）
