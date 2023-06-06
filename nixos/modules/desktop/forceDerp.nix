{...}: {
  networking.firewall.extraCommands = ''
    iptables -A INPUT -p udp --dport 41641 -j REJECT
    iptables -A OUTPUT -p udp --dport 41641 -j REJECT
    ip6tables -A INPUT -p udp --dport 41641 -j REJECT
    ip6tables -A OUTPUT -p udp --dport 41641 -j REJECT
  '';
}
