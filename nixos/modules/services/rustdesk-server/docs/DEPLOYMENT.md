# RustDesk Android 观影与远控

## 已实现的拓扑

本方案使用 `lejianwen/rustdesk-server` v0.1.2（内含 1.1.14 forapi）及 `lejianwen/rustdesk-api` v2.7。API 的登录/JWT/客户端 WebSocket 修复依赖 forapi hbbs，不能与官方 hbbs 混搭。NixOS 服务编排和隔离仍由本仓库声明，不运行 Docker、不启用 Pro 专属功能。

| 节点 | 角色                        | 原生客户端入口                                            | 纳入自动中继池           |
| ---- | --------------------------- | --------------------------------------------------------- | ------------------------ |
| fra0 | 唯一 hbbs/ID 数据库 + hbbr  | ID: `rustdesk.dora.im:21116`，relay: `fra0.dora.im:21117` | 是                       |
| sjc0 | hbbr                        | `sjc0.dora.im:21117`                                      | 是                       |
| cu   | hbbr，经 nft 本机端口重定向 | `cu.dora.im:50566`                                        | 否，按需在双方客户端手选 |

原生 ID 与 HTTPS API/管理后台共用 DNS 名称 `rustdesk.dora.im`：ID 使用 TCP/UDP 21116，API 使用 HTTPS 443。该 DNS 记录是未代理的 CNAME，原生 ID 流量直达 fra0；TLS Web 请求由现有 Traefik 转发。Relay 仍使用 fra0/sjc0 中继池。RustDesk 原生 ID/Relay 字段不是 HTTPS URL，不填写 `/rustdesk` 路径。客户端登录使用管理员用户名 `i` 和 SOPS `common.yaml` 的 `password`；设备连接仍需用户授权或会话密码。

fra0 是唯一注册中心；如果 fra0 故障，不能保证新会话建立。sjc0/cu 是媒体中继备选，不是第二份 hbbs 数据库。不要把两个独立 SQLite hbbs 放在轮询 DNS 后面冒充高可用。现有 ams0/hkg4 RustDesk 导入保持原行为，不加入这套身份或中继池。

## lejianwen API 控制面

fra0 启用后，API 只绑定 `127.0.0.1:21114`，由 Traefik 暴露为 `https://rustdesk.dora.im`。API 使用同机 PostgreSQL 的 `rustdesk` 数据库和同名数据库用户；连接复用现有 localhost 认证策略，不增加密码、监听地址或防火墙规则。资源链接、运行日志和迁移备份仍位于 systemd `StateDirectory=/var/lib/rustdesk-api`。

- 管理后台：`https://rustdesk.dora.im/_admin/`。
- Web Client：由 API release 提供的静态资源服务。
- 默认关闭公开注册；管理员用户名固定同步为 `i`，密码来自 SOPS `common.yaml` 的 `password`。fra0 API 启动前会同步该账号；发生改动时清除该账户旧 token。secret 不进入 Nix store、命令行参数、SQL 日志或 journal。其他普通用户仍通过管理后台创建。
- Swagger 默认关闭。生产配置使用 fra0 自己的 CNAME/DNS-01 TLS，不通过 HTTPS 代理转发 private JWT 或 RustDesk server 私钥。
- hbbs 配置 `MUST_LOGIN=Y` 和与 API 相同的 JWT key；API v2.7 配置同一 ID/relay 地址及 server public key。`secrets/common.yaml` 的 `rustdesk` 分组不完整时，构建校验或运行时凭据加载会阻止启动。
- sjc0、cu 只运行 forapi hbbr；不运行 API、不复制 SQLite，服务只加载公钥。共享加密文件的解密权限边界见下文。

仓库固定官方 release assets 的 SHA-256，不使用 floating Docker `latest`。API release 是 MIT；server forapi 使用其上游仓库 LICENSE/发布条件。升级前应一并更新兼容性、哈希和软件许可审查。API 仓库 v2.7 release note 说明 webclient2 因 DMCA 从该 release 移除；Web Admin、常规 Web Client 和地址簿仍按 release 配置提供。

