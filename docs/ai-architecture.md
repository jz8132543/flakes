# NixOS 全栈 AI 基建与数字伴侣架构设计与运维实战指南

## 一、 宏观架构总览与 Life-OS 情感伴侣愿景

本系统基于 **NixOS Flakes** 现代化声明式基础设施与容器化编排，为自建数字生活基建（Life-OS）打造了一套完整的全栈 AI、知识工程与拟人化情感陪伴中枢。

系统贯彻**单一事实来源（Single Source of Truth）**、**100% 声明式开箱即用（Zero-Config Post-Deploy）**与**数据/状态严格持久化（Impermanence + 5GB Restic 严苛灾备）**三大工程原则：

1. **单一事实来源与零手动配置**：所有身份认证（Keycloak OIDC）、API 路由（New-API）、模型映射、工具注册（ContextForge + FastMCP）与反向代理（Traefik），在部署完成后无需任何人工点击网页 `/install`、复制粘贴 API Key 或修改配置，全部由声明式代码与幂等脚本全自动初始化。
2. **多模态与拟人情感中枢正交解耦**：底层由模型网关接入高性价比模型矩阵；中间层由 FastMCP 工具箱和 Dify 负责知识检索与工作流；顶层由统一的人设编译器（Persona Engine）负责格式解析、世界书触发、草稿箱撕毁、多气泡拆分与跨平台状态机，再通过统一接口分发至 QQ（NapCat + AstrBot）、微信（官方 iLink）与 Matrix。
3. **数字生活基建全链路感知（Life-OS Sync）**：AI 伴侣深度融合个人生活服务，不仅能闲聊，还能读取随手记（Memos）、考公刷题动态（Kaogong）、影音库更新（Jellyfin / MoviePilot）、智能家居传感器（Home Assistant）与全球分布式网络健康度（DN42 BGP / ATC CDN / VictoriaMetrics），成为真正生活在数字系统里的全知伴侣。
4. **遵循 Haumea/Rake 无 `default.nix` 递归收集规范**：整个 `services/ai/` 及其子目录（`gateway/`、`mcp/`、`dify/`、`companion/`）严格**不使用 `default.nix`**。根据仓库 `lib/rake.nix` 基于 Haumea 的加载机制，无 `default.nix` 时 Haumea 会自动遍历目录下全部模块，并通过 transformer 动态挂载 `.all` 递归展平属性。在主机配置中只需写 `imports = nixosModules.services.ai.all;` 即可一键声明式装配全部 AI 模块。

---

### 1.1 模块目录规范与递归加载机制

```text
nixos/modules/services/ai/
├── gateway/
│   ├── new-api.nix             # New-API 聚合底座与模型矩阵 (nixosModules.services.ai.gateway.new-api)
│   └── cpa.nix                 # CPA 代理与逆向通道 (nixosModules.services.ai.gateway.cpa)
├── mcp/
│   ├── common.nix              # ContextForge 基础选项与持久化
│   ├── containers.nix          # ContextForge 容器拓扑与 Keycloak SSO 挂载
│   ├── db-init.nix             # 自动向 ContextForge 注册虚拟网关
│   ├── degoog-bridge.nix       # 隐私搜索与深度正文提取 FastMCP
│   ├── lifeos-bridge.nix       # 个人生活基建 MCP 工具箱 (Memos, 考公, 影音, 智能家居, 监控)
│   ├── traefik-proxy.nix       # ContextForge Traefik 反向代理
│   └── backup.nix              # MCP 备份配置
├── dify/
│   ├── common.nix / containers.nix / db-init.nix / traefik-proxy.nix / backup.nix
└── companion/
    ├── common.nix              # 伴侣通用选项、端口、持久化与反向代理
    ├── persona-engine.nix      # 人设编译器、记忆中枢、出站清洗、主动关怀与告警 Webhook
    ├── qq-astrbot.nix          # AstrBot + NapCat (OneBot v11) 与平滑自愈工具 heal-napcat-ws
    ├── wechat-ilink.nix        # 微信官方 iLink 长轮询与 24h 窗口智能保活
    ├── matrix-bot.nix          # Matrix 端到端加密 E2EE 伴侣通道
    └── backup.nix              # 5GB 极简灾备排除规则 (过滤群聊图片/音视频)
```

