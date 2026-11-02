{ pkgs }:
pkgs.testers.runNixOSTest {
  name = "tssh-auto";

  defaults =
    { lib, ... }:
    {
      imports = [ ../nixos/modules/base/openssh.nix ];
      options.ports.ssh = lib.mkOption {
        type = lib.types.port;
        default = 1022;
      };
      config = {
        networking.domain = "test";
        virtualisation.memorySize = 768;
        boot.kernelModules = [ "sch_netem" ];
        programs.ssh.transport = {
          package = pkgs.tsshd;
          clientPackage = pkgs.trzsz-ssh-auto;
        };
      };
    };

  nodes = {
    client = {
      environment.systemPackages = [
        pkgs.trzsz-ssh-auto
        pkgs.python3
        pkgs.curl
      ];
      networking.interfaces.eth1.ipv6.addresses = [
        {
          address = "2001:db8:1::1";
          prefixLength = 64;
        }
      ];
    };
    server = {
      systemd.services.http-fixture = {
        wantedBy = [ "multi-user.target" ];
        preStart = ''
          mkdir -p /tmp/http-fixture
          printf 'forward-ok' > /tmp/http-fixture/marker
        '';
        serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 -m http.server 18080 --bind 127.0.0.1 --directory /tmp/http-fixture";
      };
      networking.interfaces.eth1.ipv6.addresses = [
        {
          address = "2001:db8:1::3";
          prefixLength = 64;
        }
      ];
    };
    cu = { };
  };

  testScript = ''
    import shlex

    start_all()
    for machine in (client, server, cu):
        machine.wait_for_unit("multi-user.target")
        machine.wait_for_unit("sshd.service")
        machine.wait_for_open_port(1022)
        machine.succeed("mkdir -p /root/.ssh && chmod 700 /root/.ssh")

    client.succeed("ssh-keygen -q -t ed25519 -N \"\" -f /root/.ssh/id_ed25519")
    public_key = client.succeed("cat /root/.ssh/id_ed25519.pub").strip()
    for machine in (client, server, cu):
        machine.succeed("printf '%s\\n' " + shlex.quote(public_key) + " > /root/.ssh/authorized_keys")

    ssh_config = """Host plain
      HostName cu
    Host server6
      HostName 2001:db8:1::3
    Host *
      User root
      Port 1022
      StrictHostKeyChecking no
      UserKnownHostsFile /dev/null
      ControlMaster no
      ControlPath none
      ConnectTimeout 5
      #!! AutoTransport yes
      #!! AutoTransportTimeout 2
      #!! ReliableIO yes
      #!! TsshdPath /run/current-system/sw/bin/tsshd
      #!! UdpMTU 1350
      #!! UdpHeartbeatTimeout 8
      #!! UdpAliveTimeout 24h
    """
    client.succeed("printf '%s' " + shlex.quote(ssh_config) + " > /root/.ssh/config")
    tssh = "timeout -k 5 45 ${pkgs.trzsz-ssh-auto}/bin/tssh --auto-transport --reliable-io -4 -T"

    def run(host, command, options=""):
        return client.succeed(tssh + " -n " + options + " " + host + " " + command)

    with subtest("default policy excludes only cu and preserves TCP"):
        server.succeed("grep -Fx 'VersionAddendum tsshd-kcp-auto-v1' /etc/ssh/sshd_config")
        cu.fail("grep -F 'VersionAddendum tsshd-kcp-auto-v1' /etc/ssh/sshd_config")
        cu.fail("test -x /run/current-system/sw/bin/tsshd")
        run("server", "true", "--tcp --debug")
        run("plain", "true")

    with subtest("direct KCP and reliable payload EOF"):
        assert run("server", "printf kcp-ok").strip() == "kcp-ok"
        assert run("server", "ss -Hlun 'sport >= 61001 and sport <= 61999'").strip()
        client.succeed("seq 1 8192 > /tmp/input")
        client.succeed(tssh + " server cat < /tmp/input > /tmp/output")
        client.succeed("cmp /tmp/input /tmp/output")
        status, output = client.execute(tssh + " -n server sh -c 'exit 37'")
        assert status == 37, (status, output)

    with subtest("native chain when any hop lacks capability"):
        assert run("plain", "printf mixed-ok", "-J server").strip() == "mixed-ok"
        assert run("server", "printf mixed-hop-ok", "-J plain").strip() == "mixed-hop-ok"

    with subtest("complete multi-hop KCP"):
        assert run("client", "printf chain-ok", "-J server").strip() == "chain-ok"
        assert run("client", "ss -Hlun 'sport >= 61001 and sport <= 61999'", "-J server").strip()
        client.succeed(tssh + " -J server client cat < /tmp/input > /tmp/chain-output")
        client.succeed("cmp /tmp/input /tmp/chain-output")

    with subtest("literal IPv6 bind and IPv6 UDP timeout"):
        ipv6 = tssh.replace(" -4 ", " -6 ")
        assert client.succeed(ipv6 + " -n server6 printf ipv6-ok").strip() == "ipv6-ok"
        server.succeed("ip6tables -I INPUT -p udp --dport 61001:61999 -j DROP")
        assert client.succeed(ipv6 + " -n server6 printf ipv6-fallback").strip() == "ipv6-fallback"
        server.succeed("ip6tables -D INPUT -p udp --dport 61001:61999 -j DROP")

    with subtest("UDP timeout falls back without repeating the application"):
        server.succeed("iptables -I INPUT -p udp --dport 61001:61999 -j DROP")
        run("server", "sh -c 'echo once >> /tmp/executions'")
        assert server.succeed("wc -l < /tmp/executions").strip() == "1"
        client.succeed(tssh + " server cat < /tmp/input > /tmp/fallback-output")
        client.succeed("cmp /tmp/input /tmp/fallback-output")
        server.succeed("iptables -D INPUT -p udp --dport 61001:61999 -j DROP")

    with subtest("target UDP timeout rolls back an already established KCP hop"):
        client.succeed("iptables -I INPUT -p udp --dport 61001:61999 -j DROP")
        client.succeed("ip6tables -I INPUT -p udp --dport 61001:61999 -j DROP")
        run("client", "sh -c 'echo once >> /tmp/target-executions'", "-J server")
        assert client.succeed("wc -l < /tmp/target-executions").strip() == "1"
        client.succeed("iptables -D INPUT -p udp --dport 61001:61999 -j DROP")
        client.succeed("ip6tables -D INPUT -p udp --dport 61001:61999 -j DROP")

    with subtest("stale marker is fatal rather than a downgrade"):
        client.fail(tssh + " -n -o TsshdPath=/nonexistent/tsshd server true")
        run("server", "true", "--tcp -o TsshdPath=/nonexistent/tsshd")

    with subtest("PTY initial size and SIGWINCH propagation"):
        client.succeed("python3 ${./tssh-pty-test.py} ${pkgs.trzsz-ssh-auto}/bin/tssh")

    with subtest("non-PTY installer-style stdin and dynamic forwarding"):
        script = "mkdir -p /tmp/installer-fixture; printf installed > /tmp/installer-fixture/result; printf installer-ok"
        client.succeed("printf '%s' " + shlex.quote(script) + " > /tmp/install-input")
        assert client.succeed(tssh + " server sh < /tmp/install-input").strip() == "installer-ok"
        assert server.succeed("cat /tmp/installer-fixture/result").strip() == "installed"
        server.wait_for_unit("http-fixture.service")
        server.wait_for_open_port(18080)
        client.succeed("systemd-run --unit=tssh-forward --property=TimeoutStopSec=5 --setenv=HOME=/root "
                       "${pkgs.trzsz-ssh-auto}/bin/tssh --auto-transport --reliable-io -T -n -D 1080 server sleep 30")
        client.wait_for_open_port(1080)
        assert client.succeed("curl -fsS --max-time 10 --socks5-hostname 127.0.0.1:1080 --noproxy \"\" http://127.0.0.1:18080/marker").strip() == "forward-ok"
        client.succeed("systemctl stop tssh-forward")

    with subtest("independent concurrent instances use distinct UDP ports"):
        def udp_ports():
            return {line.split()[3].rsplit(":", 1)[-1] for line in
                    server.succeed("ss -Hlun 'sport >= 61001 and sport <= 61999'").splitlines()}

        before = udp_ports()
        for index in range(2):
            command = "touch /tmp/concurrent-" + str(index) + "; sleep 30"
            client.succeed("systemd-run --unit=tssh-concurrent-" + str(index) +
                           " --property=TimeoutStopSec=5 --setenv=HOME=/root "
                           "${pkgs.trzsz-ssh-auto}/bin/tssh --auto-transport --reliable-io -4 -T -n "
                           "-oAutoTransportTimeout=10 server sh -c " + shlex.quote(command))
        for index in range(2):
            server.wait_until_succeeds("test -e /tmp/concurrent-" + str(index), timeout=20)
        assert len(udp_ports() - before) >= 2
        for index in range(2):
            client.succeed("systemctl stop tssh-concurrent-" + str(index))

    with subtest("exhausted configured port fails closed before application"):
        port = next(port for port in range(61001, 62000) if str(port) not in udp_ports())
        holder = ("import socket,time,pathlib; s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); "
                  "s.bind(('0.0.0.0'," + str(port) + ")); "
                  "pathlib.Path('/tmp/port-held').touch(); time.sleep(60)")
        server.succeed("systemd-run --unit=tssh-port-holder --property=TimeoutStopSec=5 "
                       "${pkgs.python3}/bin/python3 -c " + shlex.quote(holder))
        server.wait_until_succeeds("test -e /tmp/port-held", timeout=20)
        client.fail(tssh + " -n -oTsshdPort=" + str(port) + " server touch /tmp/exhaustion-application")
        server.fail("test -e /tmp/exhaustion-application")
        server.succeed("systemctl stop tssh-port-holder")

    with subtest("KCP payload survives delay loss duplication and reordering"):
        server.succeed("tc qdisc replace dev eth1 root netem delay 50ms loss 5% duplicate 1% reorder 5%")
        kcp_only = 'case "$(ps -o comm= -p "$PPID")" in tsshd*) cat;; *) exit 99;; esac'
        client.succeed(tssh + " -oAutoTransportTimeout=10 server sh -c " + shlex.quote(kcp_only) +
                       " < /tmp/input > /tmp/impaired-output")
        client.succeed("cmp /tmp/input /tmp/impaired-output")
        server.succeed("tc qdisc del dev eth1 root")

    with subtest("short post-commit UDP blackout does not rerun the application"):
        command = ('case "$(ps -o comm= -p "$PPID")" in tsshd*) ;; *) exit 99;; esac; '
                   "echo once >> /tmp/blackout-count; touch /tmp/blackout-start; "
                   "printf begin; sleep 2; printf middle; sleep 4; printf end")
        client.succeed("systemd-run --unit=tssh-blackout --property=TimeoutStopSec=5 "
                       "--property=StandardOutput=file:/tmp/blackout-output --property=StandardError=journal --setenv=HOME=/root "
                       "${pkgs.trzsz-ssh-auto}/bin/tssh --auto-transport --reliable-io -4 -T -n "
                       "server sh -c " + shlex.quote(command))
        server.wait_until_succeeds("test -e /tmp/blackout-start", timeout=20)
        server.succeed("iptables -I INPUT -p udp --dport 61001:61999 -j DROP")
        server.succeed("ip6tables -I INPUT -p udp --dport 61001:61999 -j DROP")
        server.succeed("sleep 4")
        server.succeed("iptables -D INPUT -p udp --dport 61001:61999 -j DROP")
        server.succeed("ip6tables -D INPUT -p udp --dport 61001:61999 -j DROP")
        client.wait_until_succeeds("! systemctl is-active --quiet tssh-blackout", timeout=30)
        assert client.succeed("systemctl show tssh-blackout -p ExecMainStatus --value").strip() == "0"
        output = client.succeed("cat /tmp/blackout-output")
        assert output == "beginmiddleend", repr(output)
        assert server.succeed("wc -l < /tmp/blackout-count").strip() == "1"
  '';
}