管理员登录密码是 SOPS 中的 `password`，不是 API JWT 或设备连接密码。修改该 secret 后，sops-nix 会重启 API，启动前自动同步 PostgreSQL 管理员。密码实际变化时该管理员的旧 API token 会失效。

## PostgreSQL 存储与迁移记录

| 组件                                 | 数据位置                                              | 支持边界                                                                     |
| ------------------------------------ | ----------------------------------------------------- | ---------------------------------------------------------------------------- |
| API 用户、分组、地址簿、审计等应用表 | fra0 PostgreSQL 数据库 `rustdesk`                     | v2.7 原生支持，配置类型必须为 `postgresql`                                   |
| hbbs 设备注册库                      | `/var/lib/rustdesk/db_v2.sqlite3` 及其 SQLite sidecar | 固定的 forapi v0.1.2 只支持 SQLite；改 PostgreSQL 需要另行批准的上游源码移植 |
| hbbr 连线与带宽状态                  | 各中继进程内存                                        | 没有持久数据库可迁移                                                         |
| 身份密钥、JWT、静态资源与运行日志    | SOPS、Nix store 或相应状态目录                        | 不是关系数据库表，保持各自存储方式                                           |

PostgreSQL 的数据库与所有者通过现有 `ensureDatabases`/`ensureUsers` 声明，只作用于 API 节点，不在 sjc0/cu 创建数据库。新数据库自动纳入现有 PostgreSQL `backupAll` 备份流程，不修改共享 PostgreSQL 认证策略。

### 2026-11-20 UTC 生产迁移

fra0 的 API 已由 SQLite 迁移至 PostgreSQL。停写后先执行一致性备份及完整性检查，再初始化原生 PostgreSQL 表结构，以 data-only 方式复制旧表数据并校准序列；17 张应用表逐表核验一致。原管理员 1 个、分组 2 个、版本记录 1 条；账号密码哈希、身份/角色 ID、分组名称、地址簿和版本内容均与停写快照一致。原 SQLite 与存在的 WAL/SHM 保留为 `.pre-postgresql`，不再供 API 读写。

一次性迁移服务、runtime 迁移入口、旧 SQLite 启动条件及 pgloader 测试依赖均已从正常配置移除。后续系统更新只运行 PostgreSQL 版 API，不重复执行迁移。其他旧 SQLite 实例若复用此配置，必须先独立备份并完成其数据迁移；不能把旧快照再次导入当前已使用的 `rustdesk` 数据库。

API 包显式提供 `ZONEINFO` 指向固定 `tzdata`，避免纯 Nix 环境缺少 `Asia/Shanghai` 时建表失败。此故障可能同时返回 HTTP 200，数据库就绪应结合实际表、账户数据和应用连接检查。

保留的恢复材料：

- `/var/lib/rustdesk-api/pre-migration-backup-nx9yh20u/rustdeskapi.db`：停写后的独立一致性快照。
- 同目录 `audit.json`：受限校验基线，仅保存表行数和数据摘要，不保存明文密码。
- 同目录 `postgresql-after-migration.dump`：验证后的 PostgreSQL custom-format 备份。
- `/var/lib/rustdesk-api/sqlite-pre-postgresql-*/`：迁移阶段的一致快照及受限阶段日志。
- `/var/lib/rustdesk-api/data/*.pre-postgresql`：保留的原库及存在的 sidecar。

备份目录权限 0700，备份文件权限 0600；不把内容提交到 Git、粘贴到聊天或输出到公共日志。恢复旧配置前应停 API，先备份并处理切换后新增的 PostgreSQL 数据，再用一致性快照恢复旧 SQLite 路径；不能只回滚 Nix 代际而遗漏数据库。hbbs 注册库和身份密钥没有迁移或轮换。

## 统一存放在 secrets/common.yaml

所有节点从同一份 `secrets/common.yaml` 读取 RustDesk 密钥，以 YAML 二级映射组织。Nix 的 `rustdesk/server_public_key` 表示 `rustdesk` 映射下的 `server_public_key`，不是带斜杠的 YAML 顶层键。

以下仅为结构示意，填写时必须替换为 fra0 已有的真实值：

