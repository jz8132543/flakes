# 代理协议抗封锁能力调研与核心选型

本文记录 VLESS/REALITY/XHTTP 及相关代理技术的调研过程、公开证据、实测结论与选型依据，作为该子系统的使用说明与决策记录。

不涉及具体主机配置、网络故障排查过程或个人使用动机。所有版本与源码结论均标注了核实日期和证据来源。

---

## 1. 威胁模型分层

比较任何"混淆能力"之前，必须先分清四个独立层次。混淆它们会得出错误结论。

```text
1. 代理协议      VLESS / Trojan / Shadowsocks / AnyTLS / VMess
2. 传输方式      TCP / WebSocket / gRPC / XHTTP / QUIC
3. 安全与外观    普通 TLS / REALITY / ShadowTLS / 随机混淆
4. 入口设施      直连 VPS / 中转 / CDN / 动态桥网络
```

**外层决定审查者首先看到什么；内层与流量组织仍影响后续统计。**

关键认知：**第 3 层加密强度不等于抗封锁能力。** 加密保护内容机密性，混淆改变外观与行为。二者目标不同：

- 更多加密或随机填充 ≠ 更像正常网页访问
- 后量子安全 ≠ 隐藏目的 IP、明文 SNI、连接数与时序
- 换一个协议名称 ≠ 改变威胁模型

### 各层的实际作用

| 机制              | 解决什么           | 不解决什么                     |
| ----------------- | ------------------ | ------------------------------ |
| 真实 TLS/浏览器栈 | TLS 实现层指纹差异 | 长连接、流量规模、上下行相关性 |
| CDN 隐藏源 IP     | 入口 IP 被封       | CDN 风控、账号停用、域前置限制 |
| padding           | 长度特征           | 时序、方向比例、连接数         |
| 多入口/动态桥     | 批量封 IP 成本     | 单一协议的实现层缺陷           |
| 后量子密钥交换    | 未来量子解密风险   | 任何被动/主动探测              |

---

## 2. 主流协议组合横向对比

未给星级或百分比评分，因为缺少同线路、同流量、同检测器的可靠横向实验。

### 2.1 TLS 与 HTTP 类

| 组合                                 | 主要优势                                                     | 主要局限                                                  |
| ------------------------------------ | ------------------------------------------------------------ | --------------------------------------------------------- |
| VLESS + Vision + REALITY             | 无需自签目标域名证书；性能好；缓解部分 TLS-in-TLS 特征       | IP/SNI/ASN 关系、时序与规模仍有风险                       |
| VLESS + REALITY（无 Vision）         | 保留 REALITY 握手机制                                        | 内层握手形状缺少针对性缓解                                |
| VLESS + XHTTP + REALITY              | 改变流量组织，支持分流与复用                                 | **外层仍是 REALITY，不自动免疫其风险**；直连仍暴露入口 IP |
| VLESS + 真实 TLS                     | 自有域名与网站可建立一致关系                                 | 自有 IP 仍可被封                                          |
| Trojan + TCP + 真实 TLS              | 成熟、实际 TLS、可提供正常网站回落                           | 不自动消除嵌套握手特征                                    |
| VLESS/VMess/Trojan + WSS + TLS + CDN | 成熟 HTTP 入口，隐藏直连源站 IP                              | WS 连接模式、CDN 风控仍存在                               |
| **VLESS + XHTTP + TLS + CDN**        | HTTP 入口 + 流量组织灵活 + 隐藏源站 IP                       | 会话元数据、padding、WAF 需适配                           |
| **NaiveProxy + HTTPS/H2**            | **真实 Chromium TLS/HTTP 栈**，覆盖范围远超 ClientHello 模仿 | 不隐藏直连 IP；仍有隧道统计特征                           |
| NaiveProxy + HTTP/3                  | 真实 Chromium QUIC/H3 栈                                     | 依赖 UDP 可达性                                           |
| AnyTLS + TLS                         | 可调 paddingScheme、连接复用，兼容性好                       | 非完整浏览器栈，不隐藏 SNI/IP                             |
| SS + ShadowTLS v3                    | 转发真实握手，v3 改进认证与完整性                            | 非完整浏览器会话；严格模式要求 TLS 1.3                    |
| SS + Restls                          | 可控制握手后长度、方向与交互                                 | 脚本可能形成新特征；客户端仍非 Chromium                   |

### 2.2 QUIC 与 UDP 类

