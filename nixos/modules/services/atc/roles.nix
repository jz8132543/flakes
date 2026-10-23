{
  config,
  lib,
  ...
}:
with lib;
let
  cdnData = (builtins.fromJSON (builtins.readFile ../../../../lib/data/data.json)).cdn;
  controlNodeNames =
    cdnData.controlNodeNames
      or (map (c: if builtins.isAttrs c then c.name else c) (cdnData.controlNodes or [ ]));
  edgeNodeNames = cdnData.edgeNodeNames or (map (e: e.name) (cdnData.edgeNodes or [ ]));

  isControlNode = builtins.elem config.networking.hostName controlNodeNames;
  isEdgeNode = builtins.elem config.networking.hostName edgeNodeNames;
in
{
  config = mkMerge [
    # ── 控制平面节点自动角色配置 ───────────────────────────────────────────
    (mkIf isControlNode {
      services.atc.ops.enable = mkDefault true;
      services.atc.monitor.enable = mkDefault true;
      services.atc.router.enable = mkDefault true;
      services.atc.tuning.enable = mkDefault true;
      services.atc.edge.enable = mkDefault false;
    })

    # ── 边缘加速节点自动角色配置 ───────────────────────────────────────────
    (mkIf isEdgeNode {
      services.atc.edge.enable = mkDefault true;
      services.atc.tuning.enable = mkDefault true;
      # 确保边缘节点覆盖任何优化模块 (如 infini.nix) 中的关闭设定，强制开启 Traefik 与证书
      services.traefik.enable = mkOverride 40 true;
      security.acme.certs.main.domain = mkOverride 40 "*.${config.networking.domain}";
      systemd.services.acme-order-renew-main.enable = mkOverride 40 true;
      systemd.timers.acme-renew-main.enable = mkOverride 40 true;
      services.atc.ops.enable = mkDefault false;
      services.atc.monitor.enable = mkDefault false;
      services.atc.router.enable = mkDefault false;
    })

    # ── 非 CDN 节点全部静默禁用 ─────────────────────────────────────────────
    (mkIf (!isControlNode && !isEdgeNode) {
      services.atc.edge.enable = mkDefault false;
      services.atc.ops.enable = mkDefault false;
      services.atc.monitor.enable = mkDefault false;
      services.atc.router.enable = mkDefault false;
      services.atc.tuning.enable = mkDefault false;
    })
  ];
}
