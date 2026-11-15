args@{ config, lib, ... }:
let
  cfg = config.services.livekitSuite;
  self = args.self or { };
  nodes = args.nodes or { };
  livekitNodes = args.livekitNodes or null;
  # Only these scalar metadata branches are inspected. Never read node.pkgs or a toplevel.
  inventory =
    if livekitNodes != null then
      livekitNodes
    else if nodes != { } then
      nodes
    else
      self.nixosConfigurations or { };
  metadata = lib.mapAttrs (
    _: node:
    lib.attrByPath [ "services" "livekitSuite" "_meta" ] { enable = false; } (node.config or node)
  ) inventory;
  enabled = lib.filterAttrs (_: meta: meta.enable) metadata;
  byRole = role: lib.filterAttrs (_: meta: meta.roles.${role} or false) enabled;
  list = role: lib.mapAttrsToList (name: meta: meta // { inherit name; }) (byRole role);
  turnNodes = list "turn";
  sfuNodes = list "sfu";
  primary = builtins.filter (node: node.primary) sfuNodes;
  primaryNode =
    if primary != [ ] then
      builtins.head primary
    else if sfuNodes != [ ] then
      builtins.head sfuNodes
    else
      null;
  urlFor =
    node:
    "wss://${node.domain}${lib.optionalString (node.httpsPort != 443) ":${toString node.httpsPort}"}";
  host =
    meta:
    if meta.turnDomain != "" then
      meta.turnDomain
    else if meta.publicIpv4 != "" then
      meta.publicIpv4
    else
      "[${meta.publicIpv6}]";
in
{
  options.services.livekitSuite.topology = lib.mkOption {
    type = lib.types.raw;
    readOnly = true;
    internal = true;
    description = "Lazy derived topology, consumed only by final runtime configuration artifacts.";
  };
  config.services.livekitSuite.topology = {
    inherit sfuNodes turnNodes;
    redisNodes = list "redis";
    primary = if primaryNode == null then null else primaryNode // { url = urlFor primaryNode; };
    nodes = map (node: {
      inherit (node) name region;
      url = urlFor node;
    }) sfuNodes;
    iceServers = lib.concatMap (node: [
      { urls = [ "stun:${host node}:${toString node.turnPort}" ]; }
      {
        urls = [
          "turn:${host node}:${toString node.turnPort}?transport=udp"
          "turn:${host node}:${toString node.turnPort}?transport=tcp"
          "turns:${host node}:${toString node.turnTlsPort}?transport=tcp"
        ];
      }
    ]) turnNodes;
    turnServers = lib.concatMap (
      node:
      map
        (protocol: {
          host = host node;
          port = if protocol == "tls" then node.turnTlsPort else node.turnPort;
          inherit protocol;
          ttl = cfg.settings.turn.credentialTtl;
        })
        [
          "udp"
          "tcp"
          "tls"
        ]
    ) turnNodes;
  };
}