```yaml
rustdesk:
  server_private_key: |-
    <fra0 已有的完整 Ed25519 PEM 私钥，保留 BEGIN/END 行>
  server_public_key: "<与上述私钥匹配的完整 ssh-ed25519 公钥行>"
  api_jwt_key: "<fra0 已有的 API JWT key>"
```

| 新的 common.yaml 路径         | 旧 fra0 文件中的字段         | 格式                           |
| ----------------------------- | ---------------------------- | ------------------------------ |
| `rustdesk/server_private_key` | `rustdesk_server_key`        | 完整多行 PEM 私钥              |
| `rustdesk/server_public_key`  | `rustdesk_server_public_key` | OpenSSH `ssh-ed25519` 公钥整行 |
| `rustdesk/api_jwt_key`        | `rustdesk_api_jwt_key`       | 原 API JWT key 字符串          |

由用户使用 `sops secrets/common.yaml` 迁移实际值；旧值可从 `secrets/terraform/hosts/fra0.yaml` 的 SOPS 编辑视图取得。若此前已在 common 顶层添加 `rustdesk_server_public_key`，需要在 SOPS 编辑视图中把它移入上述分组。不要直接重命名加密 YAML 的键或复制 `ENC[...]` 密文。

必须保留 fra0 现有身份和 JWT，不为 sjc0 重新生成一套公私钥，也不要用随机字符串替换已有私钥。`rustdesk-server-key` 输出的 base64 原始公钥用于客户端；common 中仍需 OpenSSH 格式。迁移前后实际密钥值不变，只改变读取位置和名称。

运行时路径是 `/run/secrets/rustdesk/server_private_key`、`/run/secrets/rustdesk/server_public_key`、`/run/secrets/rustdesk/api_jwt_key`。fra0 声明并加载三项，sjc0/cu 仅声明并加载公钥；systemd 仍通过 `LoadCredential` 注入，主私钥和 JWT 不进入 Nix store、API YAML 或公开 JSON。

**共享文件的权限边界：** common 的 SOPS 规则允许多个节点解密同一文件。把私钥和 JWT 放入 common 后，持有该文件解密身份的节点可以解密这些值，即使其服务没有声明或加载它们。角色条件只控制运行时文件和服务凭据，不提供加密上的主机隔离。

这四项套件密钥（包括 `livekit/master_secret`）不再使用 `terraformOutput.enable`，因此 `terraform-outputs-extract-secrets` 不会覆盖 common 中的手工维护值。已有 Terraform 身份资源和输出保留用于迁移，不删除、不轮换；已有值齐备时，此次迁移本身无需 Terraform apply。DNS 等基础设施变更仍按原 Terraform 流程由用户操作。

common 字段就绪后再部署。服务显示 active 也可能仍是旧系统的 hbbr，应同时核对实际激活的系统、可执行文件和真实中继流量。

## 自动选择与故障边界

保持 `ALWAYS_USE_RELAY=N`，允许客户端先尝试直连。失败后使用 hbbs 返回的 hbbr。OSS 1.1.16 对两个以上 relay 每 3 秒发起一轮并发 TCP 检查，每地址约 3 秒连接超时，然后在有连接成功的候选中轮询：

- 检查的是 **fra0 到 relay 的 TCP 可达性**，不是两部手机到节点的 RTT/丢包/吞吐。
- 不是自动最近或最低 RTT 选择；若所有候选都探测失败，上游保留上一轮列表，不能称严格剔除全部死节点。
- 建立的 relay 会话固定在一台机器，节点失效或 Wi-Fi/蜂窝切换需要客户端恢复/重连，不承诺视频无中断或转到最优节点。
- 国外无法主动访问 cu，因此默认池仅含 fra0、sjc0；cu 若加入，会被国外探测排除。双方均可达 cu 时可手动指定 `cu.dora.im:50566`，ID Server 仍用 fra0。手选中继不等于强制中继，客户端直连逻辑仍独立。
- Pro 的 GeoIP 选择需要另购和配置，且地理最近也不等于实测网络最好。本次未部署或购买 Pro。

## 端口与 cu 的最小暴露

