{ pkgs, kernelPackages }:
let
  benchmark = pkgs.writeCBin "anti-balloon-benchmark" ''
    #include <stdio.h>
    #include <string.h>
    #include <sys/mman.h>
    #include <time.h>

    static double seconds(clockid_t clock) {
        struct timespec t;
        clock_gettime(clock, &t);
        return t.tv_sec + t.tv_nsec / 1e9;
    }

    int main(void) {
        const size_t size = 8 * 1024 * 1024;
        double wall = seconds(CLOCK_MONOTONIC);
        double cpu = seconds(CLOCK_PROCESS_CPUTIME_ID);
        for (int i = 0; i < 128; i++) {
            void *p = mmap(NULL, size, PROT_READ | PROT_WRITE,
                           MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
            if (p == MAP_FAILED) return 1;
            if (madvise(p, size, MADV_NOHUGEPAGE)) return 1;
            memset(p, i, size);
            if (munmap(p, size)) return 1;
        }
        printf("{\"wall\":%.6f,\"process_cpu\":%.6f}\n",
               seconds(CLOCK_MONOTONIC) - wall,
               seconds(CLOCK_PROCESS_CPUTIME_ID) - cpu);
        return 0;
    }
  '';
in
pkgs.testers.runNixOSTest {
  name = "anti-balloon-kernel";

  defaults = {
    imports = [ ../nixos/modules/optimize/anti-balloon.nix ];
    boot.kernelPackages = kernelPackages;
    services.anti-balloon = {
      memoryFiller = false;
      kernel.enable = true;
    };
    virtualisation.memorySize = 768;
    virtualisation.cores = 2;
    environment.systemPackages = [
      pkgs.python3
      pkgs.stress-ng
    ];
  };

  nodes.machine = { };
  nodes.hardened.boot.kernelParams = [ "init_on_free=1" ];

  testScript = ''
    import json
    import statistics

    start_all()
    machine.wait_for_unit("multi-user.target")
    hardened.wait_for_unit("multi-user.target")
    params = "/sys/module/kfree_hybrid_ept/parameters/"

    machine.wait_for_unit("anti-balloon-kernel.service")
    machine.succeed("systemctl stop anti-balloon-kernel")

    def counter(name):
        return int(machine.succeed("cat " + params + name).strip())

    def benchmark(label):
        samples = [json.loads(machine.succeed("${benchmark}/bin/anti-balloon-benchmark")) for _ in range(3)]
        print(label, {key: statistics.median(s[key] for s in samples) for key in samples[0]})

    with subtest("refuse incompatible security policy without changing it"):
        hardened.fail("modprobe kfree_hybrid_ept")
        hardened.fail("test -d /sys/module/kfree_hybrid_ept")
        hardened.succeed("dmesg | grep -F 'incompatible init_on_free/page_poison policy'")

    with subtest("baseline userspace correctness"):
        benchmark("1 GiB allocation churn, module absent")
        machine.succeed("python3 ${./anti-balloon-memory-test.py}", timeout=40)

    with subtest("load and actually randomize isolated free pages"):
        machine.succeed("systemctl start anti-balloon-kernel")
        machine.succeed("test ! -d /sys/module/virtio_balloon")
        machine.wait_until_succeeds("test $(cat " + params + "reported_pages_colored) -gt 0", timeout=60)
        benchmark("1 GiB allocation churn, module loaded")
        before = counter("free_pages_colored")
        machine.succeed("python3 ${./anti-balloon-memory-test.py}", timeout=40)
        assert counter("free_pages_colored") > before
        machine.succeed("stress-ng --vm 2 --vm-bytes 160M --vm-method all --verify --timeout 15s", timeout=40)

    with subtest("unload during memory churn then reload"):
        machine.succeed("systemd-run --unit=ab-churn --property=RemainAfterExit=yes stress-ng --vm 2 --vm-bytes 128M --verify --timeout 180s")
        for _ in range(3):
            machine.succeed("test $(systemctl show ab-churn -p SubState --value) = running")
            machine.succeed("systemctl stop anti-balloon-kernel", timeout=60)
            machine.fail("test -d /sys/module/kfree_hybrid_ept")
            machine.succeed("systemctl start anti-balloon-kernel", timeout=60)
        machine.succeed("systemctl stop ab-churn")
        machine.succeed("python3 ${./anti-balloon-memory-test.py}", timeout=40)
        print("free pages colored:", counter("free_pages_colored"))
        print("free events skipped:", counter("free_events_skipped"))
        print("isolated pages colored:", counter("reported_pages_colored"))
        machine.succeed("systemctl stop anti-balloon-kernel", timeout=60)
        machine.fail("dmesg | grep -E 'BUG:|Oops:|WARNING:|Bad page state|general protection fault'")
        machine.succeed("python3 ${./anti-balloon-memory-test.py}", timeout=40)
  '';
}
