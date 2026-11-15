# 部署与验收

## 当前已接入节点

| 节点 | 角色                                   | 信令域名                 | TURN 域名                 |
| ---- | -------------------------------------- | ------------------------ | ------------------------- |
| fra0 | SFU、TURN、网页/令牌 API、Redis 主节点 | livekit.dora.im          | livekit-turn.dora.im      |
| cu   | SFU、TURN，媒体公网 IPv6 only          | livekit-cu.dora.im:50569 | livekit-turn-cu.dora.im   |
| sjc0 | SFU、TURN                              | livekit-sjc0.dora.im     | livekit-turn-sjc0.dora.im |

DNS 记录在 `terraform/cloudflare.tf` 管理，全部 DNS-only，关闭 Cloudflare 橙云。`livekit-cu` 使用 A/AAAA：A 在每次 plan/apply 时查询 `cu.dora.im` 的 IPv4，AAAA 复用 `cuv6.dora.im` 的声明地址。不能在一个名称上同时放两个 CNAME，也不能 CNAME 与 A/AAAA 共存；`moved` 块保留已经 apply 的旧记录身份，先将 CNAME 改成 A，再创建 AAAA。新增 `hashicorp/dns` provider 后，需要用户先运行 `terraform-init`，再审查/apply DNS 变更；仅旧版 apply 不包含这次双栈修改。cu 的供应商 IPv4 若变化，需要重新 plan/apply 同步 A，DNS-only A 不会像 CNAME 一样自动跟踪变化。

cu 信令使用已有 IPv4 NAT 映射端口 `50569`，即 `wss://livekit-cu.dora.im:50569`，同时允许 IPv4/IPv6 访问；这不代表 IPv4 媒体端口已经映射。`livekit-turn-cu` 继续仅 CNAME 到 `cuv6.dora.im`，避免给客户端广告无法到达的 IPv4 TURN/3480。cu 媒体仍广告真实公网 IPv6，IPv4-only 客户端应优先使用 fra0/sjc0，不能靠增加 A 记录解决媒体跨地址族问题。

`terraform/password.tf` 提供独立敏感输出 `livekit_suite_master_secret`。apply 与秘密输出提取仍由用户执行；密钥未就绪前不进行远端部署。

主入口是 `https://livekit.dora.im`。可在浏览器观看手机发布的屏幕、内录音频并独立连麦；手机屏幕和内录的发布需要原生 Android LiveKit 应用，Android 浏览器普遍不能代替 MediaProjection 采集系统屏幕。

LiveKit 原生客户端通常填写 `wss://livekit.dora.im` 加一枚 JWT，而不是只输入裸 `fra0`/IP 就自动登录。任意名为 LiveKit 的示例 App 不一定读取本套件的发现协议。支持此接口的定制 App 可以用 `https://livekit.dora.im/config.json` 或 `/.well-known/livekit-suite` 获取公开配置，再用加入凭据调用 `/api/session`。这些路径是本套件协议，不是 LiveKit 通用标准或 LiveKit Cloud Sandbox 协议。

## Flake 导出与单行接入

### 参数与拓扑的职责

`settings.nix` 目前只定义编解码、音频处理、ICE、端口默认值和房间策略，不包含主机清单。将节点、角色、域名、Region 和公开入口统一为 Terraform 的非敏感 output 后，可通过已有 `lib/data/template.yq` 导出到 `lib/data/data.json`，再从 `lib/default.nix` 供 Nix 模块读取；不需要直接解析 HCL，也不需要再遍历 `self.nixosConfigurations`。公开拓扑不能包含 JWT 签名密钥、Redis 密码或 TURN secret。

当前尚未把 LiveKit 拓扑接到这个 output，发现仍使用元数据树；不能在没有生成对应 JSON 数据的情况下删掉发现逻辑。建议最终让 Terraform 唯一管理基础设施拓扑，`settings.nix` 唯一管理频繁调整的媒体策略，避免两边复制同一份节点或参数。若明确选择将媒体参数也统一进 Terraform，`settings.nix` 可移除，但每次改码率/帧率都需要刷新 Terraform outputs 并重新提取公开 JSON，不能认为编辑 `.tf` 后 Nix 会自动读取未应用的 locals。

仓库已经在 `flake/hosts.nix` 和 `flake/colmena.nix` 将 `nixos/modules/services/livekit-suite/` 挂到 `nixosModules.services.livekit`，不受自动 rake 的 `.all` 列表变换影响。在其他 Flake 可这样导出：

```nix
{
  outputs = inputs@{ self, nixpkgs, ... }: {
    nixosModules.services.livekit = import ./nixos/modules/services/livekit-suite;
    nixosConfigurations.fra0 = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit self; };
      modules = [ ./hosts/fra0 ];
    };
  };
}
```