| 节点 | TCP 公网端口        | UDP 公网端口 | 说明                            |
| ---- | ------------------- | ------------ | ------------------------------- |
| fra0 | 21115、21116、21117 | 21116        | NAT 测试、注册/信令、原生 relay |
| sjc0 | 21117               | 无新增       | 仅原生 relay                    |
| cu   | **50566**           | **无新增**   | 只占一个供应商映射 TCP 端口     |

cu 的 50560/SSH、50561-50565/kernel-relay、50567/EasyTier、50568/DN42 NAT-T、50569/HTTPS 均保持不变。5352/LiveKit TURN 等既有配置不变，不注入 Linux sysctl。

**不能直接让 hbbr 监听 50566**：上游还会绑定 `port + 2` 的 WebSocket，即 TCP 50568。为避免与已登记端口及未来服务冲突，cu hbbr 仍监听内部 TCP 21117/21119，nftables 仅将外部目的 50566 重定向到 21117。内核保留真实源地址，不经过 loopback TCP 代理。hbbr 将 loopback 连接视为管理命令，Traefik/HAProxy 转发到 127.0.0.1 会破坏原生会话，因此不能用它代替该映射。

模块在 cu 拒绝对内部 21117 的非映射外部连接，并拒绝各节点无需使用的 WebSocket 端口。NixOS input 规则看到重定向后的端口，所以 `allowedTCPPorts` 包含内部 21117；前置 `native_only` 链检查 conntrack 原始目标端口，实际公网入口仍只有 50566。现有 cu 对整个 5056x 的防火墙许可未扩大。

本次不开放 21118/21119，不提供网页 RustDesk 客户端，原生 Android 客户端不需要它们。

## 密钥与身份保持

`terraform/rustdesk.tf` 使用 `tls_private_key` 生成真正的 Ed25519 密钥对，并设置 `prevent_destroy`。不能使用 64 个随机字节直接当成 Ed25519 密钥：libsodium 所需格式是 **32 字节 seed + 由该 seed 推导的 32 字节公钥**，必须匹配。

- Terraform 既有敏感输出 `rustdesk_server_key` 是 PEM 私钥，迁移时原样放入 common 的 `rustdesk/server_private_key`；仅 fra0 服务加载。
- 既有输出 `rustdesk_server_public_key` 是 OpenSSH 公钥，迁移至 common 的 `rustdesk/server_public_key`；运行时转换为 RustDesk 所需的 base64 原始公钥，三个节点都读取同一项。
- 运行时 `runtime.py` 验证密钥类型和公私匹配，在 fra0 状态目录生成 base64 libsodium 格式的 `id_ed25519`，权限 0600。命令行和 Nix store 没有私钥。
- 若已有状态中的 `id_ed25519` 不同、存在 `.env` 覆盖或符号链接，会拒绝启动，**不会自动轮换/覆盖已有 RustDesk 身份**。部署前应备份并迁移已有实例。不要删库或删密钥来跳过该检查。
- hbbr 仅通过凭据接收经过转换的公钥，设置 `KEY`，拒绝不匹配的 relay 请求；sjc0/cu 的服务没有私钥凭据。服务器公钥不是访问设备的密码，手机端仍需临时会话密码或手动同意。
- `/var/lib/rustdesk` 和其中的 fra0 `db_v2.sqlite3` 随既有全局 `/var/lib` 持久化，沿用 Nixpkgs 非特权用户/沙箱。

Terraform 既有 state 本身仍包含初始私钥。继续使用仓库现有加密 state/outputs 流程，不将明文 state、plan 或私钥提交到 Git，不把私钥写进 `lib/data/data.json`。服务以 common 为读取来源，不再要求各 host 的 Terraform SOPS 文件包含 RustDesk 字段。实际值迁移和解密由用户操作。

初稿中的 `random_id.rustdesk_server_key` 已替换为真实 Ed25519 资源，尚未用于生产。若你已自行 apply 初稿，应审查 plan 中该未使用随机值的移除；不得把随机 64 字节当作合法私钥，也不要擅自替换已有设备信任的真实身份。

## 用户部署步骤

