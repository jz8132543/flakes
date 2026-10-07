{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.services.anti-balloon;

  # 超轻量 C 防气球与内存保护常驻守护程序：
  # 1. 击穿宿主机内存压缩 (Defeat ESXi/Hyper-V/zswap Compression)：
  #    - full 模式：每页 4096 字节全部填充高熵 SplitMix64 伪随机数，数据熵接近 8.0 bits/byte，杜绝 ESXi/Hyper-V/zswap 压缩。
  #    - sparse 模式：每页散布 16 个 cacheline (128 字节) 伪随机数，仅用于瓦解 KSM 及基础气球探测，无法防御宿主机整页内存压缩。
  # 2. 零误判自修复与批量 madvise (Dual-Sampling & Batched Recovery)：
  #    - 首字节强制非零 + 双采样（偏移 0 和 2048 均为 0 才判定为被内核回收），消除 0.4% 的误报重填损耗。
  #    - 扫描触碰检测到零页时重填随机数，并将连续页面合并为区间单次调用 madvise(MADV_FREE)，系统调用大幅下降。
  # 3. 统一口径的真正动态扩容 (Dynamic Expansion via smaps_rollup LazyFree)：
  #    - 动态从 /proc/self/smaps_rollup 读取当前进程真实存活的 LazyFree 内存，
  #      将 meminfo 路径扣除自身持有量，与 cgroup 路径（memory.max - memory.current）统一为“外部可用内存”口径。
  #      彻底解决 g_total_held 静态记账失真导致的扩容一次后永久失效 Bug。
  # 4. cgroup 与容器内存限制感知 (cgroup v1/v2 Awareness)：
  #    - 优先探测 /sys/fs/cgroup/memory.max (v2) 与 memory.limit_in_bytes (v1)，防止打爆容器或 slice 限制。
  # 5. 规避 THP 干扰 (MADV_NOHUGEPAGE)：
  #    - 分配时显式禁用透明大页，避免 2MB THP 拆分延迟，保证细粒度 4KB 页面分配可控。
  # 6. EPT Accessed 保温与绝对零 OOM (Keep-Warm & Zero OOM)：
  #    - 纯读 1 字节/页刷新硬件 EPT Accessed=1，不置脏位；MADV_FREE 保证全部计入 MemAvailable，内核按需秒级丢弃。
  # 7. 全链路日志与信号响应：
  #    - 填充循环内层定期检查 g_running，收到 SIGTERM 秒级退出；所有关键动作与异常输出 stderr 记录至 journal。
  antiBalloonDaemon = pkgs.writeCBin "anti-balloon-daemon" ''
    #include <stdio.h>
    #include <stdlib.h>
    #include <stdint.h>
    #include <string.h>
    #include <strings.h>
    #include <unistd.h>
    #include <signal.h>
    #include <limits.h>
    #include <sys/mman.h>
    #include <sys/sysinfo.h>
    #include <time.h>

    #define MAX_BLOCKS 64
    #define CHUNK_SZ (256ULL * 1024 * 1024)
    #define MIN_EXPAND_SZ (128ULL * 1024 * 1024)

    typedef struct {
        char *buf;
        size_t sz;
    } MemBlock;

    static MemBlock g_blocks[MAX_BLOCKS];
    static size_t g_num_blocks = 0;

    static volatile sig_atomic_t g_running = 1;
    static void handle_sig(int sig) {
        (void)sig;
        g_running = 0;
    }

    // SplitMix64 PRNG: 寄存器级伪随机数生成器（>3.5 GB/s 吞吐）
    static inline uint64_t splitmix64(uint64_t *state) {
        uint64_t z = (*state += 0x9e3779b97f4a7c15ULL);
        z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ULL;
        z = (z ^ (z >> 27)) * 0x94d049bb133111ebULL;
        return z ^ (z >> 31);
    }

    // 整页填充：每页 4096 字节全部填入高熵随机数，彻底击穿 ESXi/Hyper-V/zswap 内存压缩
    // 强制首字节非零，消除误判为零页的微小概率（1/256 -> 0）
    static inline void fill_page_full(char *page, uint64_t *state) {
        uint64_t *p64 = (uint64_t *)page;
        for (int i = 0; i < 512; i++) {
            p64[i] = splitmix64(state);
        }
        if ((*(unsigned char *)page) == 0) {
            *(unsigned char *)page = 1;
        }
    }

    // 稀疏填充：每页散布 16 个 cacheline (128 字节)，仅瓦解 KSM 及基础气球探测，无法防宿主整页压缩
    static inline void fill_page_sparse(char *page, uint64_t *state) {
        for (int k = 0; k < 16; k++) {
            uint64_t r = splitmix64(state);
            if ((r & 0xff) == 0) r |= 1;
            *(volatile uint64_t *)(page + k * 256) = r;
        }
    }

    static inline void refill_page(char *page, int is_full, uint64_t *state) {
        if (is_full) {
            fill_page_full(page, state);
        } else {
            fill_page_sparse(page, state);
        }
    }

    static int parse_interval(const char *str) {
        if (!str || !*str) return 180;
        char *end = NULL;
        long val = strtol(str, &end, 10);
        if (val <= 0) return 0;
        while (end && (*end == ' ' || *end == '\t')) end++;
        if (end && *end) {
            if (strcasecmp(end, "s") == 0 || strcasecmp(end, "sec") == 0) return (int)val;
            if (strcasecmp(end, "m") == 0 || strcasecmp(end, "min") == 0) return (int)(val * 60);
            if (strcasecmp(end, "h") == 0) return (int)(val * 3600);
        }
        return (int)val;
    }

    // 从 /proc/self/smaps_rollup 读取当前进程真实存活的 LazyFree 内存（字节）
    static unsigned long long get_self_lazyfree(void) {
        FILE *f = fopen("/proc/self/smaps_rollup", "r");
        if (!f) return 0;
        char line[256];
        unsigned long long lf = 0;
        while (fgets(line, sizeof(line), f)) {
            if (strncmp(line, "LazyFree:", 9) == 0) {
                sscanf(line + 9, "%llu", &lf);
                lf *= 1024ULL; // kB to bytes
                break;
            }
        }
        fclose(f);
        return lf;
    }

    static int get_meminfo(unsigned long long *total, unsigned long long *avail) {
        FILE *f = fopen("/proc/meminfo", "r");
        if (!f) return -1;
        char line[256];
        *total = 0; *avail = 0;
        while (fgets(line, sizeof(line), f)) {
            if (strncmp(line, "MemTotal:", 9) == 0) {
                sscanf(line + 9, "%llu", total);
                *total *= 1024ULL;
            } else if (strncmp(line, "MemAvailable:", 13) == 0) {
                sscanf(line + 13, "%llu", avail);
                *avail *= 1024ULL;
            }
        }
        fclose(f);
        return (*total > 0 && *avail > 0) ? 0 : -1;
    }

    static void get_cgroup_memory_limit(unsigned long long *out_limit, unsigned long long *out_avail) {
        *out_limit = ULLONG_MAX;
        *out_avail = ULLONG_MAX;

        // 1. cgroup v2
        FILE *f_cg = fopen("/proc/self/cgroup", "r");
        if (f_cg) {
            char line[512];
            while (fgets(line, sizeof(line), f_cg)) {
                char *p = strstr(line, "::");
                if (p) {
                    p += 2;
                    char *nl = strchr(p, '\n');
                    if (nl) *nl = '\0';

                    char path[1024];
                    snprintf(path, sizeof(path), "/sys/fs/cgroup%s/memory.max", p);
                    FILE *f_max = fopen(path, "r");
                    if (!f_max) {
                        snprintf(path, sizeof(path), "/sys/fs/cgroup/memory.max");
                        f_max = fopen(path, "r");
                    }
                    if (f_max) {
                        char buf[64];
                        if (fgets(buf, sizeof(buf), f_max)) {
                            if (strncmp(buf, "max", 3) != 0) {
                                unsigned long long val = strtoull(buf, NULL, 10);
                                if (val > 0) *out_limit = val;
                            }
                        }
                        fclose(f_max);
                    }

                    if (*out_limit != ULLONG_MAX) {
                        snprintf(path, sizeof(path), "/sys/fs/cgroup%s/memory.current", p);
                        FILE *f_cur = fopen(path, "r");
                        if (f_cur) {
                            char buf[64];
                            if (fgets(buf, sizeof(buf), f_cur)) {
                                unsigned long long cur = strtoull(buf, NULL, 10);
                                if (cur < *out_limit) *out_avail = *out_limit - cur;
                                else *out_avail = 0;
                            }
                            fclose(f_cur);
                        }
                    }
                    break;
                }
            }
            fclose(f_cg);
        }

        // 2. cgroup v1 fallback
        if (*out_limit == ULLONG_MAX) {
            FILE *f_v1 = fopen("/sys/fs/cgroup/memory/memory.limit_in_bytes", "r");
            if (f_v1) {
                char buf[64];
                if (fgets(buf, sizeof(buf), f_v1)) {
                    unsigned long long val = strtoull(buf, NULL, 10);
                    if (val > 0 && val < (1ULL << 60)) {
                        *out_limit = val;
                        FILE *f_cur = fopen("/sys/fs/cgroup/memory/memory.usage_in_bytes", "r");
                        if (f_cur) {
                            if (fgets(buf, sizeof(buf), f_cur)) {
                                unsigned long long cur = strtoull(buf, NULL, 10);
                                if (cur < *out_limit) *out_avail = *out_limit - cur;
                                else *out_avail = 0;
                            }
                            fclose(f_cur);
                        }
                    }
                }
                fclose(f_v1);
            }
        }
    }

    // 统一口径：返回系统中除本进程已持有的 LazyFree 内存外的“外部实际可用内存”
    static int get_effective_memory(unsigned long long *out_total, unsigned long long *out_avail) {
        unsigned long long total = 0, avail = 0;
        if (get_meminfo(&total, &avail) != 0) {
            struct sysinfo si;
            if (sysinfo(&si) != 0) {
                fprintf(stderr, "anti-balloon: failed to query /proc/meminfo and sysinfo\n");
                return -1;
            }
            total = (unsigned long long)si.totalram * si.mem_unit;
            avail = (unsigned long long)si.freeram * si.mem_unit;
        }

        // MemAvailable 包含了本进程的 LazyFree 内存。在此减去本进程存活的 LazyFree，
        // 将口径统一为“本守护进程之外的外部可用内存”，与 cgroup 路径（memory.max - memory.current）
        // 严格一致，彻底消除重复扣减与动态扩容失效问题。
        unsigned long long my_lazyfree = get_self_lazyfree();
        if (avail > my_lazyfree) {
            avail -= my_lazyfree;
        } else {
            avail = 0;
        }

        unsigned long long cg_limit = ULLONG_MAX, cg_avail = ULLONG_MAX;
        get_cgroup_memory_limit(&cg_limit, &cg_avail);

        if (cg_limit < total) total = cg_limit;
        if (cg_avail < avail) avail = cg_avail;

        *out_total = total;
        *out_avail = avail;
        return 0;
    }

    static int allocate_and_fill_block(size_t alloc_sz, int is_full, uint64_t *prng_state) {
        if (g_num_blocks >= MAX_BLOCKS || alloc_sz == 0) return 0;

        alloc_sz = (alloc_sz / 4096) * 4096;
        if (alloc_sz < 4096) return 0;

        char *buf = mmap(NULL, alloc_sz, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (buf == MAP_FAILED) {
            fprintf(stderr, "anti-balloon: mmap failed for %zu bytes: %m\n", alloc_sz);
            return -1;
        }

        // 显式禁用 THP (Transparent Huge Pages)，避免 2MB 拆分延迟，保证 4KB 粒度可控
        madvise(buf, alloc_sz, MADV_NOHUGEPAGE);

        for (size_t offset = 0; offset < alloc_sz && g_running; offset += CHUNK_SZ) {
            size_t this_chunk = CHUNK_SZ;
            if (offset + this_chunk > alloc_sz) this_chunk = alloc_sz - offset;

            for (size_t i = 0; i < this_chunk; i += 4096) {
                refill_page(buf + offset + i, is_full, prng_state);
            }
            madvise(buf + offset, this_chunk, MADV_FREE);
        }

        if (!g_running) {
            fprintf(stderr, "anti-balloon: received termination signal during allocation, aborting\n");
            munmap(buf, alloc_sz);
            return -1;
        }

        g_blocks[g_num_blocks].buf = buf;
        g_blocks[g_num_blocks].sz = alloc_sz;
        g_num_blocks++;
        fprintf(stderr, "anti-balloon: allocated block %zu (%zu MB, mode=%s)\n",
                g_num_blocks, alloc_sz / 1024 / 1024, is_full ? "full" : "sparse");
        return 0;
    }

    int main(int argc, char **argv) {
        int interval_sec = 180;
        int margin_mb = 512;
        int is_full = 1;

        for (int i = 1; i < argc; i++) {
            if (strcmp(argv[i], "--interval") == 0 && i + 1 < argc) {
                interval_sec = parse_interval(argv[++i]);
            } else if (strcmp(argv[i], "--margin") == 0 && i + 1 < argc) {
                margin_mb = atoi(argv[++i]);
                if (margin_mb < 64) margin_mb = 64;
            } else if (strcmp(argv[i], "--fill") == 0 && i + 1 < argc) {
                i++;
                if (strcmp(argv[i], "sparse") == 0) is_full = 0;
                else is_full = 1;
            }
        }

        struct sigaction sa;
        memset(&sa, 0, sizeof(sa));
        sa.sa_handler = handle_sig;
        sigaction(SIGTERM, &sa, NULL);
        sigaction(SIGINT, &sa, NULL);

        fprintf(stderr, "anti-balloon: daemon started (interval=%ds, margin=%dMB, fillMode=%s)\n",
                interval_sec, margin_mb, is_full ? "full" : "sparse");

        uint64_t prng_state = (uint64_t)time(NULL) ^ 0xa5a5a5a512345678ULL;

        unsigned long long total_bytes = 0, avail_bytes = 0;
        if (get_effective_memory(&total_bytes, &avail_bytes) == 0) {
            unsigned long long safety_margin = (unsigned long long)margin_mb * 1024ULL * 1024ULL;
            if (safety_margin > total_bytes / 3) safety_margin = total_bytes / 3;
            if (safety_margin < 64ULL * 1024 * 1024) safety_margin = 64ULL * 1024 * 1024;

            if (avail_bytes > safety_margin + 16ULL * 1024 * 1024) {
                size_t alloc_sz = (size_t)(avail_bytes - safety_margin);
                allocate_and_fill_block(alloc_sz, is_full, &prng_state);
            } else {
                fprintf(stderr, "anti-balloon: available memory (%llu MB) <= safety margin (%llu MB), waiting for memory\n",
                        avail_bytes / 1024 / 1024, safety_margin / 1024 / 1024);
            }
        }

        if (interval_sec <= 0) {
            while (g_running) pause();
            for (size_t b = 0; b < g_num_blocks; b++) munmap(g_blocks[b].buf, g_blocks[b].sz);
            return 0;
        }

        while (g_running) {
            for (int s = 0; s < interval_sec && g_running; s++) {
                sleep(1);
            }
            if (!g_running) break;

            // 1. 保温触碰与批量 madvise 自修复
            for (size_t b = 0; b < g_num_blocks; b++) {
                char *buf = g_blocks[b].buf;
                size_t sz = g_blocks[b].sz;

                char *batch_start = NULL;
                size_t batch_len = 0;

                for (size_t i = 0; i < sz; i += 4096) {
                    volatile unsigned char *p = (volatile unsigned char *)(buf + i);
                    unsigned char c = *p;
                    // 双采样判定：偏移 0 和偏移 2048 均为 0 才确认页面已被内核回收为共享零页
                    if (__builtin_expect(c == 0, 0)) {
                        unsigned char c_mid = *(volatile unsigned char *)(buf + i + 2048);
                        if (c_mid == 0) {
                            refill_page(buf + i, is_full, &prng_state);
                            if (batch_start == NULL) {
                                batch_start = buf + i;
                                batch_len = 4096;
                            } else if (batch_start + batch_len == buf + i) {
                                batch_len += 4096;
                            } else {
                                madvise(batch_start, batch_len, MADV_FREE);
                                batch_start = buf + i;
                                batch_len = 4096;
                            }
                            continue;
                        }
                    }
                    if (batch_start != NULL) {
                        madvise(batch_start, batch_len, MADV_FREE);
                        batch_start = NULL;
                        batch_len = 0;
                    }
                }
                if (batch_start != NULL) {
                    madvise(batch_start, batch_len, MADV_FREE);
                }
            }

            // 2. 动态自适应扩容：口径已统一为“除自身 LazyFree 外的外部可用内存”，
            //    只要 avail_bytes 超过安全余量与阈值，即说明有新内存被外部业务释放
            if (get_effective_memory(&total_bytes, &avail_bytes) == 0) {
                unsigned long long safety_margin = (unsigned long long)margin_mb * 1024ULL * 1024ULL;
                if (safety_margin > total_bytes / 3) safety_margin = total_bytes / 3;
                if (safety_margin < 64ULL * 1024 * 1024) safety_margin = 64ULL * 1024 * 1024;

                if (avail_bytes > safety_margin + MIN_EXPAND_SZ) {
                    size_t expand_sz = (size_t)(avail_bytes - safety_margin);
                    fprintf(stderr, "anti-balloon: dynamic expansion triggered (+%zu MB)\n", expand_sz / 1024 / 1024);
                    allocate_and_fill_block(expand_sz, is_full, &prng_state);
                }
            }
        }

        fprintf(stderr, "anti-balloon: shutting down, unmapping %zu blocks\n", g_num_blocks);
        for (size_t b = 0; b < g_num_blocks; b++) {
            munmap(g_blocks[b].buf, g_blocks[b].sz);
        }
        return 0;
    }
  '';
in
{
  options.services.anti-balloon = {
    enable = lib.mkEnableOption "anti-balloon and memory protection" // {
      default = true;
    };

    interval = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "3m";
      description = ''
        防止宿主机将冷内存换出到宿主 Swap 的刷新间隔（定时以纯读方式触碰内存刷新 EPT Accessed 位）。
        默认为 3m。设为 null 或 "" 可禁用后台常驻保温。
      '';
    };

    safetyMarginMB = lib.mkOption {
      type = lib.types.int;
      default = 512;
      description = ''
        保留给系统与业务突发使用的安全内存余量（MB）。
      '';
    };

    fillMode = lib.mkOption {
      type = lib.types.enum [
        "full"
        "sparse"
      ];
      default = "full";
      description = ''
        页面填充模式：
        - "full": 整页 4096 字节填满 SplitMix64 伪随机数（高熵，彻底击穿 ESXi、Hyper-V 及宿主机 zswap 的整页内存压缩与 KSM 去重，推荐）；
        - "sparse": 每页散布 16 个 cacheline (128 字节) 伪随机数，仅用于瓦解 KSM 及基础气球探测，无法防御宿主机整页内存压缩（初始化 CPU 开销极低）。
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # 1. 禁用 QEMU Guest Agent 与相关探测
    # 注意：禁用 qemuGuest 会使 Proxmox/SolusVM 等控制面板无法获取客户机内部 IP，
    # 且基于 QEMU-GA 的 fsfreeze 快照一致性保障将失效（但 ACPI 在线关机等不受影响）。
    services.qemuGuest.enable = lib.mkForce false;

    # 2. 彻底焊死各大虚拟化厂商的内存气球回收驱动（Fake install）
    # 注意：若内核将 virtio_balloon 等驱动编译为 built-in (=y)，modprobe 黑名单无法阻止驱动加载，
    # 此时主要依靠上述守护进程的真实物理页扣押与定期 keep-warm 保温提供防护。
    boot.extraModprobeConfig = ''
      install virtio_balloon /bin/false
      install vmw_balloon /bin/false
      install hv_balloon /bin/false
      install xen_balloon /bin/false
    '';

    boot.blacklistedKernelModules = [
      "virtio_balloon"
      "vmw_balloon"
      "hv_balloon"
      "xen_balloon"
    ];

    # 3. 内存常驻保护守护进程
    systemd.services.anti-balloon = {
      description = "Anti-balloon memory protection daemon (EPT keep-warm & KSM prevention)";
      wantedBy = [ "multi-user.target" ];
      after = [ "multi-user.target" ];
      unitConfig = {
        ConditionVirtualization = true;
        StartLimitIntervalSec = "60s";
        StartLimitBurst = 5;
      };
      serviceConfig = {
        Type = "exec";
        ExecStart = "${antiBalloonDaemon}/bin/anti-balloon-daemon --interval ${
          if cfg.interval != null && cfg.interval != "" then cfg.interval else "0"
        } --margin ${toString cfg.safetyMarginMB} --fill ${cfg.fillMode}";
        Restart = "on-failure";
        RestartSec = "10s";

        # 绝不将自身换出到 Swap 分区
        MemorySwapMax = "0";

        # 初始化填充窗口期若突发极端内存压力，优先牺牲本守护进程，保护业务服务
        OOMScoreAdjust = 1000;

        # 降权与安全加固
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
        PrivateTmp = true;

        # 最低 CPU 与 IO 调度优先级，确保完全不影响任何业务进程
        Nice = 19;
        CPUSchedulingPolicy = "batch";
        IOSchedulingClass = "idle";
      };
    };
  };
}
