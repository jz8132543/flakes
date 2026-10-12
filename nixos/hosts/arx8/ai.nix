{
  config,
  pkgs,
  lib,
  ...
}:
let
  # ── 1. 路径变量统一管理 ───────────────────────────────────────────────
  aiModelsDir = "/mnt/games/AI"; # 静态 GGUF 模型存放根目录
  hfCacheDir = "${aiModelsDir}/huggingface"; # 自动下载时的 HF 缓存目录

  # ── 2. llama.cpp 构建与底层参数函数 (针对 7945HX + RTX4060) ────────
  llama-cpp = pkgs.llama-cpp.override { cudaSupport = true; };
  llama-server = lib.getExe' llama-cpp "llama-server";

  mkLlamaCmd =
    {
      repo,
      file,
      ngl,
      ctx,
      extra ? "",
    }:
    ''
      ${llama-server} \
        --port ''${PORT} --host 127.0.0.1 \
        --hf-repo ${repo} --hf-file${file} \
        --n-gpu-layers ${toString ngl} \
        --ctx-size ${toString ctx} \
        --threads 8 \
        --threads-batch 16 \
        --batch-size 1024 \
        --ubatch-size 512 \
        --flash-attn \
        ${extra}
    '';
in
{
  # ==========================================
  # 1. SOPS 密钥与 Open WebUI 环境变量
  # ==========================================
  sops.secrets = {
    "openai_api_key" = { };
    "open-webui/secret_key" = { };
  };

  sops.templates."open-webui.env" = {
    mode = "0444";
    content = ''
      OPENAI_API_KEY=''${config.sops.placeholder."openai_api_key"}
      WEBUI_SECRET_KEY=''${config.sops.placeholder."open-webui/secret_key"}
    '';
  };

  users.users.llama-swap = {
    isSystemUser = true;
    group = "llama-swap";
    # 极为关键：赋予该后台服务调用 Nvidia 显卡的硬件权限
    extraGroups = [
      "video"
      "render"
    ];
  };
  users.groups.llama-swap = { };

  # ==========================================
  # 2. 部署 Open WebUI 前端服务
  # ==========================================
  services.open-webui = {
    enable = true;
    port = 8081; # 错开 llama-swap 的 8080 端口
    environmentFile = config.sops.templates."open-webui.env".path;

    environment = {
      # 强制走 OpenAI API 协议直连 llama-swap 代理网关
      ENABLE_OLLAMA_API = "False";
      OPENAI_API_BASE_URL = "http://127.0.0.1:8080/v1";

      # 关闭遥测
      ANONYMIZED_TELEMETRY = "False";
      DO_NOT_TRACK = "True";
      SCARF_NO_ANALYTICS = "True";
    };
  };

  # ==========================================
  # 3. 部署 llama-swap 模型动态路由 (替代原原生 llama-cpp)
  # ==========================================
  services.llama-swap = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 8080; # 统一对外的网关端口

    settings = {
      globalTTL = 600;
      healthCheckTimeout = 300; # 留足时间给模型冷启动下载或加载

      # 开启互斥：切换模型时，旧模型会被杀掉，彻底释放 48G 内存
      routing.router.settings.groups.single = {
        swap = true;
        exclusive = true;
        members = [
          "qwen-coder-7b-uncensored"
          "qwen-27b-abliterated"
          "r1-32b-abliterated"
          "r1-70b-abliterated"
        ];
      };

      # 你的无限制/特征抹除版模型舰队
      models = {
        "qwen-coder-7b-uncensored" = {
          name = "Qwen 2.5 Coder 7B Uncensored";
          cmd = mkLlamaCmd {
            repo = "mradermacher/Qwen2.5-Coder-7B-Instruct-Uncensored-GGUF";
            file = "Qwen2.5-Coder-7B-Instruct-Uncensored.Q4_K_M.gguf";
            ngl = 99;
            ctx = 16384;
            extra = "--cache-type-k q8_0 --cache-type-v q8_0";
          };
        };
        "qwen-27b-abliterated" = {
          name = "Qwen 3.8 27B Abliterated";
          cmd = mkLlamaCmd {
            repo = "huihui-ai/Huihui-Qwen3.8-27B-abliterated-GGUF";
            file = "Huihui-Qwen3.8-27B-abliterated-UD-Q4_K_XL.gguf";
            ngl = 14;
            ctx = 32768;
            extra = "--cache-type-k q4_0 --cache-type-v q4_0 --spec-type draft-mtp --spec-draft-n-max 2";
          };
        };
        "r1-32b-abliterated" = {
          name = "DeepSeek R1 Distill 32B Abliterated";
          cmd = mkLlamaCmd {
            repo = "tensorblock/DeepSeek-R1-Distill-Qwen-32B-abliterated-GGUF";
            file = "DeepSeek-R1-Distill-Qwen-32B-abliterated-Q4_K_M.gguf";
            ngl = 12;
            ctx = 32768;
            extra = "--cache-type-k q4_0 --cache-type-v q4_0";
          };
        };
        "r1-70b-abliterated" = {
          name = "DeepSeek R1 Distill 70B Abliterated";
          cmd = mkLlamaCmd {
            repo = "mradermacher/DeepSeek-R1-Distill-Llama-70B-abliterated-i1-GGUF";
            file = "DeepSeek-R1-Distill-Llama-70B-abliterated-i1-IQ2_XS.gguf";
            ngl = 6;
            ctx = 16384;
            extra = "--cache-type-k q4_0 --cache-type-v q4_0";
          };
        };
      };
    };
  };

  # 【关键安全与沙箱配置】授予 llama-swap 下载模型和读取本地模型的权限
  systemd.services.llama-swap = {
    # 确保缓存目录存在
    serviceConfig = {
      User = "llama-swap";
      Group = "llama-swap";

      # 强制关闭 DynamicUser，避免它自动生成限制设备访问的隔离环境
      DynamicUser = lib.mkForce false;
      PrivateDevices = lib.mkForce false; # 确保能读到 /dev/nvidia0

      # 保留文件系统的读写挂载
      ReadWritePaths = [ hfCacheDir ];
      ReadOnlyPaths = [ aiModelsDir ];
    };
    environment = {
      HF_HOME = hfCacheDir;
      HF_HUB_CACHE = hfCacheDir;
      LLAMA_CACHE = lib.mkForce "${aiModelsDir}/.cache";
    };
  };

  # ==========================================
  # 4. 全局环境变量与终端辅助工具
  # ==========================================
  # environment.sessionVariables = {
  #   LLAMA_CACHE = "${aiModelsDir}/.cache";
  #   HF_HOME = hfCacheDir;
  # };
  environment.variables = {
    HF_HOME = hfCacheDir;
    HF_HUB_CACHE = hfCacheDir;
  };

  environment.systemPackages = [
    # 方便在终端中随时调用支持 CUDA 的 llama-cli 测试
    (pkgs.llama-cpp.override { cudaSupport = true; })

    # 优化后的 Hugging Face 下载快捷脚本
    (pkgs.writeShellScriptBin "hf-dl" ''
      #!/usr/bin/env bash
      # 用法示例: hf-dl huihui-ai/Huihui-Qwen3.8-27B-abliterated-GGUF Huihui-Qwen3.8-27B-abliterated-UD-Q4_K_XL.gguf
      export HF_ENDPOINT="https://hf-mirror.com"
      exec ${pkgs.python3Packages.huggingface-hub}/bin/huggingface-cli download \
        --local-dir ${aiModelsDir} \
        --local-dir-use-symlinks False \
        "$@"
    '')
  ];

  # ==========================================
  # 5. Traefik 反向代理配置
  # ==========================================
  services.traefik.proxies.open-webui = {
    rule = "HostRegexp(`{host:.+}`)";
    target = "http://127.0.0.1:${toString config.services.open-webui.port}";
  };
  systemd.tmpfiles.rules = [
    # 格式：类型 | 路径 | 权限 | 属主 | 属组 | 寿命
    # 使用 "-" 代表忽略该项，让它继承父目录或系统默认值
    "d /mnt/games/AI - - - -"
    "d /mnt/games/AI/huggingface - - - -"
    "d /mnt/games/AI/.cache - - - -"
  ];
}