> **Haumea 导入语法示例**：
>
> ```nix
> # 在 fra0/default.nix 中整包导入：
> imports = nixosModules.services.ai.all;
>
> # 或在边缘节点/特定机器仅导入部分子系统：
> imports = nixosModules.services.ai.companion.all; # 仅伴侣系统
> imports = nixosModules.services.ai.gateway.all;   # 仅模型网关
> ```

---

### 1.2 系统架构全景图

```
                           [ 用户交互终端 (Client Interaction) ]
                                    |
          +-------------------------+-------------------------+
          |                         |                         |
          v (OneBot v11 WS)         v (HTTP Long-Poll)        v (Matrix E2EE)
    [ QQ 客户端 / 群聊 ]       [ 微信个人号 (免风控) ]      [ Matrix 加密房间 ]
          |                         |                         |
          v                         v                         v
+-------------------+     +-------------------+     +-------------------+
|     NapCatQQ      |     |  wechat-ilink     |     |   matrix-bot      |
|  (无头 NTQQ 协议)  |     | (24h窗口智能保活) |     |  (永不失联保底)   |
+-------------------+     +-------------------+     +-------------------+
          |                         |                         |
          v                         |                         |
+-------------------+               |                         |
|      AstrBot      |               |                         |
| (表情转译/多模态)  |               |                         |
+-------------------+               |                         |
          |                         |                         |
          +-------------------------+-------------------------+
                                    | 统一 HTTP/JSON 对话载荷 (Session Scope)
                                    v
+-------------------------------------------------------------------------------+
|                 AI 拟人情感编译器与记忆中枢 (Persona Engine)                   |
|                                                                               |
|  • 人设编译器：SillyTavern 卡 (PNG V2/V3 / JSON)、世界书、大肥鱼 Markdown、SOUL.md |
|  • 动态宏展开：{{char}}, {{user}}, {{time}}, {{date}}, {{weekday}}              |
|  • 世界书扫描：常驻词条 + 关键词动态正则触发注入 Prompt                         |
|  • 拟真出站管道：撕毁（（内心独白））草稿箱、拟人橡皮擦、多气泡延迟拆分发送   |
|  • 主动关怀调度：22.5h 微信保活续期、晨起唤醒、深夜催睡、服务器告警拟人化转述 |
|  • 会话记忆存储：/var/lib/ai-companion/memory/companion.db (SQLite/状态机)   |
+-------------------------------------------------------------------------------+
         |                                                       |
         | 调用多模态推理与文本生成                               | 统一工具链挂载
         v                                                       v
+------------------------------------+   +--------------------------------------+
|       统一模型网关 (New-API)       |   |      IBM ContextForge MCP 总线        |
|                                    |   |                                      |
|  • companion-pro: step-5-preview,  |   |  • degoog-mcp: 隐私搜索与网页正文提取 |
|    glm-5.3 (高智商细腻陪伴)        |   |  • lifeos-mcp: 个人生活基建聚合工具:  |
|  • companion-flash: deepseek-v4.1  |   |    - memos_note: 随手记读写          |
|  • companion-audio: stepaudio-2.5  |   |    - kaogong_status: 考公刷题督学    |
|    (听写 ASR + 情绪语音条 TTS)     |   |    - movie_subscribe: 追剧点播       |
|  • companion-vision: qwen3-vl      |   |    - hass_sensor: 智能家居状态       |
|  • local-rp-model: arx8 算力协同   |   |    - infra_health: 集群与 BGP 监控   |
|  • 零配置固定令牌: internal-token   |   +--------------------------------------+
+------------------------------------+                      ^
         |                                                  |
         +--------------------------+-----------------------+
                                    |
                                    v
+-------------------------------------------------------------------------------+
|                    Dify 知识库与复杂工作流引擎 (Dify CE)                       |
|                                                                               |
|  • 社区版双模登录：账号 i 密码直登 + Keycloak OIDC 免密 SSO (GitHub OAuth 桥接) |
|  • 自动免配置向导：dify_setups 表自动标记完成，无需网页 /install 引导          |
|  • 自动注入 Degoog Search 联网搜索工具 (OpenAPI 3.0 Schema)                   |
|  • 向量存储：原生 Qdrant 实例 (/var/lib/private/qdrant)                       |
+-------------------------------------------------------------------------------+
```