已有网络、密钥和 TLS 入口声明的节点，角色启用只需：

```nix
{ self, ... }: {
  imports = [ self.nixosModules.services.livekit.all ];
}
```

角色导入会静态启用 `_meta.enable`，无需再维护启用节点名单。它不能凭空注册域名、签发证书、猜测 NAT 映射或制造多节点共同密钥。首次接入必须提供网络元数据与 TLS 适配。在本仓库三个主机已经添加对应声明和 `infrastructure.nix` 适配器；不需要用户再手工补充。通用模块可以单独导入 `sfu`、`turn`、`web` 或 `redis`。

```nix
{ config, ... }: {
  services.livekitSuite = {
    secretFile = config.sops.secrets.livekit_suite_master_secret.path;
    interfaces = [ "eth0" ];
    _meta = {
      domain = "livekit.example.org";
      turnDomain = "turn.example.org";
      publicIpv4 = "203.0.113.10";
      publicIpv6 = "2001:db8::10";
      privateAddress = "192.0.2.10";
      region = "eu-central";
      latitude = 50.1109;
      longitude = 8.6821;
      primary = true;
    };
    tls = {
      certFile = "/run/secrets/turn-cert.pem";
      keyFile = "/run/secrets/turn-key.pem";
    };
  };
}
```

以上地址是文档占位的 RFC 保留地址，不能直接部署。默认 Coturn 假定 `publicIpv4/publicIpv6` 存在于本机接口；复杂 NAT 的公网/私网一对一映射需要额外适配，不应把公网 IP 当成本机可绑定 IP。sfus 共用一个 Redis，新增普通边缘节点应设置 `redis.enable = false; web.enable = false;`。若多台都导入 all 且不关闭 Redis，SFU 配置会明确拒绝把独立 Redis 当成协调集群。

调参示例：

```nix
services.livekitSuite = {
  interfaces = [ "ens3" ];
  _meta.region = "ap-east";
  settings.media.video = {
    frameRate = 60;
    maxBitrate = 12000000; # bit/s; 0 means omit additional application cap
  };
  settings.media.screenAudio.audioBitrate = 320000;
};
```

## 密钥输出准备

先由用户执行现有 Terraform 工作流。不要将明文输出粘贴到 Nix、日志、网页或聊天中。若使用 `terraform-pipe`，它除了 apply 还会更新输出、提取加密密钥、格式化并提交/推送 secrets 仓库，应确认自己接受这些副作用。单独执行 apply 后，还必须完成输出与秘密提取：

```bash
terraform-wrapper apply
terraform-update-outputs
terraform-outputs-extract-secrets
```

这些是仓库 devshell 中已有命令，提取命令在本地处理敏感数据并重新 SOPS 加密。应确认 `secrets/terraform/hosts/{fra0,cu,sjc0}.yaml` 均包含非空的 `livekit_suite_master_secret`，并确认三个节点的 age 私钥可以解密对应文件。**只有 DNS apply 成功，不代表部署密钥已经就绪。** 准备前相关服务即使有配置也不会启动；全量 build 的 SOPS 文件校验也可能因此失败。

运行时路径为 `/run/secrets/livekit_suite_master_secret`，经 `LoadCredential` 注入服务。`sops-install-secrets.service` 是显式依赖，秘密更新会重启相关服务。需要轮换时更新主种子并一致地部署所有节点；不能假设滚动更新期间不同种子的节点可以继续互通。

agenix 或独立文件部署同样可用 `secretFile = "/run/agenix/livekit-master"`，文件需要至少 32 字节的真正随机材料，不应使用人类密码。开发机可显式设置 `development = true`，首次启动会在 `/var/lib/livekit-suite/master-secret` 生成随机种子；这只适合单机，不得在三个节点分别自动生成后期待集群互通。启用 impermanence 的开发机需要将该目录加入持久化声明。

## 防火墙与入口

| 端口                | 用途                           | 暴露范围                           |
| ------------------- | ------------------------------ | ---------------------------------- |
| TCP 443             | WSS/HTTPS 与 TURN/TLS SNI 复用 | 公网 Traefik                       |
| TCP 8443 / cu 50569 | 已有备用 HTTPS/TURN TLS 入口   | 保留现有端口声明                   |
| TCP 17980           | SFU API/信令                   | 仅 127.0.0.1，由 Traefik 转发      |
| TCP 17981           | WebRTC ICE/TCP                 | 各节点公网，不能经 HTTP 代理       |
| UDP 63000-63999     | SFU ICE/媒体                   | 各节点公网                         |
| UDP/TCP 3480        | Coturn STUN/TURN               | 各节点公网                         |
| TCP 5351            | Coturn PROXY v2 内部端口       | nftables 仅允许 loopback           |
| UDP 64000-64499     | 普通 UDP/TCP Coturn relay      | 各节点公网                         |
| UDP 64500-64999     | TLS/PROXY Coturn relay         | 各节点公网                         |
| TCP 6390            | Redis                          | fra0 loopback + fra0.ts 的私网地址 |
| TCP 17990           | 网页/配置/令牌 HTTP 后端       | 仅 127.0.0.1                       |

