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
  #    - full 模式：每页 4096 字节全部填充高熵 SplitMix64 伪随机数，压缩率接近 1:1，杜绝 ESXi/Hyper-V/zswap 压缩。
  #    - sparse 模式：每页散布 16 个 cacheline (128 字节) 伪随机数，瓦解 KSM 及简单游程压缩。
  # 2. 批量 madvise 自修复 (Batched LazyFree Recovery)：
  #    - 扫描触碰检测到零页（被内核回收重用）时，自动重填伪随机数，并将连续页面合并为区间单次调用 madvise(MADV_FREE)，
  #      将数万次系统调用骤降为极少数区间调用。
  # 3. 动态多区域扩容 (Dynamic Expansion via Multi-Block List)：
  #    - 维护动态区域数组，定时保温时重新探测可用内存。若系统有业务退出释放出新的闲置内存，自动追加 mmap 分配并初始化。
  # 4. cgroup 与容器内存限制感知 (cgroup v1/v2 Awareness)：
  #    - 优先探测 /sys/fs/cgroup/memory.max (v2) 与 memory.limit_in_bytes (v1)，防止打爆容器或 slice 限制。
  # 5. 规避 THP 干扰 (MADV_NOHUGEPAGE)：
  #    - 分配时显式禁用透明大页，避免 2MB THP 拆分延迟，保证细粒度 4KB 页面分配可控。
  # 6. EPT Accessed 保温与绝对零 OOM (Keep-Warm & Zero OOM)：
  #    - 纯读 1 字节/页刷新硬件 EPT Accessed=1，不置脏位；MADV_FREE 保证全部计入 MemAvailable，内核按需秒级丢弃。
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
    static size_t g_total_held = 0;

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
    static inline void fill_page_full(char *page, uint64_t *state) {
        uint64_t *p64 = (uint64_t *)page;
        for (int i = 0; i < 512; i++) {
            p64[i] = splitmix64(state);
        }
    }

    // 稀疏填充：每页散布 16 个 cacheline (128 字节)，瓦解 KSM 及简单游程压缩
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

    static int get_effective_memory(unsigned long long *out_total, unsigned long long *out_avail) {
        unsigned long long total = 0, avail = 0;
        if (get_meminfo(&total, &avail) != 0) {
            struct sysinfo si;
            if (sysinfo(&si) != 0) return -1;
            total = (unsigned long long)si.totalram * si.mem_unit;
            // sysinfo.freeram 未包含 cache/buffer，保守低估真实可用量
            avail = (unsigned long long)si.freeram * si.mem_unit;
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
        if (buf == MAP_FAILED) return -1;

        // 显式禁用 THP (Transparent Huge Pages)，避免 2MB 拆分延迟，保证 4KB 粒度可控
        madvise(buf, alloc_sz, MADV_NOHUGEPAGE);

        for (size_t offset = 0; offset < alloc_sz; offset += CHUNK_SZ) {
            size_t this_chunk = CHUNK_SZ;
            if (offset + this_chunk > alloc_sz) this_chunk = alloc_sz - offset;

            for (size_t i = 0; i < this_chunk; i += 4096) {
                refill_page(buf + offset + i, is_full, prng_state);
            }
            madvise(buf + offset, this_chunk, MADV_FREE);
        }

        g_blocks[g_num_blocks].buf = buf;
        g_blocks[g_num_blocks].sz = alloc_sz;
        g_num_blocks++;
        g_total_held += alloc_sz;
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

        uint64_t prng_state = (uint64_t)time(NULL) ^ 0xa5a5a5a512345678ULL;

        unsigned long long total_bytes = 0, avail_bytes = 0;
        if (get_effective_memory(&total_bytes, &avail_bytes) == 0) {
            unsigned long long safety_margin = (unsigned long long)margin_mb * 1024ULL * 1024ULL;
            if (safety_margin > total_bytes / 3) safety_margin = total_bytes / 3;
            if (safety_margin < 64ULL * 1024 * 1024) safety_margin = 64ULL * 1024 * 1024;

            if (avail_bytes > safety_margin + 16ULL * 1024 * 1024) {
                size_t alloc_sz = (size_t)(avail_bytes - safety_margin);
                allocate_and_fill_block(alloc_sz, is_full, &prng_state);
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
                    if (__builtin_expect(c == 0, 0)) {
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
                    } else {
                        if (batch_start != NULL) {
                            madvise(batch_start, batch_len, MADV_FREE);
                            batch_start = NULL;
                            batch_len = 0;
                        }
                    }
                }
                if (batch_start != NULL) {
                    madvise(batch_start, batch_len, MADV_FREE);
                }
            }

            // 2. 动态自适应扩容：若业务退出释放出新内存，追加新 VMA 块
            if (get_effective_memory(&total_bytes, &avail_bytes) == 0) {
                unsigned long long safety_margin = (unsigned long long)margin_mb * 1024ULL * 1024ULL;
                if (safety_margin > total_bytes / 3) safety_margin = total_bytes / 3;
                if (safety_margin < 64ULL * 1024 * 1024) safety_margin = 64ULL * 1024 * 1024;

                if (avail_bytes > g_total_held + safety_margin + MIN_EXPAND_SZ) {
                    size_t expand_sz = (size_t)(avail_bytes - g_total_held - safety_margin);
                    allocate_and_fill_block(expand_sz, is_full, &prng_state);
                }
            }
        }

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
        - "full": 整页 4096 字节填满 SplitMix64 伪随机数（高熵，彻底击穿 ESXi、Hyper-V 及宿主机 zswap 的内存压缩）；
        - "sparse": 每页散布 16 个 cacheline (128 字节) 伪随机数，瓦解 KSM 及基础游程压缩（更低初始化 CPU 成本）。
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # 1. 禁用 QEMU Guest Agent 与相关探测
    services.qemuGuest.enable = lib.mkForce false;

    # 2. 彻底焊死各大虚拟化厂商的内存气球回收驱动（Fake install）
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
        ConditionVirtualization = "vm";
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