---

## 二、 核心服务层详细分解与架构设计

### 2.1 模型网关与路由底座 (`nixos/modules/services/ai/gateway/`)

网关层确立 **New-API** 为全机唯一 OpenAI 兼容上游（Single Source of Truth），下接商业渠道与 CPA（CLI-Proxy-API）逆向代理：

1. **确定性密钥派生与免配置内部 Token**：
   - 过去各服务部署后需在 UI 手动复制粘贴 Token，违背 NixOS 声明式原则。
   - `new-api.nix` 在容器首次完成建表后，通过 `new-api-bootstrap.service` 自动向 `tokens` 表幂等插入一条无限额度的内部专用令牌：
     $$\text{Token} = \text{sk-ai-internal-} + \text{SHA256}(\text{SOPS password})[0:32]$$
   - 令牌同步落盘至 `/var/lib/new-api/internal-token`（权限 `0644`），供同机下游服务（Dify、Persona Engine、AstrBot）免配置直连调用。
2. **多模态与模型路由矩阵**：
   - 渠道自动绑定 `companion-pro`（指向高情商情感模型 `step-5-preview` / `glm-5.3`）、`companion-flash`（高频轻量总结）、`companion-audio`（`stepaudio-2.5-asr` 与 `stepaudio-2.5-tts`）及 `companion-vision`（`qwen3-vl`）。
   - 预留 `local-rp-model` 模型别名，在 `arx8` 本地 GPU 节点上线时，可通过内网优先直通本地无审查模型。

---

### 2.2 搜索与 Life-OS MCP 工具总线 (`nixos/modules/services/ai/mcp/`)

采用 **IBM ContextForge (ContextForge AI Gateway)** 作为集中注册中心，通过标准化 MCP 协议挂载两套 FastMCP 守护进程：

1. **`degoog-bridge.nix`（隐私搜索与深度网页提取）**：
   - 监听本地端口 `5005`，封装本地 `degoog.nix`（去谷歌化隐私聚合搜索引擎）。
   - 暴露 `search_web(query, limit)` 与 `fetch_webpage(url)` 两个核心工具。
   - 实现标准 MCP SSE 协议（`/sse` 与 `/messages`），并自动生成 OpenAPI 3.0 规范注入 Dify。
2. **`lifeos-bridge.nix`（数字生活基建聚合）**：
   - 监听本地端口 `5007`，以只读或受信操作直连本地运行的服务：
     - **Memos 随手记**：`memos_create_note`（随口让 AI 记录备忘）、`memos_list_recent`（闲聊时感知近期随手记动态）。
     - **考公督学**：`kaogong_daily_status`（获取刷题统计与错题本抽查）。
     - **影音自动化**：`moviepilot_subscribe`（自动检索与磁力订阅）、`jellyfin_recent_media`（查询最近入库大片）。
     - **智能家居**：`hass_get_state`（读取 Home Assistant 传感器如人体存在、光照、晚间灯光）。
     - **集群运维监控**：`infra_cluster_health`（读取 VictoriaMetrics 监控指标，汇总二十余个节点与 DN42 BGP 状态）。
3. **`db-init.nix` 自动注册**：
   - ContextForge 启动时自动读取 `/var/lib/contextforge/config/mcp_servers.json`，将 `degoog-search` 与 `lifeos-tools` 同时作为虚拟 MCP 工具池暴露给 AI 智能体。

