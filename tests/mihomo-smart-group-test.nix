{ lib }:
let
  # Capture the YAML value without building it or reading any secrets.
  mkSubscription =
    publisher:
    (import ../nixos/modules/services/sub.nix {
      inherit lib;
      config = {
        networking.domain = "example.test";
        ports.ssh = 1022;
        users.users.mihomo.uid = 998;
        services = {
          mihomo = {
            enable = true;
            routing.proxyPublicSsh = false;
          };
          dn42 = {
            enable = true;
            ikePort = 500;
            natTPort = 4500;
            allClusterTunnelPorts = [
              500
              4500
            ];
          };
          # 以独立模块方式导入时不经过模块系统，选项默认值不会自动生效，
          # 因此在此提供 sub.nix 中被引用的默认值；调用方的取值优先。
          subscriptionPublisher = {
            enable = true;
            healthCheckUrl = "https://www.gstatic.com/generate_204";
            smartGroupType = "url-test";
            smartLearning = {
              enable = true;
              collectorSize = 100;
              preferASN = true;
              useLightGBM = true;
              collectData = false;
            };
            serverName = "example.test";
            transport = "xhttp";
            xhttpPath = "/speedtest";
            xhttpMode = "stream-one";
            xhttpExtra = {
              xPaddingBytes = "100-1000";
              xPaddingObfsMode = true;
              xPaddingPlacement = "header";
              xPaddingHeader = "X-Padding";
              xPaddingMethod = "repeat-x";
            };
            xhttpXmux = {
              maxConnections = "3-3";
              hMaxRequestTimes = "600-900";
              hMaxReusableSecs = "1800-3000";
              hKeepAlivePeriod = 45;
            };
            xhttpUplinkChunkSize = "524288-1048576";
            xhttpScMaxEachPostBytes = "524288-1048576";
            xhttpScMinPostsIntervalMs = "10-30";
          }
          // publisher;
        };
      };
      pkgs.formats.yaml = _: { generate = _: value: value; };
    }).config.content;

  nodes = [
    {
      name = "fra0";
      server = "fra0";
      port = 8555;
      regions = [ "EU" ];
      type = "vless";
      smartFactor = null;
    }
    {
      name = "sjc0";
      server = "sjc0";
      port = 8555;
      regions = [ "US" ];
      type = "vless";
      smartFactor = 1.2;
    }
    {
      name = "hkg5";
      server = "hkg5";
      port = 8555;
      regions = [ "HK" ];
      type = "vless";
      smartFactor = 0.8;
    }
    {
      name = "tyo0";
      server = "tyo0";
      port = 8555;
      regions = [ "JP" ];
      type = "vless";
      # 故意使用会被内核拒绝的值，用于验证断言不会静默放过。
      smartFactor = 0;
    }
  ];

  # 主文档：必须保持上游 mihomo 可解析，因此区域组恒为 url-test。
  mainGroups = document: document.sops.templates."subscription/mihomo.yaml".file.proxy-groups;
  # smart 文档：由 smartGroupType 决定是否把 url-test 组升级为 smart。
  smartGroups = document: document.sops.templates."subscription/mihomo-smart.yaml".file.proxy-groups;
  byMainName = document: name: lib.lists.findFirst (g: g.name == name) null (mainGroups document);
  bySmartName = document: name: lib.lists.findFirst (g: g.name == name) null (smartGroups document);

  urlTest = mkSubscription {
    inherit nodes;
    groups = [ ];
  };

  smart = mkSubscription {
    inherit nodes;
    smartGroupType = "smart";
    groups = [ ];
  };

  # 用户自定义组也可以单独启用 smart。
  smartUserGroup = mkSubscription {
    inherit nodes;
    groups = [
      {
        name = "UNLOCK";
        type = "smart";
        nodes = [
          "fra0"
          "sjc0"
        ];
        proxies = [ ];
        url = "https://www.gstatic.com/generate_204";
        interval = 300;
        tolerance = 50;
        groups = [ ];
        expandGroups = false;
      }
    ];
  };

  urlTestUserGroup = mkSubscription {
    inherit nodes;
    groups = [
      {
        name = "UNLOCK";
        nodes = [
          "fra0"
          "sjc0"
        ];
        proxies = [ ];
        type = "url-test";
        url = "https://www.gstatic.com/generate_204";
        interval = 300;
        tolerance = 50;
        groups = [ ];
        expandGroups = false;
      }
    ];
  };
