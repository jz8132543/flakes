{
  config,
  pkgs,
  lib,
  ...
}:
let
  aiModelsDir = "/mnt/games/AI";
  hfCacheDir = "${aiModelsDir}/.cache/huggingface";

  llama-cpp = pkgs.llama-cpp.override { cudaSupport = true; };
  llama-server = lib.getExe' llama-cpp "llama-server";

  # 严格复刻 xddxdd 的 CUDA 设备绑定包装器
  useCudaDevice = id: "env CUDA_DEVICE_ORDER=PCI_BUS_ID CUDA_VISIBLE_DEVICES=${builtins.toString id}";

  # 按照 xddxdd 的风格定义的文本生成模型命令模板
  mkTextGen = repo: file: _quant: ctx: ngl: extra: ''
    ${useCudaDevice 0} ${llama-server} \
    --port ''${PORT} --host 127.0.0.1 \
    --hf-repo ${repo} \
    --hf-file ${file} \
    --n-gpu-layers ${toString ngl} \
    --ctx-size ${toString ctx} \
    --threads 8 \
    --threads-batch 16 \
    --batch-size 1024 \
    --ubatch-size 512 \
    --flash-attn on \
    ${extra}
  '';

  models = {
    # keep-sorted start block=yes
    "deepseek-r1-32b-abliterated" = {
      name = "DeepSeek R1 Distill 32B Abliterated";
      cmd =
        mkTextGen "tensorblock/DeepSeek-R1-Distill-Qwen-32B-abliterated-GGUF"
          "DeepSeek-R1-Distill-Qwen-32B-abliterated-Q4_K_M.gguf"
          "Q4_K_M"
          32768
          12
          "--cache-type-k q4_0 --cache-type-v q4_0";
    };
    "deepseek-r1-70b-abliterated" = {
      name = "DeepSeek R1 Distill 70B Abliterated";
      cmd =
        mkTextGen "mradermacher/DeepSeek-R1-Distill-Llama-70B-abliterated-i1-GGUF"
          "DeepSeek-R1-Distill-Llama-70B-abliterated-i1-IQ2_XS.gguf"
          "IQ2_XS"
          16384
          6
          "--cache-type-k q4_0 --cache-type-v q4_0";
    };
    "qwen-38-27b-abliterated" = {
      name = "Qwen 3.8 27B Abliterated";
      cmd =
        mkTextGen "huihui-ai/Huihui-Qwen3.8-27B-abliterated-GGUF"
          "Huihui-Qwen3.8-27B-abliterated-UD-Q4_K_XL.gguf"
          "Q4_K_XL"
          32768
          14
          "--cache-type-k q4_0 --cache-type-v q4_0 --spec-type draft-mtp --spec-draft-n-max 2";
    };
    "qwen-coder-7b-uncensored" = {
      name = "Qwen 2.5 Coder 7B Uncensored";
      cmd =
        mkTextGen "mradermacher/Qwen2.5-Coder-7B-Instruct-Uncensored-GGUF"
          "Qwen2.5-Coder-7B-Instruct-Uncensored.Q4_K_M.gguf"
          "Q4_K_M"
          16384
          99
          "--cache-type-k q8_0 --cache-type-v q8_0";
    };
    # keep-sorted end
  };
in
{
  # ==========================================
  # Open WebUI (保持不变)
  # ==========================================
  sops.secrets."openai_api_key" = { };
  sops.secrets."open-webui/secret_key" = { };

  sops.templates."open-webui.env" = {
    mode = "0444";
    content = ''
      OPENAI_API_KEY=''${config.sops.placeholder."openai_api_key"}
      WEBUI_SECRET_KEY=''${config.sops.placeholder."open-webui/secret_key"}
    '';
  };

  services.open-webui = {
    enable = true;
    port = 8081;
    environmentFile = config.sops.templates."open-webui.env".path;
    environment = {
      ENABLE_OLLAMA_API = "False";
      OPENAI_API_BASE_URL = "http://127.0.0.1:8080/v1";
      ANONYMIZED_TELEMETRY = "False";
      DO_NOT_TRACK = "True";
      SCARF_NO_ANALYTICS = "True";
    };
  };

  services.traefik.proxies.open-webui = {
    rule = "HostRegexp(`{host:.+}`)";
    target = "http://127.0.0.1:${toString config.services.open-webui.port}";
  };

  # ==========================================
  # Llama Swap 配置 (严格遵循 xddxdd 风格)
  # ==========================================
  services.llama-swap = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 8080;

    settings = {
      globalTTL = 600;
      healthCheckTimeout = 7200; # 依然保留超长超时，以防网络龟速导致崩溃
      inherit models;
      routing.router.settings.groups.single = {
        swap = true;
        exclusive = true;
        members = builtins.attrNames models;
      };
    };
  };

  # ==========================================
  # 用户、权限与环境变量注入
  # ==========================================
  systemd.services.llama-swap.serviceConfig = {
    User = "llama-swap";
    Group = "llama-swap";
    DynamicUser = lib.mkForce false;
    PrivateUsers = lib.mkForce false;
    # 开放指定目录的沙箱权限
    ReadWritePaths = [
      aiModelsDir
      hfCacheDir
    ];
  };

  users.users.llama-swap = {
    group = "llama-swap";
    isSystemUser = true;
    extraGroups = [
      "video"
      "render"
    ]; # 必须保留，否则报错 exited prematurely
  };
  users.groups.llama-swap = { };

  # 将下载路径强制指向游戏盘
  systemd.services.llama-swap.environment = {
    HF_HOME = lib.mkForce hfCacheDir;
    HF_HUB_CACHE = lib.mkForce hfCacheDir;
    LLAMA_CACHE = lib.mkForce aiModelsDir;
  };

  environment.sessionVariables = {
    LLAMA_CACHE = aiModelsDir;
    HF_HOME = hfCacheDir;
  };
  environment.variables = {
    HF_HOME = hfCacheDir;
    HF_HUB_CACHE = hfCacheDir;
  };

  environment.systemPackages = [
    (pkgs.llama-cpp.override { cudaSupport = true; })
  ];

  # 确保外置硬盘的缓存目录存在
  systemd.tmpfiles.rules = [
    "d ${aiModelsDir} 0777 - - -"
    "d ${hfCacheDir} 0777 - - -"
    # "d ${aiModelsDir}/.cache 0750 llama-swap llama-swap -"
  ];
}