---

### 2.3 Dify AI 平台零配置与双模登录 (`nixos/modules/services/ai/dify/`)

1. **管理员账户与免向导启动**：
   - `dify-db-init.nix` 在 API 容器迁移建表后触发 `dify-bootstrap.service`，使用 Python 对 `sops` 主密码执行 Dify 专用的 `PBKDF2-HMAC-SHA256` 盐哈希运算，Upsert 管理员账号 `i@dora.im` 并绑定租户。
   - 向 `dify_setups` 表插入当前版本初始化记录，用户打开浏览器直接呈现登录界面，彻底跳过网页首次 `/install` 引导。
2. **Keycloak OIDC SSO 破局**：
   - Dify 社区版官方在前端隐藏了通用 OIDC 按钮。
   - 方案通过只读挂载定制的 `/app/api/libs/oauth.py`，将原生启用的 GitHub OAuth 认证流透明重定向至 Keycloak 的 `/protocol/openid-connect/auth`、`token` 和 `userinfo` 端点，实现**管理员 `i` 密码登录与 Keycloak SSO 一键单点登录共存**。
3. **工具开箱即用注入**：
   - 启动时自动将 `degoog-bridge` 的 OpenAPI 结构写入 PostgreSQL 的 `tool_api_providers` 表，所有新建的 Chatflow 与 Agent 工作流均原生拥有联网搜索能力。

---

### 2.4 拟人情感中枢与全渠道 IM (`nixos/modules/services/ai/companion/`)

#### 1. 人设编译器与情感中枢 (`persona-engine.nix`)

监听本地端口 `5006`，作为整套系统的“认知与情感中枢”：

- **多格式人设热加载**：
  - 支持解析 SillyTavern 角色卡 V2/V3（自动解包 PNG `tEXt`/`iTXt` 的 Base64 `chara`/`ccv3` 元数据或 `.json` 结构）。
  - 自动进行动态宏替换（`{{char}}`, `{{user}}`, `{{time}}`, `{{date}}`, `{{weekday}}`）。
  - 具备世界书（World Info）关键词与正则递归扫描能力，命中时动态注入上下文。
  - 兼容大肥鱼 Markdown 人格模板与 `SOUL.md`。
- **拟真交互管道（Humanizer Pipeline）**：
  - **草稿箱撕毁**：严格正则清洗 `（（[\s\S]*?））`、`\(\([\s\S]*?\)\)` 以及 `<think>[\s\S]*?</think>`，将模型的心理活动和规划过程剥离，仅保留最终回复。
  - **三道拟人橡皮擦**：自动擦除“作为一个人工智能模型”、“很高兴为您服务”等 AI 客服口癖。
  - **多气泡延迟发送（Bubble Splitting）**：将长回复按语义和标点切分为 2~4 个短句，并计算拟真打字耗时（`len * 0.08s`，介于 `0.8s ~ 2.8s` 之间），指导客户端分段发送。
- **主动关怀与系统告警**：
  - `/v1/companion/proactive`：生成早安问候、夜间催睡或日常随性搭话。
  - `/api/v1/system-alert`：接收 Prometheus / Alertmanager 报警信息，让伴侣以符合人设口吻（亲昵、焦急、关切）将节点故障转述给主人。

#### 2. QQ 接入层 (`qq-astrbot.nix` · 基于 `dafeiyu-astrbot` 架构)

- **NapCatQQ**（无头 NTQQ，端口 `6098` WS / `6099` WebUI）负责 OneBot v11 协议通信。
- **AstrBot**（端口 `6185`）作为智能体中枢，通过内网直连 New-API 与本地模型。
- 配备 `heal-napcat-ws` 命令行工具，当检测到 QQ 连接断开时，通过 WebUI API 平滑重启 WebSocket 链路，无需重启容器，更**无需重新扫码**。

#### 3. 微信官方 iLink 接入层 (`wechat-ilink.nix`)

