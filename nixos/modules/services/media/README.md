# Home Theater System - 家庭影院系统

基于 NixOS 的全自动化家庭影院系统，开箱即用。

## 🎬 包含服务

| 服务             | 用途            | URL                      |
| ---------------- | --------------- | ------------------------ |
| **Jellyfin**     | 媒体服务器      | https://jellyfin.dora.im |
| **Jellyseerr**   | 请求管理        | https://seerr.dora.im    |
| **Sonarr**       | 电视剧管理      | https://sonarr.dora.im   |
| **Radarr**       | 电影管理        | https://radarr.dora.im   |
| **Prowlarr**     | 索引器管理      | https://prowlarr.dora.im |
| **Bazarr**       | 字幕管理        | https://bazarr.dora.im   |
| **qBittorrent**  | 下载客户端      | https://qbit.dora.im     |
| **FlareSolverr** | Cloudflare 绕过 | (内部服务)               |

## 🔐 统一凭证

所有服务使用相同的凭证：

- **用户名**: `i`
- **密码**: 从 sops secret `password` 读取
- **邮箱**: `noreply@dora.im`
- **SMTP 密码**: 从 sops secret `smtp/password` 读取

## 📁 目录结构

```
/srv/media/
├── movies/          # 电影库 (Radarr)
├── tv/              # 电视剧库 (Sonarr)
└── music/           # 音乐库

/srv/torrents/
├── downloading/     # 下载中
├── completed/       # 已完成
├── tv-sonarr/       # Sonarr 专用
├── movies-radarr/   # Radarr 专用
└── prowlarr/        # Prowlarr 专用
```

## 🚀 快速开始

### 1. 配置 Secrets

编辑 `secrets/common.yaml` 添加必要的密钥：

```yaml
# 主密码 (所有服务共用)
password: your-secure-password

# SMTP 配置 (用于邮件通知)
smtp:
  password: your-smtp-password

# 媒体服务 API 密钥 (首次运行自动生成)
media:
  sonarr_api_key: <32位十六进制>
  radarr_api_key: <32位十六进制>
  prowlarr_api_key: <32位十六进制>
```

### 2. 部署 NixOS 配置

```bash
# 部署到媒体服务器 (nue0)
colmena apply --on nue0

# 或者使用 deploy-rs
deploy .#nue0
```

### 3. 应用 Terraform 配置

```bash
cd terraform
terraform init
terraform apply
```

### 4. 完成手动配置

以下步骤只需在首次部署时执行一次：

#### Jellyseerr 设置向导

1. 访问 https://seerr.dora.im
2. 选择 "Use your Jellyfin account"
3. 输入 Jellyfin URL: `http://localhost:8096`
4. 使用用户名 `i` 和配置的密码登录
5. 配置 Sonarr 和 Radarr 连接

#### Prowlarr 添加索引器

1. 访问 https://prowlarr.dora.im
2. 进入 Indexers 页面
3. 添加你的 torrent 站点索引器

#### Jellyfin 添加媒体库

1. 访问 https://jellyfin.dora.im
2. 进入 Dashboard > Libraries
3. 添加 Movies 库: `/srv/media/movies`
4. 添加 TV Shows 库: `/srv/media/tv`

## 📊 自动化说明

### NixOS 自动配置 (首次启动)

- ✅ Jellyfin - 创建初始用户、语言设置
- ✅ qBittorrent - 设置凭证、下载分类、保存路径
- ✅ Sonarr - 根目录、认证配置
- ✅ Radarr - 根目录、认证配置
- ✅ Prowlarr - 认证配置
- ✅ Bazarr - 连接 Sonarr/Radarr、语言设置

### Terraform 自动化配置

- ✅ Sonarr - 命名规则 (TRaSH Guides)、下载客户端、邮件通知
- ✅ Radarr - 命名规则、下载客户端、邮件通知
- ✅ Prowlarr - FlareSolverr 代理、应用同步 (Sonarr/Radarr)

## 🔧 配置文件

### NixOS 模块

```
nixos/modules/services/media/
├── default.nix              # 入口模块
├── home-theater.nix         # 主配置和目录结构
├── jellyfin.nix             # Jellyfin 服务
├── jellyfin-auto-config.nix # Jellyfin 自动配置
├── sonarr.nix               # Sonarr 服务
├── sonarr-auto-config.nix   # Sonarr 自动配置
├── radarr.nix               # Radarr 服务
├── radarr-auto-config.nix   # Radarr 自动配置
├── prowlarr.nix             # Prowlarr 服务
├── prowlarr-auto-config.nix # Prowlarr 自动配置
├── bazarr.nix               # Bazarr 服务
├── bazarr-auto-config.nix   # Bazarr 自动配置
├── jellyseerr.nix           # Jellyseerr 服务
├── jellyseerr-auto-config.nix # Jellyseerr 设置说明
├── qbittorrent.nix          # qBittorrent 服务
├── qbittorrent-auto-config.nix # qBittorrent 自动配置
└── flaresolverr.nix         # FlareSolverr 服务
```

### Terraform 文件

```
terraform/
├── providers.tf    # Terraform providers (包括 devopsarr)
├── media.tf        # 媒体栈自动化配置
├── password.tf     # 密码生成资源
└── secrets.tf      # Sops secrets 访问
```

## 🔄 工作流程

```
用户请求 (Jellyseerr)
    ↓
Sonarr/Radarr 搜索
    ↓
Prowlarr 索引器查询
    ↓
qBittorrent 下载
    ↓
Sonarr/Radarr 导入整理
    ↓
Bazarr 下载字幕
    ↓
Jellyfin 提供播放
```

## 🔒 安全性

- 所有服务通过 Traefik 反向代理，使用 HTTPS
- 服务间通信使用内部网络 (127.0.0.1)
- 认证使用 sops 加密存储的密码
- 所有服务启用表单认证

## 📝 维护命令

```bash
# 查看服务状态
systemctl status jellyfin sonarr radarr prowlarr bazarr jellyseerr qbittorrent

# 查看自动配置日志
journalctl -u jellyfin-auto-config
journalctl -u qbittorrent-auto-config
journalctl -u sonarr-auto-config

# 重新运行自动配置 (删除标记文件后)
rm /var/lib/jellyfin/.auto-configured
systemctl restart jellyfin-auto-config

# 查看 Terraform 状态
cd terraform && terraform show
```

## 🐛 故障排除

### 服务无法启动

```bash
# 检查服务日志
journalctl -u SERVICE_NAME -f

# 检查端口占用
ss -tlnp | grep PORT
```

### API 认证失败

1. 确认 `secrets/common.yaml` 中的 API key 正确
2. 检查服务的 `config.xml` 中的 API key 是否匹配
3. 重启服务：`systemctl restart SERVICE_NAME`

### Terraform apply 失败

1. 确保服务正在运行
2. 确保可以通过 URL 访问服务
3. 检查 API key 是否正确