1. 将本次新增源码纳入你的 Git 源边界；Git-backed Flake 不读取未跟踪导入。无需为了本任务更新其他 inputs。
2. 使用 SOPS 把已有 RustDesk 三项密钥及 LiveKit 主密钥迁移至 common 的二级分组；保留既有值，避免身份或令牌意外轮换。DNS 已就绪时无需为此次迁移再次 Terraform apply。
3. 确认 common 的 SOPS recipients 覆盖待部署节点；配置或字段存在不代表目标节点实际可以解密。不把值粘贴到聊天或日志。
4. 部署本次已获授权的节点；cu 仍按任务约定暂缓。所需字段尚未就绪时构建校验或 `LoadCredential` 会阻止启动，而不是自动生成另一个身份。
5. 在 fra0 可信终端运行 `sudo rustdesk-server-key`，输出客户端应信任的 **base64 原始公钥**，不是 Terraform/OpenSSH 公钥整行，也不是私钥。将该公钥提供给双方客户端。

| Android 字段 | 普通模式                              | 国内 cu 手选模式           |
| ------------ | ------------------------------------- | -------------------------- |
| ID Server    | `rustdesk.dora.im:21116`              | `rustdesk.dora.im:21116`   |
| Relay Server | 留空，使用健康候选池                  | `cu.dora.im:50566`         |
| API Server   | `https://rustdesk.dora.im`            | `https://rustdesk.dora.im` |
| Key          | `sudo rustdesk-server-key` 返回的公钥 | 同左                       |

不要将 URL `https://fra0.dora.im` 当成 API Server。本方案的 API 地址是 `https://rustdesk.dora.im`，管理后台是 `/_admin/`；hbbs 已启用账户登录要求。管理员创建并启用用户后，再在客户端完成登录。

## 安卓红果：画质、音频、控制与穿透

服务器只转发加密数据，不解码、转码或选择 codec；不能从 Nix 把所有 Android 客户端强制改成 HEVC/AV1。客户端设置项可能随版本改变，以实装版本界面和质量监视器为准：

| 项目       | 建议起点                                                              | 验收标准                                                 |
| ---------- | --------------------------------------------------------------------- | -------------------------------------------------------- |
| 硬件编解码 | 开启 Hardware codec；双方可用时先尝试 HEVC                            | 质量监视器显示实际 codec，不只看下拉框                   |
| 视频编码   | HEVC 硬编优先；AV1 若只有软件编码先检查热量与实际 FPS；H.264 兼容回退 | 避免为了 AV1 名称造成掉帧。AV2 当前无本方案支持路径      |
| 分辨率     | 原生分辨率；关闭 Android 软件编码 half-scale                          | 1080×2400 的手机不应实际只发送 540×1200                  |
| FPS        | 影视先 30，再按源片/实际设备试 60                                     | 120 是部分客户端 UI 请求上限，不是 Android 硬编实测保证  |
| 画质/码率  | Custom，从 100% 起；链路允许时提高                                    | 百分比不是 Mbps。观看字幕/运动细节并记录实际吞吐和丢帧   |
| ABR        | 开启                                                                  | 弱网自适应，保留恢复能力；不把固定高码率灌满链路         |
| 音频       | 开启 Audio capture，非必要关闭麦克风                                  | 对方听到系统内录，不是扬声器经麦克风重录                 |
| 远控       | 用户同意后开启 Input control/Accessibility                            | 点击、拖动、撤销授权后立即停止；不默认无人值守           |
| 画面监视   | 开启 Show quality monitor                                             | 记录 codec、真实尺寸、实际 FPS、带宽/延迟及 direct/relay |

本地 relay 单会话上限为 128 × 1024² bit/s（约 **134.22 Mbps**），节点总上限为 1024 × 1024² bit/s（约 **1.074 Gbps**）。这是宽松的传输限额，不是编码目标，也不表示节点实际带宽达标。长期会话降级限额提升至相同 128 单位，避免 stock 的 32 单位降速。可按 `services.rustdesk-server.cluster.bandwidth` 覆盖；cu 的实际供应商带宽仍是硬上限。

