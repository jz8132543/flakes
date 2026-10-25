# ─────────────────────────────────────────────────────────────────────────────
# services/ai/dify/containers.nix
#
# Dify OCI 容器定义（基于 rootless podman）
#
# 容器拓扑：
#   ┌─────────────────────────────────────────────────────┐
#   │  dify-api    (Dify Flask API + migrations)          │ :apiPort
#   │  dify-worker (Celery worker，共享 API 镜像)          │ 无对外端口
#   │  dify-web    (Next.js 前端)                          │ :webPort
#   │  dify-sandbox (代码沙箱执行器)                       │ :sandboxPort (仅内网)
#   └─────────────────────────────────────────────────────┘
#
# 所有容器使用 --network=host 以便访问：
#   • 宿主机原生 PG/Redis/Qdrant（loopback）
#   • ContextForge MCP 总线（loopback）
#   • CPA/NewAPI 网关（loopback）
#
# 启动顺序约束：
#   dify-db-init.service → podman-dify-{api,worker,web,sandbox}.service
# ─────────────────────────────────────────────────────────────────────────────
{
  config,
  lib,
  pkgs,
  difyConnVars,
  ...
}:
let
  cfg = config.services.ai.dify;

  inherit (difyConnVars)
    pgHost
    pgPort
    difyPgUser
    difyPgDb
    redisHost
    redisPort
    qdrantHost
    qdrantPort
    apiPort
    webPort
    sandboxPort
    ;

  # ── 共享环境变量（API 与 Worker 完全一致）─────────────────────────────
  commonApiEnv = {
    # ── 运行模式 ────────────────────────────────────────────────────────
    MODE = "api";
    LOG_LEVEL = "INFO";
    DEBUG = "false";
    FLASK_DEBUG = "false";

    # ── PostgreSQL ───────────────────────────────────────────────────
    DB_HOST = pgHost;
    DB_PORT = toString pgPort;
    DB_USERNAME = difyPgUser;
    DB_PASSWORD = ""; # 内网 trust，密码为空
    DB_DATABASE = difyPgDb;

    # ── Redis (Celery 消息队列 & 缓存) ──────────────────────────────
    REDIS_HOST = redisHost;
    REDIS_PORT = toString redisPort;
    REDIS_PASSWORD = "";
    REDIS_DB = "0";
    CELERY_BROKER_URL = "redis://${redisHost}:${toString redisPort}/1";
    BROKER_USE_SSL = "false";

    # ── 向量数据库：使用原生 Qdrant ──────────────────────────────────
    VECTOR_STORE = "qdrant";
    QDRANT_URL = "http://${qdrantHost}:${toString qdrantPort}";
    QDRANT_API_KEY = ""; # 内网无需认证
    QDRANT_CLIENT_TIMEOUT = "20";

    # ── 文件存储（本地卷，由 restic 备份）───────────────────────────
    STORAGE_TYPE = "local";
    STORAGE_LOCAL_PATH = "/app/api/storage";

    # ── 代码沙箱（API Key 由 sops-nix dify-secret.env 注入）───────
    CODE_EXECUTION_ENDPOINT = "http://${toString "127.0.0.1"}:${toString sandboxPort}";
    CODE_MAX_NUMBER = "9223372036854775807";
    CODE_MIN_NUMBER = "-9223372036854775808";

    # ── Dify 对外访问地址 ─────────────────────────────────────────────
    CONSOLE_WEB_URL = "https://${cfg.domain}";
    CONSOLE_API_URL = "https://${cfg.domain}";
    SERVICE_API_URL = "https://${cfg.domain}";
    APP_WEB_URL = "https://${cfg.domain}";

    # ── SSE / 流式响应：禁用响应缓冲 ────────────────────────────────
    # Traefik 已配置 3600s 超时，此处也禁用服务端缓冲
    HTTP_REQUEST_MAX_CONNECT_TIMEOUT = "10";
    HTTP_REQUEST_MAX_READ_TIMEOUT = "60";
    HTTP_REQUEST_MAX_WRITE_TIMEOUT = "20";

    # ── 邮件（可选，留空则禁用）─────────────────────────────────────
    MAIL_TYPE = "";
    MAIL_DEFAULT_SEND_FROM = "";

    # ── 统一大模型网关（NewAPI）──────────────────────────────────────
    # 配置 NewAPI 作为默认供应商
    OPENAI_API_BASE = "http://127.0.0.1:${toString config.ports.new-api}/v1";
    # 允许配置多个模型提供商（用户可以在 UI 中添加更多）
    MODEL_PROVIDER = "openai"; # 默认使用 OpenAI 兼容接口

    # ── Rerank 模型对接预留位 ─────────────────────────────────────────
    # 若 rerankApiBase 非空则注入；否则 Dify 内部会使用默认配置
    RERANK_API_URL = lib.optionalString (cfg.rerankApiBase != "") cfg.rerankApiBase;

    # ── Dify 内部插件守护程序（Plugin Daemon）────────────────────────
    PLUGIN_DAEMON_URL = "http://127.0.0.1:${toString config.ports.dify-plugin-daemon}";

    # ── 登录与认证（支持用户 i 密码登录 + Keycloak OIDC 单点登录）─────
    ENABLE_SOCIAL_OAUTH_LOGIN = "true";
    ENABLE_EMAIL_PASSWORD_LOGIN = "true";
    GITHUB_CLIENT_ID = "dify";

    # ── 安全 ─────────────────────────────────────────────────────────
    WEB_API_CORS_ALLOW_ORIGINS = "*";
    CONSOLE_CORS_ALLOW_ORIGINS = "*";
  };

  # ── Keycloak OIDC 桥接：通过挂载定制 oauth.py 让 Dify CE 原生支持 Keycloak SSO ──
  difyOauthPy = pkgs.writeText "dify-oauth.py" ''
    import base64
    import binascii
    import json
    import logging
    import urllib.parse
    from dataclasses import dataclass
    from typing import NotRequired, TypedDict, override

    import httpx
    from pydantic import TypeAdapter, ValidationError

    from core.helper.http_client_pooling import get_pooled_http_client

    logger = logging.getLogger(__name__)

    type JsonObject = dict[str, object]
    type JsonObjectList = list[JsonObject]

    JSON_OBJECT_ADAPTER: TypeAdapter[JsonObject] = TypeAdapter(JsonObject)
    JSON_OBJECT_LIST_ADAPTER: TypeAdapter[JsonObjectList] = TypeAdapter(JsonObjectList)

    _http_client: httpx.Client = get_pooled_http_client(
        "oauth:default",
        lambda: httpx.Client(limits=httpx.Limits(max_keepalive_connections=50, max_connections=100)),
    )


    class AccessTokenResponse(TypedDict, total=False):
        access_token: str


    class OAuthState(TypedDict, total=False):
        invite_token: str
        timezone: str
        language: str
        redirect_url: str


    class GitHubEmailRecord(TypedDict, total=False):
        email: str
        primary: bool
        verified: bool


    class GitHubRawUserInfo(TypedDict, total=False):
        id: int | str
        login: str
        name: NotRequired[str | None]
        email: NotRequired[str | None]
        preferred_username: NotRequired[str | None]
        sub: NotRequired[str | None]


    class GoogleRawUserInfo(TypedDict):
        sub: str
        email: str


    ACCESS_TOKEN_RESPONSE_ADAPTER = TypeAdapter(AccessTokenResponse)
    OAUTH_STATE_ADAPTER = TypeAdapter(OAuthState)
    GITHUB_RAW_USER_INFO_ADAPTER = TypeAdapter(dict)
    GITHUB_EMAIL_RECORDS_ADAPTER = TypeAdapter(list[GitHubEmailRecord])
    GOOGLE_RAW_USER_INFO_ADAPTER = TypeAdapter(GoogleRawUserInfo)


    @dataclass
    class OAuthUserInfo:
        id: str
        name: str
        email: str


    def encode_oauth_state(
        invite_token: str | None = None,
        timezone: str | None = None,
        language: str | None = None,
        redirect_url: str | None = None,
    ) -> str | None:
        state: OAuthState = {}
        if invite_token:
            state["invite_token"] = invite_token
        if timezone:
            state["timezone"] = timezone
        if language:
            state["language"] = language
        if redirect_url:
            state["redirect_url"] = redirect_url
        if not state:
            return None

        raw_state = json.dumps(state, separators=(",", ":")).encode("utf-8")
        return base64.urlsafe_b64encode(raw_state).decode("ascii").rstrip("=")


    def decode_oauth_state(state: str | None) -> OAuthState:
        if not state:
            return {}

        try:
            padded_state = state + "=" * (-len(state) % 4)
            raw_state = base64.urlsafe_b64decode(padded_state.encode("ascii")).decode("utf-8")
            return OAUTH_STATE_ADAPTER.validate_python(json.loads(raw_state))
        except (binascii.Error, ValueError, UnicodeDecodeError, json.JSONDecodeError, ValidationError):
            return {}


    def _json_object(response: httpx.Response) -> JsonObject:
        return JSON_OBJECT_ADAPTER.validate_python(response.json())


    def _json_list(response: httpx.Response) -> JsonObjectList:
        return JSON_OBJECT_LIST_ADAPTER.validate_python(response.json())


    class OAuth:
        client_id: str
        client_secret: str
        redirect_uri: str

        def __init__(self, client_id: str, client_secret: str, redirect_uri: str):
            self.client_id = client_id
            self.client_secret = client_secret
            self.redirect_uri = redirect_uri

        def get_authorization_url(
            self,
            invite_token: str | None = None,
            timezone: str | None = None,
            language: str | None = None,
            redirect_url: str | None = None,
        ) -> str:
            raise NotImplementedError()

        def get_access_token(self, code: str) -> str:
            raise NotImplementedError()

        def get_raw_user_info(self, token: str) -> JsonObject:
            raise NotImplementedError()

        def get_user_info(self, token: str) -> OAuthUserInfo:
            raw_info = self.get_raw_user_info(token)
            return self._transform_user_info(raw_info)

        def _transform_user_info(self, raw_info: JsonObject) -> OAuthUserInfo:
            raise NotImplementedError()


    class GitHubOAuth(OAuth):
        """
        Keycloak SSO Adapter for Dify CE:
        Redirects GitHub OAuth flow to Keycloak OIDC.
        """
        _AUTH_URL = "https://sso.${config.networking.domain}/realms/users/protocol/openid-connect/auth"
        _TOKEN_URL = "http://127.0.0.1:${toString config.ports.keycloak}/realms/users/protocol/openid-connect/token"
        _USER_INFO_URL = "http://127.0.0.1:${toString config.ports.keycloak}/realms/users/protocol/openid-connect/userinfo"

        @override
        def get_authorization_url(
            self,
            invite_token: str | None = None,
            timezone: str | None = None,
            language: str | None = None,
            redirect_url: str | None = None,
        ) -> str:
            params = {
                "client_id": self.client_id,
                "redirect_uri": self.redirect_uri,
                "response_type": "code",
                "scope": "openid profile email",
            }
            state = encode_oauth_state(
                invite_token=invite_token,
                timezone=timezone,
                language=language,
                redirect_url=redirect_url,
            )
            if state:
                params["state"] = state
            return f"{self._AUTH_URL}?{urllib.parse.urlencode(params)}"

        @override
        def get_access_token(self, code: str) -> str:
            data = {
                "client_id": self.client_id,
                "client_secret": self.client_secret,
                "code": code,
                "grant_type": "authorization_code",
                "redirect_uri": self.redirect_uri,
            }
            headers = {"Accept": "application/json"}
            response = _http_client.post(self._TOKEN_URL, data=data, headers=headers)

            response_json = ACCESS_TOKEN_RESPONSE_ADAPTER.validate_python(_json_object(response))
            access_token = response_json.get("access_token")

            if not access_token:
                raise ValueError(f"Error in GitHub OAuth: {response_json}")

            return access_token

        @override
        def get_raw_user_info(self, token: str) -> JsonObject:
            headers = {"Authorization": f"Bearer {token}"}
            response = _http_client.get(self._USER_INFO_URL, headers=headers)
            response.raise_for_status()
            return _json_object(response)

        @override
        def _transform_user_info(self, raw_info: JsonObject) -> OAuthUserInfo:
            sub = str(raw_info.get("sub") or raw_info.get("id") or "")
            username = str(raw_info.get("preferred_username") or raw_info.get("name") or sub)
            email = str(raw_info.get("email") or f"{username}@${config.networking.domain}")
            return OAuthUserInfo(id=sub, name=username, email=email)


    class GoogleOAuth(OAuth):
        _AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
        _TOKEN_URL = "https://oauth2.googleapis.com/token"
        _USER_INFO_URL = "https://www.googleapis.com/oauth2/v3/userinfo"

        @override
        def get_authorization_url(
            self,
            invite_token: str | None = None,
            timezone: str | None = None,
            language: str | None = None,
            redirect_url: str | None = None,
        ) -> str:
            params = {
                "client_id": self.client_id,
                "response_type": "code",
                "redirect_uri": self.redirect_uri,
                "scope": "openid email",
            }
            state = encode_oauth_state(
                invite_token=invite_token,
                timezone=timezone,
                language=language,
                redirect_url=redirect_url,
            )
            if state:
                params["state"] = state
            return f"{self._AUTH_URL}?{urllib.parse.urlencode(params)}"

        @override
        def get_access_token(self, code: str) -> str:
            data = {
                "client_id": self.client_id,
                "client_secret": self.client_secret,
                "code": code,
                "grant_type": "authorization_code",
                "redirect_uri": self.redirect_uri,
            }
            headers = {"Accept": "application/json"}
            response = _http_client.post(self._TOKEN_URL, data=data, headers=headers)

            response_json = ACCESS_TOKEN_RESPONSE_ADAPTER.validate_python(_json_object(response))
            access_token = response_json.get("access_token")

            if not access_token:
                raise ValueError(f"Error in Google OAuth: {response_json}")

            return access_token

        @override
        def get_raw_user_info(self, token: str) -> JsonObject:
            headers = {"Authorization": f"Bearer {token}"}
            response = _http_client.get(self._USER_INFO_URL, headers=headers)
            response.raise_for_status()
            return _json_object(response)

        @override
        def _transform_user_info(self, raw_info: JsonObject) -> OAuthUserInfo:
            payload = GOOGLE_RAW_USER_INFO_ADAPTER.validate_python(raw_info)
            return OAuthUserInfo(id=str(payload["sub"]), name="", email=payload["email"])
  '';

  # ── 统一 systemd 依赖声明（所有容器共用）────────────────────────────
  mkContainerDeps = extraAfter: {
    after = [
      "dify-db-init.service"
      "redis-dify.service" # services.redis.servers."dify" 生成的 unit 名
      "qdrant.service" # 原生 NixOS services.qdrant
      "sops-install-secrets.service"
    ]
    ++ extraAfter;
    requires = [
      "dify-db-init.service"
      "redis-dify.service"
      "qdrant.service" # 原生 NixOS services.qdrant
    ];
    wantedBy = [ "multi-user.target" ];
  };