现有 MatrixRTC 的 7880/7881/50000-60000、既有 Coturn 3479/5349、DERP 3478 和 SSH transport 的 61001-61999 不变；套件不调整 Linux sysctl/qdisc。5350 是通用直连 TLS 模式的监听端口，本仓库采用 Traefik TLS 终止，因此不会向客户端广告或开放它。

TURN 域名必须被证书覆盖，单层 `*.dora.im` 已有证书适用。Traefik 使用现有证书体系；TURN 专用 TLS options 不强制 HTTP ALPN。普通 HTTPS 路由照常工作，只有 TURN 域名 SNI 匹配专用 TCP 路由。cu 443/TLS 的 IPv6 可达性必须实测；若运营商封锁，需要同时修改其实际公开入口与元数据广告端口，不能只改 DNS。当前配置不假设能新增 cu IPv4 端口映射。

## 用户接入

部署后在 fra0 的可信终端读取加入凭据：

```bash
sudo livekit-suite-access
```

该命令仅显示派生的用户加入凭据，不显示主种子、API 签名 secret 或 Redis 密码。加入凭据可进入任意合法名称的房间并发布/订阅，但没有服务管理权限；只分发给可信人员。

网页访问 `https://livekit.dora.im`，输入房间名与加入凭据。手机原生应用获取 token 的请求示例：

```http
POST /api/session HTTP/1.1
Host: livekit.dora.im
Authorization: Bearer USER_JOIN_KEY
Content-Type: application/json

{"room":"screen-room","node":"fra0"}
```

响应包含 `serverUrl`、`token`、随机 `identity`、`expiresAt` 和带短期凭据的 `iceServers`。App 使用返回的 URL/token 调用 LiveKit `connect`。不要把主种子/API secret 当作客户端 token，不要在 URL query 中传入加入密码。网页不把这些凭据写入 localStorage。长时间断网后若旧 token 过期，重新调用认证接口，不凭空认为任何演示 App 都会自动刷新。

## 分阶段验收

本地先验证源码与求值，不要求 DNS 就绪：

```bash
nix eval --impure --json --expr 'let f = builtins.getFlake (toString ./.); in import ./nixos/modules/services/livekit-suite/test-discovery.nix { lib = f.inputs.nixpkgs.lib; }'
python3 -B nixos/modules/services/livekit-suite/test-runtime.py -v
python3 -B nixos/modules/services/livekit-suite/test-android-control.py -v
node --check nixos/modules/services/livekit-suite/frontend/app.js
nix build .#checks.x86_64-linux.livekit-suite-test --no-link
nix flake check --no-build
```

Git Flake 不包含未跟踪文件。新文件尚未纳入 Git 时，可临时使用 `path:/absolute/path/to/flakes` 做本地求值；不要误把缺文件错误当作 Nix 模块错误。本仓库全量 checks 还包含所有主机和其他已有改动，单项套件检查与全量失败需分别判断。

用户完成 apply 和加密输出提取后，再构建三个节点并进行远端部署测试。部署顺序优先 fra0 的密钥/Redis/Tailscale/HTTPS，再部署边缘节点。在未经用户确认前不执行远端部署。

实机验收清单：

1. DNS 指向正确地址、证书链有效、主入口 `/healthz` 和 `/config.json` 可达。
2. 无凭据的 `/api/session` 返回 401，公开 JSON 没有 TURN secret、JWT 签名 secret 或加入凭据。
3. 各节点 SFU 服务正常，共同注册到私网 Redis；公网不能访问 Redis 和 5351。
4. 原生手机 MediaProjection 发布屏幕，网页可看并分别调节内录/麦克风音轨；实际 stats 验证编码与分辨率/帧率。
5. 分别测试 UDP 直连、强制 relay、封锁 UDP 的 TLS fallback、cu IPv6-only；用 WebRTC stats 确认实际 candidate pair，不凭服务器列表推断成功。
6. 模拟 TURN 节点退出和弱网，记录恢复时间与可见停顿，不声称无损热切换。
7. 手机端显式授权控制者 identity/session，测试乱序、丢失抬手、切后台、撤销授权后的 watchdog 释放；Root/Shizuku 注入需设备验证。

这些真实部署/浏览器/Android 验收必须在 DNS、秘密和节点启动后执行，本次源码与本地测试不能替代它们。
