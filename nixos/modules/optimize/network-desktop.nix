{
  lib,
  ...
}:
{
  # 针对桌面/笔记本环境的优化，覆盖 base/network-base.nix 中的过于激进的服务器设置
  # 解决连接手机热点时网络变差、断网、以及手机端断流的问题。

  systemd.services.set-initcwnd.script = lib.mkForce ''
    TARGET="1.1.1.1"
    GW_INFO=$(ip -4 route get $TARGET 2>/dev/null | head -n 1)
    IFACE=$(echo "$GW_INFO" | awk '{for(i=1;i<NF;i++) if($i=="dev") print $(i+1)}')
    [ -z "$IFACE" ] && exit 0

    # 探测真实可用 MTU
    BEST_PAYLOAD=1472
    for size in $(seq 1472 -10 1200); do
      if ping -I "$IFACE" -c 1 -M do -s $size -W 1 $TARGET >/dev/null 2>&1; then
        BEST_PAYLOAD=$size
        break
      fi
    done
    MSS=$((BEST_PAYLOAD - 12))

    # 桌面/笔记本模式：使用大幅降低的初始拥塞窗口
    # 避免瞬间突发包冲垮手机热点的小缓冲区
    INITCWND=32
    INITRWND=64

    # 应用 IPv4 默认路由
    DEF4=$(ip -4 route show default dev "$IFACE" | head -n 1)
    if [ -n "$DEF4" ]; then
      ip route change $DEF4 initcwnd $INITCWND initrwnd $INITRWND advmss $MSS || true
    fi

    # IPv6
    TARGET6="2606:4700:4700::1111"
    GW6_INFO=$(ip -6 route get $TARGET6 2>/dev/null | head -n 1)
    IFACE6=$(echo "$GW6_INFO" | awk '{for(i=1;i<NF;i++) if($i=="dev") print $(i+1)}')
    if [ -n "$IFACE6" ]; then
      MSS6=$((MSS - 20))
      DEF6=$(ip -6 route show default dev "$IFACE6" | head -n 1)
      [ -n "$DEF6" ] && ip -6 route change $DEF6 initcwnd $INITCWND initrwnd $INITRWND advmss $MSS6 || true
    fi

    echo "[set-initcwnd-desktop] iface=$IFACE MSS=$MSS initcwnd=$INITCWND initrwnd=$INITRWND"
  '';

  # 禁用自动 NIC Offloads 开启服务（硬件卸载可能导致某些 WiFi 驱动不稳定）
  systemd.services.enable-nic-offloads.enable = lib.mkForce false;
}