| 组合                   | 真正增加的能力                             | 混淆边界                                              |
| ---------------------- | ------------------------------------------ | ----------------------------------------------------- |
| Hysteria2（无 obfs）   | 高丢包环境性能；未认证请求可表现为 H3 网站 | **认证后自定义流不是普通 H3 网页**；普通 CDN 无法承载 |
| Hysteria2 + Salamander | 隐藏标准 QUIC 包头与 Initial 内容          | **线上是随机样式 UDP，不是 HTTPS**                    |
| Hysteria2 + Gecko      | 对握手 datagram 随机分片与填充             | 仍是随机样式 UDP                                      |
| Hysteria2 + Mimic      | eBPF 包层伪 TCP                            | 不是真 TCP；双方需 Linux/root                         |
| TUIC v5 + QUIC         | 低延迟、复用、UDP 转发                     | **QUIC ≠ HTTP/3**；错误行为依赖实现                   |

### 2.3 设施层面

| 系统            | 增加什么                              | 代价                           |
| --------------- | ------------------------------------- | ------------------------------ |
| Tor + obfs4     | 抗不知桥凭证的主动探测                | 高熵 TCP 封锁、桥泄漏仍有效    |
| Tor + WebTunnel | 隐藏路径 HTTPS，可与真实网站共域名/IP | 路径泄漏、性能与生态           |
| Tor + Snowflake | WebRTC 动态志愿者入口                 | broker/STUN 可被限制，性能波动 |
| Psiphon         | 服务器池、动态入口、策略更新          | 依赖运营网络                   |

---

## 3. uTLS 与真实浏览器栈的本质差异

这是最值得保留的架构区别，也最容易被过度营销。

**uTLS 主要解决 ClientHello 的外观，而不是把程序变成 Chrome。**

后续 TLS record、会话恢复、错误响应、HTTP/2 SETTINGS、流控、请求顺序、连接关闭、QUIC 参数及定时行为，都可能依赖实际实现。

NaiveProxy 复用 Chromium 网络栈（含相应 TLS 与 HTTP 实现），因此确实减少"Go TLS + Chrome ClientHello"这种层间不一致。当前 sing-box 的 Naive 出站自 1.13.0 起支持，并依赖 Chromium/Cronet。

但真实网络栈仍不等于完整正常浏览行为：

- 主要工作仍是隧道转发，不执行任意页面与 JavaScript
- padding 不是对全部流量无限填充
- 并行隧道、长期大流量仍可能与普通浏览不同

**结论：仅复制握手格式，不足以覆盖不同 TLS/HTTP 实现的全部行为差异。**

---

## 4. REALITY 已知问题与 Xray 修复记录

以下区分报告、维护者确认、源码修复与真实审查部署证据，不把 `closed` 当成 `fixed`。

### 4.1 post-handshake 消息不一致