- 基于腾讯官方开放的 `ilinkai.weixin.qq.com` HTTP 长轮询协议。
- 凭证与游标落盘于 `/var/lib/ai-companion/wechat/ilink_auth.json`。
- **24 小时 context_token 智能保活机制**：
  - 每次用户交互自动缓存 `context_token` 并设置 24 小时有效倒计时。
  - 当距上次互动满 22 小时且处于日间时段时，主动触发一条自然日常话题，引导主人回复以刷新 24 小时窗口。
  - 若窗口超时失效，主动问候自动转交 QQ（NapCat 私聊）或 Matrix 发送。

#### 4. Matrix 端到端加密接入层 (`matrix-bot.nix`)

- 连接本地 Matrix 服务器（端口 `3090` / `m.dora.im`），提供端到端加密、零风控的私密伴侣通道。

---

## 三、 部署过程中的真实问题排查与代码实现剖析

在实际部署与服务编排中，遇到了多项由上游协议断层、数据库 Schema 演进和网络时序引发的问题。以下为具体排错原因与针对性解决方案：

### 1. Dify v1.17+ 数据库 Schema 不兼容导致 `dify-bootstrap` 启动崩溃

- **故障现象**：`systemctl status dify-bootstrap.service` 报错：
  ```text
  psycopg2.errors.UndefinedColumn: column "label" of relation "tool_api_providers" does not exist
  ```
- **原因分析**：Dify 在 1.17 之后重构了工具提供商元数据表 `tool_api_providers`，移除了 `label` 列，将多工具清单序列化为 `tools_str`（类型为 `text` 且为 `NOT NULL`），同时新增了 `custom_disclaimer`（`text` 且为 `NOT NULL`）。原初始化脚本依据旧版字段插入导致 SQL 语法失败。
- **代码实现修复（`nixos/modules/services/ai/dify/db-init.nix`）**：
  修改插入语句，生成包含工具基本元数据的 `tools_str` JSON 串，设置 `custom_disclaimer = ""`，并将 `label` 从列名中移除：
  ```python
  tools_str = json.dumps([
      {"name": "search_web", "label": "Search Web", "description": "Search the web via Degoog"},
      {"name": "fetch_webpage", "label": "Fetch Webpage", "description": "Extract clean webpage text"}
  ])
  cur.execute("""
      INSERT INTO tool_api_providers (
          id, user_id, tenant_id, name, schema, schema_type_str,
          tools_str, icon, credentials_str, description,
          custom_disclaimer, created_at, updated_at
      ) VALUES (
          %s, %s, %s, 'degoog', %s, 'openapi',
          %s, '{"content":"🔍","background":"#2563EB"}', '{}',
          'Local privacy search and article reader',
          "", NOW(), NOW()
      );
  """, (str(uuid.uuid4()), account_id, tenant_id, json.dumps(degoog_openapi), tools_str))
  ```

---

### 2. Dify Celery Worker 循环崩溃 (`ImportError: cannot import name 'decode_oauth_state'`)

- **故障现象**：`podman-dify-worker.service` 启动后立即退出，退出码为 2：
  ```text
  File "/app/api/controllers/console/auth/oauth.py", line 18, in <module>
    from libs.oauth import decode_oauth_state
  ImportError: cannot import name 'decode_oauth_state' from 'libs.oauth' (/app/api/libs/oauth.py)
  ```
- **原因分析**：为了实现 Keycloak SSO 登录，我们通过 Volume 挂载覆盖了容器内的 `/app/api/libs/oauth.py`。然而精简版的 `oauth.py` 遗漏了 Celery Worker 与控制台认证所需的 `decode_oauth_state`、`encode_oauth_state`、`OAuthState`、`OAuthUserInfo` 等关键数据结构，导致 Celery Worker 加载 `app_factory` 时直接中断。
- **代码实现修复（`nixos/modules/services/ai/dify/containers.nix`）**：
  提取官方 Dify 1.17 镜像内置的原版 `oauth.py` 源码骨架，在保留完整的类型定义（TypedDict）、Pydantic TypeAdapter 与状态编解码函数的前提下，仅重写 `GitHubOAuth` 类的 `_AUTH_URL`、`_TOKEN_URL` 与 `_USER_INFO_URL` 使其直连 Keycloak，确保 API 与 Worker 容器均能稳定导入。