不要直接照抄最新客户端的 `enable-webrtc`、UDP/IPv6 punch 选项并声称 1.1.16 OSS 已支持。官方部分选项有特定客户端/Pro 版本前提；本次可靠基线是 stock TCP NAT 测试、直连尝试、TCP relay。新传输能力需客户端与服务器双方实际协商和真机验证，不冒充已开启。

## 验证边界

专项 check：`nix build .#checks.x86_64-linux.rustdesk-cluster-test --no-link -L`。协议测试使用三个节点实际配置的 forapi 包，不以官方旧包代替。包含真实 Ed25519 签名、公私不匹配拒绝、已有身份不变、真实 hbbs UDP 注册，以及 hbbr 拒绝错误 key、认证后二进制双向转发。API smoke 使用固定发布二进制和临时 PostgreSQL，验证普通数据库所有者权限、原生建表、账户和 JSON/布尔/时间数据跨重启保持、自动 ID 序列以及 HTTP 200；不再保留一次性 SQLite 迁移测试。WebSocket 仅在本地协议测试时使用，生产未对外暴露。

生产中继探测记录：两端同时提交同一 UUID 的原生握手曾在 fra0 和未修改的 sjc0 上失败。固定上游的配对表 remove/insert 使用两个独立锁，存在并发配对竞态；本次没有修改上游源码。按发起端先请求、对端随后建立连接的正常顺序，两节点重复三轮双向二进制转发及错误公钥拒绝均通过；不能据此宣称并发边界已修复。

配置测试检查三节点角色、common 二级字段来源、私钥/JWT 仅在 fra0 声明、relay CSV、cu 端口与 DN42/EasyTier 不冲突，并确认 Terraform 提取模板已排除 RustDesk 密钥。该检查不证明 common 中已填入正确值或节点能解密。cu nft 重定向以 NixOS `nft check` 做构建期检查；这不是实机 NAT 端到端测试。部署后需要在能访问 cu 的国内网络测试 50566，而不是从国外主动探测 cu。

部署后验收：ID 注册、优先 direct、强制 relay 时分别命中 fra0/sjc0、手选 cu、错误 key 拒绝、重连其他 relay、长于 30 分钟的持续观影、Wi-Fi/蜂窝切换、真实内录音质/实际 codec/FPS/尺寸、授权与撤销远控。不要用 service active 替代这些测试。

## 借鉴的上游与 GitHub 配置

| 来源                                                                                                                                                           | 采用                                               | 未照搬                                        |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------- | --------------------------------------------- |
| [锁定 Nixpkgs 模块](https://github.com/NixOS/nixpkgs/blob/d5cc6833999746cffdfe0598f7bc801a57b887a9/nixos/modules/services/monitoring/rustdesk-server.nix)      | 非特权服务、systemd 沙箱、StateDirectory、角色开关 | 全开 WebSocket 防火墙、错误的 relay 分隔符    |
| [官方 1.1.16 Compose](https://github.com/rustdesk/rustdesk-server/blob/1.1.16/docker-compose.yml)                                                              | signal/relay 分离和持久化                          | Docker、floating latest、无 key 检查的裸 hbbr |
| [官方 FreeBSD relay 服务](https://github.com/rustdesk/rustdesk-server/blob/1.1.16/rcd/rustdesk-hbbr)                                                           | 独立账户与稳定状态目录                             | 在 relay 自动生成新的身份                     |
| [官方 relay-only Compose 及 Pro 说明](https://github.com/rustdesk/doc.rustdesk.com/blob/master/content/self-host/rustdesk-server-pro/relay/_index.en.md)       | relay 只使用公共 KEY                               | 私钥分发到 relay、付费 GeoIP 当成 OSS         |
| [1.1.16 hbbs 选路源码](https://github.com/rustdesk/rustdesk-server/blob/1.1.16/src/rendezvous_server.rs)                                                       | 3 秒健康检查与轮询的真实语义                       | 客户端 RTT 自动最优、正在观看中无缝迁移承诺   |
| [Android 官方说明](https://rustdesk.com/docs/en/client/android/)及[客户端选项](https://rustdesk.com/docs/en/self-host/client-configuration/advanced-settings/) | 系统音频、授权控制、ABR/硬编选项和版本边界         | 把 Pro 策略推送能力当成 OSS 服务配置          |