- [Xray-core #4778](https://github.com/XTLS/Xray-core/issues/4778)（2025-06-03）+ [独立研究 #481](https://github.com/net4people/bbs/issues/481)
- Aparecium 研究指出：目标站在 `ClientFinished` 后可能发送 `NewSessionTicket`，ALPN 为 H2 时还会提前发送 HTTP/2 SETTINGS，REALITY 当时未表现相同的数量、长度与时序
- RPRX 明确承认遗漏了部分 OpenSSL 行为
- **修复**：v25.6.8 初步修补，v25.7.26 扩展三种 ALPN 探测
- **边界**：不同 ClientHello、ALPN/ALPS、目标站更新和 TCP 合包仍影响表现

### 4.2 异常 CCS 容忍数量差异

- [研究 #576](https://github.com/net4people/bbs/issues/576) + [REALITY PR #29](https://github.com/XTLS/REALITY/pull/29)（2026-03-22 合并）
- 核心不是"解出密钥"，而是攻击者比较授权路径与回落路径对异常 TLS 消息的反应
- **修复**：v26.3.27 发布目标 `maxUselessRecords` 的 1/16/32/∞ 分档探测，默认 32
- **边界**：只解决一类行为差异，不是所有异常 record/超时/Alert 的完整模拟

### 4.3 "100% 精准识别"说法证据不足

- [Xray-core #6091](https://github.com/XTLS/Xray-core/issues/6091)、[#6121](https://github.com/XTLS/Xray-core/issues/6121)
- 原始探针对部分目标有效，维护者测试发现不少载荷对不同实现产生相同结果
- RPRX 提出的修复方向：在正确 `ClientFinished` 前让目标站处理异常消息，克隆 error/timeout
- **当前判断**：问题被承认、实现上可修，但公开记录不足以确认完整 `error-clone/timeout-clone` 已全面完成

**尤其重要：可复现探测 ≠ 已证明审查设备规模化部署该探测。**

### 4.4 空 SNI post-handshake 遗漏

- [Xray-core #7280](https://github.com/XTLS/Xray-core/issues/7280) + [REALITY PR #42](https://github.com/XTLS/REALITY/pull/42)
- 空 SNI 时启动探测被 uTLS 拒绝、缓存为空，合法无 SNI 客户端拿不到目标本会发送的 post-handshake records
- **修复**：PR 于 2026-11-08 合并，v26.11.9 包含

### 4.5 XHTTP 的 CDN/WAF 问题

- [Xray-core #6446](https://github.com/XTLS/Xray-core/issues/6446)、[PR #6258](https://github.com/XTLS/Xray-core/pull/6258)、[#6888](https://github.com/XTLS/Xray-core/issues/6888)
- 有用户报告 TLS 终止型 CDN/WAF 拒绝 XHTTP 会话 ID 的 UUID 文本形式
- **注意：CDN 终止 TLS 后本来就能看到 HTTP 元数据，这不证明 GFW 解密了 TLS 密文**
- 已加入会话 ID 字符表、长度、放置位置等可配置能力；**未配置时仍用默认 UUID 形式**

### 4.6 后量子加密不是混淆冠军

- [VLESS Encryption PR #5067](https://github.com/XTLS/Xray-core/pull/5067)
- RPRX 原文明确：**"这个加密不是让你直接过墙用的"**
- 需区分两种 UUID：**VLESS 用户 UUID** 是代理认证信息；**XHTTP session ID** 是关联上下行的传输元数据。加密前者不会隐藏后者所在的 HTTP 路径、请求次数和时序

### 4.7 版本兼容会产生"像被墙"的症状

- [官方文档 PR #916](https://github.com/XTLS/Xray-docs-next/pull/916)
- Xray ≥v26.9.9 要求 ClientHello 含 X25519MLKEM768 且在可选 X25519 之前；部分旧指纹因此被当成普通访问者回落
- 收到目标真证书可能来自配置错误、版本不兼容或重定向，**该日志本身不是被干扰证据**

---

## 5. Xray 与 Mihomo 的跨核心兼容性

用户曾遇到"Xray 破坏兼容导致 Mihomo 无法连接"的情况。核实后至少涉及**两次独立变更**：

| 变更                                                           | 状态                                                                                       |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| 默认 `minClientVer` 门槛（曾要求 ≥26.3.27，Mihomo 报 `1.8.2`） | **已撤销**。提交 `47cfe999`（2026-09-08），v26.11.9 包含。但面板中显式设置的值不会自动消失 |
| 强制 ML-KEM ClientHello（≥v26.9.9）                            | **仍保留**                                                                                 |

**维护者给出的互通用法**（[Xray #7259](https://github.com/XTLS/Xray-core/issues/7259)，2026-11-04）：

> Mihomo 需使用 Chrome 指纹，且 reality-opts 下加入 `support-x25519mlkem768: true`

**版本对照：**

- 明确成功：Mihomo 1.19.29/30 → Xray 26.7.28（放宽当时版本门槛）
- 明确失败：Mihomo 1.19.31、旧 Firefox 指纹 → Xray 26.9.9
- Mihomo 官方仍保留"不考虑 Xray 26.7.11+ 兼容"的警告

**Mihomo 客户端不会替换 Xray 服务端的 TLS 栈，也不会撤销服务端已发布的修复；但客户端自身的指纹和行为差异仍是独立识别点。**

### 5.1 指纹版本差异

同一个配置标签不代表字节级指纹相同。以固定版本源码核实：

| 客户端         | `chrome` 实际指向 | MLKEM key share   |
| -------------- | ----------------- | ----------------- |
| Mihomo 1.19.34 | Chrome 133        | 有，且 MLKEM 在前 |
| Xray 26.11.9   | Chrome 155        | 有                |

因此升级 Xray 服务端**不会**同时升级 Mihomo 客户端指纹。

---

## 6. sing-box 系内核评估

### 6.1 原生 sing-box

- REALITY 服务端通过 `common/tls/reality_server.go` 调用 `utls.RealityServer()`
- 仓库锁定的 sing-box 包使用 `MetaCubeX/utls` 中的 REALITY 实现，**不是直接使用最新版 XTLS/REALITY 模块**
- **因此 Xray 发布某项 REALITY 修复，不代表 sing-box 自动获得它**

**sing-box 上的实证问题：**

- [#4610](https://github.com/SagerNet/sing-box/issues/4610)（open）：未认证请求得到目标响应后，REALITY 连接迟迟不关闭。测试显示直连目标约 1ms 收到 EOF，REALITY 回落 10 秒内无 EOF
- [#4404](https://github.com/SagerNet/sing-box/issues/4404)：Vision 切换后多发一个 19 字节 TLS record，跨实现对照 Xray 没有。**该问题已修复，1.14.4 包含**
- MetaCubeX/utls PR #6（fallback close 传播）**open 未合并**

### 6.2 sing-box-lx

用户曾考虑此分支。核实结论：

- **XHTTP 只有客户端**：`transport/v2rayxhttp/register.go` 仅调用 `v2ray.RegisterClient(...)`，无服务端注册
- 官方文档明确"Только клиент. Серверную сторону форк не реализует"（仅客户端，fork 不实现服务端）
- REALITY 服务端仍用 `utls.RealityServer()`，未移植 Xray 修复
- uTLS 子模块为 fork，Firefox 148+MLKEM 相关 PR 仍 open

**结论：sing-box-lx 支持的功能是客户端侧，不能替换 XHTTP 服务端。**

### 6.3 sing-box-extended

用户最终选择的服务端内核。

- NUR 提供 `1.14.3-extended-2.7.3`
- **XHTTP 服务端真实存在**：`transport/v2rayxhttp/server.go` + `transport/v2ray/transport.go` 的 `case C.V2RayTransportTypeXHTTP: return xhttp.NewServer(...)`
- 支持 `stream-one` / `stream-up` / `packet-up`
- 支持 XHTTP 会话 ID 可配置（`session_placement`/`session_key`/`session_id_table`/`session_id_length`）与 padding 全套参数
- 支持 VLESS `decryption`/`encryption`（fork 自有实现，默认关闭）
- systemd 单元仍是 `sing-box.service`

**修复覆盖核实（逐项读源码）：**

| Xray 已修问题                        | Extended 状态                     |
| ------------------------------------ | --------------------------------- |
| post-handshake records 探测与模仿    | **未移植**                        |
| maxUselessRecords 逐目标分档         | **未移植**（固定 32，TODO 仍在）  |
| 异常 Alert/error-clone/timeout-clone | **未移植**                        |
| 空 SNI post-handshake 缓存           | **未移植**                        |
| XHTTP 会话 ID 可配置                 | **已移植**（fork 自有）           |
| VLESS Encryption                     | **已存在**（fork 自有，默认关闭） |
| ML-KEM ClientHello 强制              | **未移植**（服务端无强制）        |

**证据：**

- `reality.go:539` TODO 原文保留：`TODO: Probe target's maxUselessRecords and some time-outs in advance.`
- `common.go:70` `maxUselessRecords = 32` 为编译期常量
- `handshake_server_tls13.go:1125-1146` 三种失败分支只调 `c.sendAlert(...)`；而 `reality.go:52-54` 的 `realityMirrorConn.Write` 恒返回错误，说明 Alert 只能来自目标真实字节
- 上游 MetaCubeX/utls PR #6/#7/#8 全部 open 未合并

**注意：MetaCubeX/utls 仓库 `has_issues: false`，关闭了新 issue 提交通道。因此"没找到对应 issue"不能解释为"没有问题"。**

**版本对照：** `v1.8.7` 与 `v1.8.8` 的 `reality.go` 逐字节相同；`v1.9.0` tag 不存在；`v1.9.0-alpha.1` 仅改 mlkem import 路径。

---

## 7. ML-KEM 与 uTLS 的准确语义

这一节纠正一个常见误解。

### 7.1 两处 key share 用途不同

源码核实显示，REALITY 中有**两个独立**的 key share 使用位置：

| 用途                     | 代码位置                                        | 由谁决定                                                                                               |
| ------------------------ | ----------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| **REALITY 身份认证密钥** | `reality.go:387-401`                            | 固定逻辑：先遍历取 `X25519`（32 字节），仅当 `peerPub == nil` 才回退取 `X25519MLKEM768` 的尾部 32 字节 |
| **实际 TLS 会话密钥**    | `handshake()` 中的 `hs.hello.serverShare.group` | 由**伪装目标站**的 ServerHello 决定                                                                    |

**关键结论：**

1. 认证阶段那个"先 X25519、取不到才回退 MLKEM"是 REALITY 校验客户端身份的**固定实现细节，不可配置**，与"启用混合后量子"无关
2. 即使客户端带了 MLKEM key share，**只要目标站在 ServerHello 里选 X25519，会话就用普通 X25519**
3. 服务端**没有** ML-KEM 开关，也不强制要求客户端携带

### 7.2 安全性对比

| 算法               | 安全性                                      | 量子抗性                                     |
| ------------------ | ------------------------------------------- | -------------------------------------------- |
| **X25519**         | 经典 ECDH，约 128 位                        | 无。未来足够强的量子计算机可用 Shor 算法破解 |
| **X25519MLKEM768** | 混合 = X25519 + ML-KEM-768（NIST FIPS 203） | **有**。且至少不弱于单独 X25519              |

混合方案是**超集关系**：共享秘密同时包含两部分，任一部分成立即可保证安全。因此 MLKEM 混合更强，不是替代关系。

### 7.3 客户端的实际行为

以 Mihomo 1.19.34 固定源码核实：

- `adapter/outbound/reality.go` 有 `SupportX25519MLKEM768` 字段，yaml 为 `support-x25519mlkem768`
- **默认 `false`**；为 false 时调用 `BuildRemovedX25519MLKEM768HandshakeState` **主动删除** ClientHello 中的 MLKEM key share 与 supported_groups
- 为 true 时**保留**指纹原有的 key share，**不会**让不支持 MLKEM 的旧模板自动获得支持
- `client-fingerprint: chrome` 在 MetaCubeX/utls v1.9.0-alpha.1 中指向 `HelloChrome_133`，其 key share 顺序为 GREASE → MLKEM768 → X25519

**因此仅设置 `client-fingerprint: chrome` 不够，还需显式 `support-x25519mlkem768: true`。**

### 7.4 服务端探测指纹的覆盖边界

Xray 当前 `record_detect.go` 的探测使用 `utls.HelloChrome_Auto`（Chrome 155），且 post-handshake 缓存键仅为 Dest + SNI + ALPN 分类，**不按完整 ClientHello 指纹细分**。这构成需要实测的覆盖边界，不能直接推断为"客户端指纹差异必然导致探测失效"或"必然被发现"。

---

## 8. 混淆参数的两端一致性

XHTTP padding 参数在客户端与服务端、以及不同客户端之间的默认值和字段命名并不一致。**配置看起来生效、实际被忽略**是常见失败模式。

### 8.1 字段命名差异

| 客户端               | padding 字段                                                                     | 会话 ID 字段                          |
| -------------------- | -------------------------------------------------------------------------------- | ------------------------------------- |
| Xray                 | `xPaddingBytes` / `xPaddingObfsMode` / ...（camelCase，位于 `extra`）            | `sessionIDPlacement` / `sessionIDKey` |
| sing-box（Extended） | `x_padding_bytes` / `x_padding_obfs_mode` / ...（snake_case）                    | `session_placement` / `session_key`   |
| Mihomo               | `x-padding-bytes` / `x-padding-obfs-mode` / ...（kebab-case，位于 `xhttp-opts`） | `session-table` / `session-length`    |

Mihomo 的 XHTTP 选项**没有 `extra` 字段**，必须逐个映射为 kebab-case 字段。

### 8.2 实测发现的默认值差异

在本地互通测试中发现：Mihomo 虽支持 padding 混淆开关，但**不会自动补齐 padding 的位置、头字段和编码方式**，导致服务端收到长度为 0 的 padding 并拒绝请求。

**解决：两端显式指定全部五项参数**，不依赖任何一端补默认值：

```
xPaddingBytes       = 100-1000
xPaddingObfsMode    = true
xPaddingPlacement   = header
xPaddingHeader      = X-Padding
xPaddingMethod      = repeat-x
```

### 8.3 连接复用（XMUX）

Mihomo 的实际入口是 `xhttp-opts.reuse-settings`（注释 aka XMUX），不是 `xmux`：

```yaml
reuse-settings:
  max-connections: "3-3" # 连接池大小
  h-max-request-times: "600-900" # 每连接请求数上限
  h-max-reusable-secs: "1800-3000" # 连接复用寿命（秒）
  h-keep-alive-period: 45 # HTTP/2 保活间隔（秒）
```

sing-box Extended 侧字段为 `xmux.max_connections` / `h_max_request_times` / `h_max_reusable_secs` / `h_keep_alive_period`。

### 8.4 单位后缀陷阱

实测发现 `badoption.Range[int]` 类型**不接受 `512k` / `1M` 这类单位后缀**，只接受纯整数：

```
正确: "524288-1048576"      (字节)
错误: "512k-1M"             → FATAL: strconv.ParseInt: parsing "512k": invalid syntax
```

涉及字段：`uplink_chunk_size`、`sc_max_each_post_bytes`、`sc_min_posts_interval_ms`（毫秒）。

### 8.5 上行 pacing（高延迟高丢包）

| 参数                       | 默认值         | 作用                      |
| -------------------------- | -------------- | ------------------------- |
| `uplink_chunk_size`        | 524288-1048576 | 上行分块大小              |
| `sc_max_each_post_bytes`   | 524288-1048576 | 单个 packet-up POST 上限  |
| `sc_min_posts_interval_ms` | 10-30          | POST 间最小间隔（抗突发） |

**这些参数只在 `packet-up` 模式生效。** `stream-one` 只有一个双向请求，没有独立的上传 POST 可以调节，因此配置了也不会生效。

### 8.6 拥塞控制参数对 REALITY 无效

Extended 有 `congestion_controller`（`bbr`/`cubic`/`reno`）和 `cwnd`（默认 32）两个独有参数。源码核实：

- `transport/v2rayxhttp/client.go:332` 只在 `case "3"`（HTTP/3/QUIC）分支调用 `congestion.NewCongestionControl(...)`
- `case "2"`（HTTP/2）分支**没有**任何拥塞控制调用
- 而 REALITY 强制 HTTP/2

**结论：在 REALITY 下配置这两个参数不会产生任何效果。** 需要 QUIC 级拥塞控制时应改用 Hysteria2/TUIC 或走普通 TLS + HTTP/3。

### 8.7 XHTTP 上下行分离与 ML-KEM

用户可能遇到"漏写 `download-settings.reality-opts.support-x25519mlkem768`"的建议。核实源码：

- `adapter/outbound/vless.go:130` `XHTTPDownloadSettings` 确实含 `RealityOpts` 字段
- 但 `:720-722` 明确禁止组合：

```go
if ds := v.option.XHTTPOpts.DownloadSettings; ds != nil {
    if cfg.Mode == "stream-one" {
        return nil, fmt.Errorf(`xhttp mode "stream-one" cannot be used with download-settings`)
    }
```

**结论：`stream-one` 与 `download-settings` 互斥。** 使用 `stream-one` 时不存在这个问题，只需在顶层 `reality-opts` 设置 `support-x25519mlkem768: true`。

只有在使用 `packet-up` 或 `stream-up`（上下行分离到不同服务器）时，才需要为 download 侧单独配置完整的 REALITY 参数。

### 9.4 withCGO 变体选择

NUR 提供两个构建变体，差异仅在 `CGO_ENABLED`：

| 变体                        | 效果                                                                    |
| --------------------------- | ----------------------------------------------------------------------- |
| 默认（`withCGO = false`）   | 纯 Go 构建                                                              |
| `-full`（`withCGO = true`） | 额外启用 `with_naive_outbound` build tag，即 **NaiveProxy/Cronet 出站** |

源码依据（`repos/ataraxiasjel/pkgs/sing-box/common.nix`）：

```nix
CGO_ENABLED = if withCGO then 1 else 0;
# cronet 预编译静态库只能用 lld 链接（bfd ld 拒绝该归档）
CGO_LDFLAGS = "-fuse-ld=lld";
tags = baseTags ++ extraTags ++ lib.optionals withCGO [ "with_naive_outbound" ];
nativeBuildInputs = [ installShellFiles ] ++ lib.optionals withCGO [ lld ];
```

**是否影响安全性：**

- **没有证据表明 `withCGO = true` 应用了额外安全补丁。** 它只改变构建方式和启用的功能 tag
- 启用 CGO 会引入 C/C++ 静态库（Chromium Cronet）到二进制，**扩大了攻击面**：Cronet 或 lld 链接层的漏洞会影响 sing-box 进程
- 纯 Go 构建的漏洞面更小，且 Cronet 的证书校验与网络栈是独立实现，出了问题排查链路更长

**是否影响功能：**

- 只有需要 **NaiveProxy 出站**（真实 Chromium 网络栈）时才必须用 `-full`
- 本文第 3 节说明 NaiveProxy 的真实浏览器栈是少数能覆盖 TLS/HTTP 实现层差异的方案，如果你走这条路，`-full` 是必需的
- 不启用时功能**不受影响**，只是没有 Naive 出站

**是否影响性能：**

- **对当前配置无影响。** 当前架构是 sing-box-extended 服务端 + Mihomo 客户端，服务端不需要 Naive 出站
- 启用后二进制更大、构建更慢（需要 lld 链接 C 归档），运行时内存占用略高
- 如果将来在服务端启用 Naive 出站作客户端用途，Chromium 栈的 TLS/HTTP 行为一致性收益可能超过这些开销

**建议：**

- **当前服务端用途保持默认（`withCGO = false`）。** 不需要 Naive 出站，纯 Go 构建攻击面更小
- 如果决定在客户端侧试验 NaiveProxy（第 3 节的真实浏览器栈路线），在那个位置用 `-full`

---

## 9. 密码学特性的定位建议

### 9.1 建议开启

| 特性                      | 理由                        | 代价              |
| ------------------------- | --------------------------- | ----------------- |
| uTLS 浏览器指纹（客户端） | ClientHello 外观一致        | 握手构造开销小    |
| 混合 key share（客户端）  | 抗量子 + 保持现代浏览器外观 | 新连接约多 1.2 KB |
| XHTTP padding（两端显式） | 长度特征随机化              | 少量带宽          |

### 9.2 默认关闭

| 特性               | 理由                                                              |
| ------------------ | ----------------------------------------------------------------- |
| VLESS 内层额外加密 | 不隐藏外层 IP/SNI/统计特征；增加握手与加解密成本，弱 CPU 上更明显 |
| 0-RTT              | 有重放边界，不应只为速度开启                                      |

**RPRX 对 VLESS Encryption 的原话：这个加密不是让你直接过墙用的。** 其主要目标是前向安全、后量子密钥交换，以及在 CDN、中转场景避免暴露 VLESS 用户 UUID 和被代理目标信息。

### 9.3 性能优化原则

- 优先调连接复用与保活，而非叠加加密层
- 不盲目提高整机 sysctl 缓冲或声明带宽
- Extended 使用 `GOGC=100`（比 legacy 的 50 省 CPU），保留既有内存上限
- 所有资源参数保持 `mkDefault` 可覆写

---

## 10. Cloudflare Worker 测速页

`terraform/modules/speedtest-worker/` 提供一个独立测速/连通性检查站点，**不依赖任何自建源站**。

### 10.1 方案选型

用户询问是否可用 GitHub 公开项目。核实 [cloudflare/speedtest](https://github.com/cloudflare/speedtest)：

- 这是 `speed.cloudflare.com` 使用的**浏览器测速引擎**（`@cloudflare/speedtest` npm 包，MIT）
- 在访问者浏览器中运行，利用 `PerformanceResourceTiming` 获取数据
- 支持下载/上传带宽、空闲与负载延迟、抖动、网络质量评分、可选 WebRTC/TURN 丢包测量
- 仓库中 `example/turn-worker` 只提供 TURN 凭据，**不是下载/上传测速后端**

**采用方案**：Worker 托管页面 + 官方引擎 + Cloudflare 官方 `__down`/`__up` 端点。这样测速流量由 Cloudflare 官方后端承载，无需自建测速服务。

**为什么不是"全部跑在 Worker 上"**：测速必须从访问者浏览器发起，才能测量访问者的连接。Worker 负责托管页面、分发引擎和提供健康检查端点。

### 10.2 当前实现

| 路径              | 行为                                                    |
| ----------------- | ------------------------------------------------------- |
| `/`、`/speedtest` | 返回首页，固定版本加载官方引擎并带完整性校验            |
| `/app.js`         | UI 包装：`autoStart: false`、官方端点、关闭单独结果上报 |
| `/generate_204`   | 无响应体 204，供健康检查                                |

**安全边界：**

- 引擎版本与 SRI 完整性校验写死（`sha384-...`）
- CSP 限制 `script-src 'self' https://cdn.jsdelivr.net`、`connect-src 'self' https://speed.cloudflare.com`
- 不支持任何上传/下载/代理端点，无开放代理或任意 URL fetch
- 无缓存头、`nosniff`、`no-referrer`
- `cpu_ms = 10`，关闭 Worker 日志

**注意：域名含 `speedtest` 不保证绕过 QoS；Cloudflare 边缘证书本身不包含代理软件标识，但也不消除 REALITY 的记录长度、握手行为、流量统计或 IP/SNI 不匹配特征。**

### 10.3 部署

```bash
terraform-wrapper apply -target=module.speedtest_worker
```

API Token 需要账号级 **Workers Scripts Edit** 权限，且账号范围需包含 Terraform 配置中的 account id。仅有 DNS 权限不足以上传脚本。

---

## 11. 核心选型与回退

### 11.1 当前架构

```text
客户端 Mihomo（规则/策略组/TUN）
  -> VLESS + REALITY + XHTTP stream-one
  -> sing-box-extended 服务端（NUR 1.14.3-extended-2.7.3）
```

**选型理由：**

1. Extended 有真实的 XHTTP 服务端实现，而非仅客户端
2. 保留 sing-box 生态与配置风格，systemd 单元仍为 `sing-box.service`
3. 支持 XHTTP 会话 ID 与 padding 全套可配置项
4. 可通过声明式参数回退到 Xray 或原生 sing-box

**已知局限：Extended 未移植 Xray 的 post-handshake 模仿、maxUselessRecords 分档、异常克隆等修复。** 若最在意这些主动探测问题，应保留 Xray 作为服务端对照。

### 11.2 回退路径

模块保留三种核心：

| `core`                      | 传输         | 说明                      |
| --------------------------- | ------------ | ------------------------- |
| `sing-box-extended`（默认） | XHTTP        | 当前主力                  |
| `xray`                      | XHTTP        | 修复最完整的 REALITY 实现 |
| `sing-box`                  | TCP + Vision | 原生 sing-box 回退        |

**回退时订阅必须同步切换**：原生 sing-box 需要 `transport = "tcp"` + `flow = "xtls-rprx-vision"`，否则 Vision 与 XHTTP 不匹配。

订阅模块提供 `services.subscriptionPublisher.transport`（`tcp`/`xhttp`）与 `serverName` 选项用于同步。

### 11.3 诊断分层

排查连接问题时，按层定位比直接改协议更有效：

| 观察                                 | 优先判断                          |
| ------------------------------------ | --------------------------------- |
| TCP 连接在发送 TLS 前就失败          | IP/端口/路径/服务监听；与协议无关 |
| 同入口普通 HTTPS 也失败              | 更接近网络/IP/端口级限制          |
| TCP 通，特定 ClientHello 后丢包/重置 | TLS/SNI/指纹或版本兼容性          |
| 握手通，开始转发后失败               | 流量分类、连接限制、资源或 QoS    |
| CDN 返回 403 或停用账号              | 先查 CDN/WAF/产品政策             |

**收到目标真证书不代表被干扰**：可能来自配置错误、版本/指纹不兼容、重定向或目标站变化。

---

## 12. 验证方法与边界

### 12.1 已完成的验证

- 真实二进制配置解析：Extended / Xray / 原生 sing-box 三套，覆盖默认、代理、单 peer、无 SOCKS、alternate 端口与路径、XMUX 覆写等场景
- 真实互通：Mihomo → Extended 的 REALITY + XHTTP + 五项 padding + reuse-settings；Shadowsocks 互通
- 安全：IPv4/IPv6/mapped IPv6/私网域名/混合 DNS 的私网目标拒绝，且确认请求已到达服务端 guard；可信 SOCKS 保留私网访问；未授权 SOCKS 阻断
- 健康选路：Extended peer URLtest 只选活节点、全部失效时不绕行 direct
- 订阅：真实 Mihomo 配置解析、分享链接与 YAML 参数一致性、invite 精确域名直连
- Worker：原生 Node 测试覆盖路由、方法、缓存头、CSP、引擎配置、无出站请求
- Terraform：`fmt -check` 与 `validate`（虚拟 account/zone，无凭据）

### 12.2 未验证的边界

- **真实线路吞吐、QoS 效果、抗封锁实际表现未验收**
- Extended 的 REALITY 探测修复缺口是基于静态源码的结论，未做真实探测实验
- VLESS 内层加密的密码学强度未审计
- 原生 sing-box 回退仅验证到 parser 层，未做真实 Vision 运行验收
- 各协议的"混淆最强"无同条件横向实测数据，本文结论基于源码、公开 issue 与协议设计，不是同线路对比实验

---

## 13. 结论

1. **不存在通用"最强混淆"排名。** 性能优化、浏览器实现一致性、抗主动探测、入口 IP 隐藏和匿名性是不同目标。
2. **加密强度 ≠ 抗封锁能力。** 后量子密钥交换、VLESS 内层加密解决的是机密性与前向安全，不隐藏 IP/SNI/时序/统计。
3. **换软件不等于换威胁模型。** 相同 REALITY 外层在不同内核中共享设计原理，也共享其未修复部分。
4. **Xray 修复最快最全，Extended 提供 XHTTP 服务端与生态便利。** 按是否在意主动探测细节选择。
5. **入口独立性比节点数量重要。** 不同主备应使用不同入口 IP、网络提供商和传输外观。
6. **配置一致性是最高频的静默失败原因。** 字段命名、默认值、版本要求都必须逐端显式核对。
7. **收到真证书、连接失败、节点不通各有原因，不能一律归因为协议被识别。**