---

### 3. AstrBot 监听端口冲突与 Traefik 代理 502

- **故障现象**：访问 `https://bot.dora.im` 出现 HTTP 502 Bad Gateway，且本地 `curl http://127.0.0.1:6180` 报错拒绝连接。
- **原因分析**：AstrBot 4.29+ 容器官方默认将 WebUI 仪表盘硬编码监听在 **6185** 端口，而我们在 `ports.nix` 中原登记为 6180。容器启动日志明确打印：
  ```text
  Starting WebUI at http://0.0.0.0:6185
  ```
- **代码实现修复（`nixos/modules/base/module/misc/ports.nix`）**：
  将 `config.ports.astrbot` 修正为 **6185**，Traefik 代理目标同步调整为 6185，网络流量正常打通。

---

### 4. 看门狗导致 NapCat 首次扫码死锁

- **故障现象**：NapCat 容器每隔几分钟自动重启，控制台二维码刚出来就被打断重刷，无法完成手机扫码授权。
- **原因分析**：原看门狗定时器每 5 分钟检查本地端口 6098（OneBot WS）是否处于 Listening 状态。但在首次部署尚未扫码登录时，NTQQ 不会拉起 WebSocket 服务端，导致看门狗误判服务死锁并强制重启 NapCat，从而形成了“未扫码 -> 杀容器 -> 生成新二维码 -> 再次杀容器”的恶性死循环。
- **代码实现修复（`nixos/modules/services/ai/companion/qq-astrbot.nix`）**：
  删除激进的重启看门狗，改为编写 `heal-napcat-ws` CLI 管理脚本。该脚本通过调用 NapCat WebUI 原生 HTTP API（`/api/OB11Config/GetConfig` 与 `SetConfig`），对 WebSocket 连接进行平滑重新触发，**不重启容器、不退登 QQ、不破坏登录态**。

---

### 5. ContextForge 启动瞬间 Keycloak 502 探测失败

- **故障现象**：ContextForge 启动日志中报错：
  ```text
  Failed to discover Keycloak endpoints from https://sso.dora.im/realms/users/.well-known/openid-configuration: Server error '502 Bad Gateway'
  ```
- **原因分析**：在 systemd 服务拓扑中，`podman-contextforge.service` 缺乏对 `keycloak.service` 的显式依赖。在机器开机或配置重载瞬间，ContextForge 立即向 Traefik 发起 OIDC Well-Known 抓取，而此时 Keycloak 正在进行 Quarkus 引导，导致首次抓取命中 502。
- **代码实现修复（`nixos/modules/services/ai/mcp/containers.nix`）**：
  在 `systemd.services.podman-contextforge` 中显式添加 `after = [ "keycloak.service" ]` 与 `wants = [ "keycloak.service" ]`，确保 Keycloak 处于 Ready 状态后再拉起 ContextForge。

---

## 四、 5GB Restic 严苛备份与持久化防爆设计

针对云服务器 5GB 远程冷备存储配额，在 `nixos/modules/services/ai/companion/backup.nix` 中设计了精细的排除策略：

