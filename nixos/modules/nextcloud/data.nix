# Nextcloud Talk 分布式 HPB 集群核心数据模型
# 该文件为集群唯一的数据源（Single Source of Truth），
# 导出的 plain attrset 被 talk-central.nix 与 talk-edge.nix 引用。
# 拓扑、端口、密钥路径变更仅需修改本文件。
let
  # ── 全局域名与 Tailscale 后缀可配置项（用户可在此处自定义）────
  domain = "dora.im"; # 公网主域名后缀（默认生成 <name>.dora.im）
  tsSuffix = "ts"; # Tailscale 域名后缀（默认生成 <name>.ts）

  # ── 读取全局基础设施数据源 data.json ─────────────────────────
  dataJson = builtins.fromJSON (builtins.readFile ../../../lib/data/data.json);

  cdnNodesMap = builtins.listToAttrs (
    map (n: {
      inherit (n) name;
      value = n;
    }) (dataJson.cdn.edgeNodes or [ ])
  );

  # ── 节点规范化函数：自动推导/补充缺省字段 ────────────────────
  # 1. publicIp / publicIpv6: 优先使用节点显式配置，留空则自动从 data.json 获取
  # 2. enableIpv4 / enableIpv6: 优先使用节点显式配置，留空则根据 IP 是否存在自动推导
  # 3. fqdn: 留空则自动计算为 "${name}.${domain}"
  # 4. tsName: 留空则自动计算为 "${name}.${tsSuffix}"
  # 5. clusterAddr: 留空则普通节点走 fqdn，国外入站阻断节点（inboundFromForeign=false）走 tsName
  normalizeNode =
    raw:
    let
      cdnNode = cdnNodesMap.${raw.name} or null;

      publicIp =
        if raw ? publicIp && raw.publicIp != null then
          raw.publicIp
        else if cdnNode != null then
          cdnNode.ipv4
        else
          null;

      publicIpv6 =
        if raw ? publicIpv6 && raw.publicIpv6 != null then
          raw.publicIpv6
        else if cdnNode != null then
          cdnNode.ipv6
        else
          null;

      enableIpv4 = raw.enableIpv4 or (publicIp != null);

      enableIpv6 = raw.enableIpv6 or (publicIpv6 != null);

      fqdn = if raw ? fqdn && raw.fqdn != null then raw.fqdn else "${raw.name}.${domain}";

      tsName = if raw ? tsName && raw.tsName != null then raw.tsName else "${raw.name}.${tsSuffix}";

      inboundFromForeign = raw.inboundFromForeign or true;

      clusterAddr =
        if raw ? clusterAddr && raw.clusterAddr != null then
          raw.clusterAddr
        else if inboundFromForeign then
          fqdn
        else
          tsName;
    in
    raw
    // {
      inherit
        fqdn
        tsName
        clusterAddr
        publicIp
        publicIpv6
        enableIpv4
        enableIpv6
        inboundFromForeign
        ;
      hasSignaling = raw.hasSignaling or true;
      hasTurn = raw.hasTurn or true;
      enableCoturn = raw.enableCoturn or (raw.hasTurn or true);
      enableCluster = raw.enableCluster or true;
      edgePort = raw.edgePort or null;
      capacity = raw.capacity or 100;
    };

  # ── 边缘节点原始拓扑声明 ─────────────────────────────────────
  # 说明：凡是可从 data.json 获取或由规则推导的字段均已留空，由 normalizeNode 自动计算！
  rawEdgeNodes = [
    {
      name = "sjc0";
      # 缺省字段（fqdn, tsName, publicIp, publicIpv6, enableIpv4, enableIpv6 等）
      # 全部由 normalizeNode 自动从 data.json 计算并补齐默认值
    }
    {
      name = "cu";
      # cu 位于国内且为独立 IPv6 DDNS 端口映射，特殊字段显式覆盖：
      fqdn = "cuv6.dora.im";
      publicIpv6 = "cuv6.dora.im";
      enableIpv4 = false;
      enableIpv6 = true;
      hasSignaling = true;
      hasTurn = false;
      enableCoturn = false;
      inboundFromForeign = false; # 关键标志：国外对端必须通过 tsName 连它，禁止国外公网直拨 cuv6.dora.im
      edgePort = 50569;
      enableCluster = true;
      capacity = 50;
    }
    {
      name = "hkg0";
      # 缺省字段由 normalizeNode 自动从 data.json 计算并补齐默认值
    }
    {
      name = "hkg5";
      # 缺省字段由 normalizeNode 自动从 data.json 计算并补齐默认值
    }
  ];
in
{
  inherit domain tsSuffix;

  nats = {
    port = 4222;
    host = "fra0.${domain}";
    secretKey = "nextcloud/turn-secret";
  };

  turn = {
    port = 3479;
    tlsPort = 5349;
    secretKey = "nextcloud/turn-secret";
  };

  grpc = {
    port = 9090;
  };

  rtpPortRange = {
    min = 20000;
    max = 20100;
  };

  edgeNodes = map normalizeNode rawEdgeNodes;
}