in
{
  # ────────────────────────────────────────────────────────────────────
  # OCI 容器定义
  # ────────────────────────────────────────────────────────────────────
  virtualisation.oci-containers.containers = {

    # ── dify-api ────────────────────────────────────────────────────
    dify-api = {
      image = cfg.image.api;
      autoStart = true;
      extraOptions = [
        "--network=host"
      ];
      environment = commonApiEnv // {
        MODE = "api";
        MIGRATION_ENABLED = "true";
        PORT = toString apiPort;
        DIFY_PORT = toString apiPort;
        DIFY_BIND_ADDRESS = "0.0.0.0";
        SERVER_WORKER_AMOUNT = "2"; # 6核机器，API 给 2 个 worker
        SERVER_WORKER_CLASS = "gevent";
        GUNICORN_TIMEOUT = "3600"; # 超过 3600s 的 SSE 由 Traefik 层维持
      };
      environmentFiles = [
        config.sops.templates."dify-secret.env".path
      ];
      volumes = [
        "${cfg.dataDir}/storage:/app/api/storage"
        "${difyOauthPy}:/app/api/libs/oauth.py:ro"
      ];
    };

    # ── dify-worker ─────────────────────────────────────────────────
    # Celery 异步任务处理（文档解析、向量化、工作流执行）
    dify-worker = {
      image = cfg.image.api; # 与 API 共享同一镜像，仅 MODE 不同
      autoStart = true;
      extraOptions = [
        "--network=host"
      ];
      environment = commonApiEnv // {
        MODE = "worker";
        # Celery 并发度：6核机器保留 2 核给 PG/系统
        CELERY_WORKER_AMOUNT = "4";
        CELERY_AUTO_SCALE = "true";
        CELERY_MAX_WORKERS = "4";
        CELERY_MIN_WORKERS = "1";
      };
      environmentFiles = [
        config.sops.templates."dify-secret.env".path
      ];
      volumes = [
        "${cfg.dataDir}/storage:/app/api/storage"
        "${difyOauthPy}:/app/api/libs/oauth.py:ro"
      ];
    };

    # ── dify-web ─────────────────────────────────────────────────────
    # Next.js 前端（SSR，直接访问 API 服务）
    dify-web = {
      image = cfg.image.web;
      autoStart = true;
      extraOptions = [
        "--network=host"
      ];
      environment = {
        PORT = toString webPort;
        HOSTNAME = "0.0.0.0";
        CONSOLE_API_URL = "https://${cfg.domain}";
        APP_API_URL = "https://${cfg.domain}";
        CONSOLE_WEB_URL = "https://${cfg.domain}";
        SERVER_CONSOLE_API_URL = "http://127.0.0.1:${toString apiPort}";
        # SSE 流式传输：禁用 Next.js 响应缓冲
        NEXT_TELEMETRY_DISABLED = "1";
      };
    };

    # ── dify-sandbox ─────────────────────────────────────────────────
    # 代码执行沙箱（gVisor/seccomp 隔离）
    dify-sandbox = {
      image = cfg.image.sandbox;
      autoStart = true;
      extraOptions = [
        "--network=host"
        "--security-opt=seccomp=unconfined" # sandbox 内部自行管理 seccomp
      ];
      environment = {
        GIN_MODE = "release";
        WORKER_TIMEOUT = "15";
        ENABLE_NETWORK = "true";
        HTTP_PROXY = "";
        HTTPS_PROXY = "";
        SANDBOX_PORT = toString sandboxPort;
      };
      environmentFiles = [
        config.sops.templates."dify-sandbox-secret.env".path
      ];
    };

    dify-plugin-daemon = {
      image = cfg.image.pluginDaemon;
      autoStart = true;
      extraOptions = [
        "--network=host"
      ];
      environment = {
        SERVER_PORT = toString config.ports.dify-plugin-daemon;
        SERVER_HOST = "0.0.0.0";
        SERVER_KEY = "plugin-api-key";
        DB_HOST = pgHost;
        DB_PORT = toString pgPort;
        DB_USERNAME = difyPgUser;
        DB_PASSWORD = "dify";
        DB_DATABASE = "dify_plugin";
        DB_DEFAULT_DATABASE = "postgres";
        REDIS_HOST = redisHost;
        REDIS_PORT = toString redisPort;
        REDIS_DB = "0";
        DIFY_INNER_API_URL = "http://127.0.0.1:${toString apiPort}";
        DIFY_INNER_API_KEY = "inner-api-key";
        PLUGIN_REMOTE_INSTALLING_HOST = "0.0.0.0";
        PLUGIN_REMOTE_INSTALLING_PORT = toString config.ports.dify-plugin-debug;
        PLUGIN_STORAGE_TYPE = "local";
        PLUGIN_STORAGE_LOCAL_ROOT = "/app/storage";
        PLUGIN_WORKING_PATH = "/app/storage/cwd";
        PLUGIN_INSTALLED_PATH = "plugin";
        PLUGIN_PACKAGE_CACHE_PATH = "plugin_packages";
        PLUGIN_MEDIA_CACHE_PATH = "assets";
      };
      volumes = [
        "${cfg.dataDir}/plugin_daemon:/app/storage"
      ];
    };
  };

  # ── Systemd 依赖拓扑注入 ─────────────────────────────────────────────
  systemd.services = {
    podman-dify-api = mkContainerDeps [
      "podman-dify-sandbox.service"
      "podman-dify-plugin-daemon.service"
    ];
    podman-dify-worker = mkContainerDeps [ "podman-dify-api.service" ];
    podman-dify-web = mkContainerDeps [ "podman-dify-api.service" ];
    podman-dify-plugin-daemon = mkContainerDeps [ ];
    podman-dify-sandbox = {
      after = [
        "network-online.target"
        "sops-install-secrets.service"
      ];
      wants = [ "sops-install-secrets.service" ];
      wantedBy = [ "multi-user.target" ];
    };
  };
}
