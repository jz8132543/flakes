# Nextcloud Talk 分布式 HPB 集群核心数据模型
# 该文件为集群唯一的数据源（Single Source of Truth），
# 导出的 plain attrset 被 talk-central.nix 与 talk-edge.nix 引用。
# 拓扑、端口、密钥路径变更仅需修改本文件。
{
  nats = {
    port = 4222;
    host = "cloud.dora.im";
    secretKey = "nextcloud/turn-secret"; # 单源密钥体系：默认复用 turn-secret，也可在 sops 单独添加 nextcloud/nats-credentials 后指向它
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

  edgeNodes = [
    {
      name = "sjc0"; # 与 hostName 一致，用于自识别
      fqdn = "sjc0.dora.im"; # 公网地址（客户端 + 对端互联默认用它）
      tsName = "sjc0.ts"; # Tailscale 地址（仅 inboundFromForeign=false 的对端用它）
      clusterAddr = "sjc0.dora.im"; # gRPC 集群互联目标地址
      hasSignaling = true;
      hasTurn = true;
      inboundFromForeign = true;
      enableIpv4 = true;
      enableIpv6 = false;
      publicIp = "45.143.130.230";
      publicIpv6 = null;
      edgePort = null; # 非标准端口时填数值
      enableCluster = true;
      capacity = 100; # 节点容量/权重注释，供人工调度参考（上游不支持跨节点房间分片）
    }
    {
      name = "cu";
      fqdn = "cuv6.dora.im";
      tsName = "cu.ts";
      # clusterAddr 说明：
      # 上游 nextcloud-spreed-signaling 使用 Go 标准库 tls.Client 进行 gRPC 互联校验，
      # 且源码中未提供 skipverify / servername 覆盖选项，强制验证证书 SAN 与 target 主机名一致。
      # 对端节点互联默认写入 cu.ts:9090 走 Tailscale 内网通道以突破 CN 入站封锁；
      # 若开启公网 CA 强校验，可为互联单独指定 FQDN 并配合内网 DNS/hosts 映射。
      clusterAddr = "cu.ts";
      hasSignaling = true;
      hasTurn = false;
      enableCoturn = false;
      inboundFromForeign = false; # 关键标志：国外对端必须通过 tsName 连它，禁止国外公网直拨 cuv6.dora.im
      enableIpv4 = false;
      enableIpv6 = true;
      publicIp = null;
      publicIpv6 = "cuv6.dora.im";
      edgePort = 50569;
      enableCluster = true;
      capacity = 50; # 节点容量/权重注释，供人工调度参考
    }
    {
      name = "hkg5";
      fqdn = "hkg5.dora.im";
      tsName = "hkg5.ts";
      clusterAddr = "hkg5.dora.im";
      hasSignaling = true;
      hasTurn = true;
      inboundFromForeign = true;
      enableIpv4 = true;
      enableIpv6 = true;
      publicIp = "216.23.94.148";
      publicIpv6 = "2401:2660:2:93::a";
      edgePort = null;
      enableCluster = true;
      capacity = 100; # 节点容量/权重注释，供人工调度参考
    }
  ];
}