in
{
  # 主文档必须保持上游 mihomo 可解析：区域组恒为 url-test，
  # 且不出现任何 smart 专属键，否则普通内核会拒绝启动。
  mainDocumentStaysUpstreamCompatible = {
    expected = [
      "url-test"
      "url-test"
      "url-test"
      "url-test"
    ];
    result = map (g: g.type) (
      lib.filter (
        g:
        lib.elem g.name [
          "US"
          "HK"
          "JP"
          "EU"
        ]
      ) (mainGroups urlTest)
    );
  };

  mainDocumentHasNoSmartKeys = {
    expected = [ ];
    result = lib.lists.filter (
      g: g ? policy-priority || g ? prefer-asn || g ? uselightgbm || g.type == "smart"
    ) (mainGroups urlTest);
  };

  # smart 文档：smartGroupType = "smart" 时区域组升级为 smart。
  smartDocumentUpgradesRegionGroups = {
    expected = [
      true
      true
      true
      true
    ];
    result = map (g: g.type == "smart" && g ? prefer-asn && g ? uselightgbm) (
      lib.filter (
        g:
        lib.elem g.name [
          "US"
          "HK"
          "JP"
          "EU"
        ]
      ) (smartGroups smart)
    );
  };

  # smart 文档在 smartGroupType = "url-test" 时不升级，保持与主文档一致。
  smartDocumentRespectsUrlTest = {
    expected = [
      "url-test"
      "url-test"
      "url-test"
      "url-test"
    ];
    result = map (g: g.type) (
      lib.filter (
        g:
        lib.elem g.name [
          "US"
          "HK"
          "JP"
          "EU"
        ]
      ) (smartGroups urlTest)
    );
  };

  # 系数只对声明了 smartFactor 的节点生成；未声明的整条省略，
  # 而不是补成 name:1（源码 getPriorityFactor 未命中即返回 1.0）。
  smartRegionPolicyPriority = {
    expected = {
      US = "sjc0:1.2";
      HK = "hkg5:0.8";
      JP = "tyo0:0";
      EU = "";
    };
    result = lib.genAttrs [ "US" "HK" "JP" "EU" ] (
      region: (bySmartName smart region).policy-priority or ""
    );
  };

  # 主文档同区域组不应带 policy-priority。
  mainRegionHasNoPolicyPriority = {
    expected = {
      US = "";
      HK = "";
      JP = "";
      EU = "";
    };
    result = lib.genAttrs [ "US" "HK" "JP" "EU" ] (
      region: (byMainName urlTest region).policy-priority or ""
    );
  };

  # 用户显式声明的 smart 组：系数与 prefer-asn / uselightgbm 一并生成。
  smartUserGroupFields = {
    expected = {
      type = "smart";
      policy-priority = "sjc0:1.2";
      prefer-asn = true;
      uselightgbm = true;
    };
    result = {
      inherit ((bySmartName smartUserGroup "UNLOCK")) type;
      inherit ((bySmartName smartUserGroup "UNLOCK")) policy-priority;
      inherit ((bySmartName smartUserGroup "UNLOCK")) prefer-asn;
      inherit ((bySmartName smartUserGroup "UNLOCK")) uselightgbm;
    };
  };

  # 未声明 smart 类型的用户组不下发 smart 专属键。
  userGroupWithoutSmartHasNoKeys = {
    expected = false;
    result = (byMainName urlTestUserGroup "UNLOCK") ? policy-priority;
  };

  # 升级为 smart 后仍保留原有调度参数，迁移是最小改动。
  smartGroupKeepsSchedulingFields = {
    expected = {
      url = "https://www.gstatic.com/generate_204";
      interval = 300;
      tolerance = 20;
    };
    result = {
      inherit ((bySmartName smart "US")) url interval tolerance;
    };
  };

  # 主文档与 smart 文档的成员和顺序必须一致，只有调度字段允许不同。
  documentsShareMembers = {
    expected = map (g: {
      inherit (g) name;
      proxies = g.proxies or [ ];
    }) (mainGroups urlTest);
    result = map (g: {
      inherit (g) name;
      proxies = g.proxies or [ ];
    }) (smartGroups urlTest);
  };
}