```nix
services.restic.backups.borgbase = {
  paths = lib.mkAfter [
    "${cfg.dataDir}/personas"
    "${cfg.dataDir}/memory"
    "${cfg.wechat.dataDir}"
    "${cfg.matrix.dataDir}"
    "${cfg.qq.dataDir}/napcat/config"
    "${cfg.qq.dataDir}/astrbot/data/cmd_config.json"
    "${cfg.qq.dataDir}/astrbot/data/data_v4.db"
  ];
  exclude = lib.mkAfter [
    "**/napcat/data/**/ChatMsg/**"
    "**/napcat/data/**/Audio/**"
    "**/napcat/data/**/Video/**"
    "**/napcat/data/**/Pic/**"
    "**/napcat/data/**/OriPic/**"
    "**/napcat/data/**/Group/**"
    "**/napcat/data/**/Crashpad/**"
    "**/napcat/logs/**"
    "${cfg.qq.dataDir}/astrbot/data/logs/**"
    "${cfg.qq.dataDir}/astrbot/data/temp/**"
    "${cfg.qq.dataDir}/astrbot/data/attachments/**"
    "${cfg.qq.dataDir}/astrbot/data/site-packages/**"
    "**/cache/**"
    "**/temp/**"
    "**/__pycache__/**"
  ];
};
```

- **防爆效果**：
  - NapCat 在大型活跃群聊中运行数周会积累数 GB 的高清图片与短视频（存放在 `ChatMsg`、`Audio`、`Video`、`Pic`），这些属于易失性展示数据，排除后**备份体积从 3GB+ 直接降低至 35MB 左右**。
  - 灾备恢复时，只需 `restic restore` 恢复核心凭据与 SQLite 数据库，NapCat 即可免扫码秒级上线。

---

## 五、 部署、使用与操作维护手册

### 5.1 域名解析与 Terraform 编排

所有对外暴露的 AI 域名均已统一定义在 `terraform/cdn.tf` 中，解析到 `fra0` 节点：

- `api.dora.im` → New-API 网关
- `cpa.dora.im` → CLI-Proxy-API 逆向与商业 API
- `chat.dora.im` → Dify AI 应用与工作流平台
- `mcp.dora.im` → IBM ContextForge MCP 总线
- `persona.dora.im` → AI 伴侣人设编译器与记忆中枢
- `bot.dora.im` → AstrBot QQ 机器人管理后台
- `napcat.dora.im` → NapCat NTQQ 协议后台与扫码登录

推送 DNS 记录（由管理员执行）：

```bash
cd terraform && terraform apply
```

---

### 5.2 主机部署与启动验证

在主仓库根目录构建并部署系统：

```bash
# 本地切换并应用
sudo nixos-rebuild switch --flake .#fra0

# 检查服务健康状态
systemctl --failed
# 应返回: 0 loaded units listed.
```

---

### 5.3 QQ 机器人登录操作（NapCat 扫码）

1. 浏览器打开 `https://napcat.dora.im/webui/`（或通过 SSH 隧道访问 `http://127.0.0.1:6099/webui/`）。
2. 输入 WebUI Token：`91615548e98b` 进入控制台。
3. 界面显示 NTQQ 登录二维码，使用手机 QQ 扫描并确认授权。
4. 凭证将自动持久化保存在 `/var/lib/dafeiyu/napcat/data/` 中，后续重启无需再次扫码。

---

### 5.4 AstrBot 控制台配置

1. 访问 `https://bot.dora.im`（初始账密：`astrbot` / `PrQ79mV3Q9EkAHtrNs7h1II7`）。
2. 在「服务商配置」中添加 OpenAI 兼容接口：
   - Base URL: `http://127.0.0.1:3280/v1`（本机 New-API 端口）
   - API Key: 从 `/var/lib/new-api/internal-token` 获取固定令牌
   - Model: `companion-pro` 或 `gemini-3-flash`
3. 在「平台设置」中确认连接到 NapCat WebSocket：`ws://127.0.0.1:6098`。

---

### 5.5 人设导入与日常维护

- **酒馆卡热导入**：
  - 将网上下好的 SillyTavern `.png` 角色卡或 `.json` 角色卡直接放入 `/var/lib/ai-companion/personas/`，引擎即刻热加载。
  - 或直接在私聊中给机器人发送一张角色卡 PNG 原图，Persona Engine 自动解析隐写块并实时切换。
- **WebSocket 自愈**：
  - 若因网络波动导致 QQ 机器人掉线，无需重启容器，直接在终端执行：
    ```bash
    heal-napcat-ws
    ```
    即可无损刷新重连。
