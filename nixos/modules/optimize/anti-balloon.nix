{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.services.anti-balloon;
  kernel = config.boot.kernelPackages.kernel;
  kernelModule = pkgs.stdenv.mkDerivation {
    pname = "kfree-hybrid-ept";
    version = "0.1.0";
    src = ./anti-balloon-kernel-src;
    nativeBuildInputs = kernel.moduleBuildDependencies;
    hardeningDisable = [
      "pic"
      "format"
    ];
    makeFlags = config.boot.kernelPackages.kernelModuleMakeFlags ++ [
      "KDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
      "INSTALL_MOD_PATH=$(out)"
    ];
    meta.platforms = [ "x86_64-linux" ];
  };

  # 可选的 best-effort 随机内存池。MADV_FREE 页面仍计入 RSS/cgroup，
  # 周期读取还会影响客户机 LRU；它既不隐身，也不构成宿主机内存预留。
  # full 降低压缩收益，sparse 降低整页去重收益，两者均不能阻止 host swap。
  antiBalloonSource = ''
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

    #define MAX_EXPAND_PER_STEP (512ULL * 1024 * 1024)
    #define BATCH_FLUSH_LIMIT (2ULL * 1024 * 1024)

    typedef struct {
        char *buf;
        size_t sz;
    } MemBlock;

    static MemBlock *g_blocks = NULL;
    static size_t g_num_blocks = 0;
    static size_t g_blocks_cap = 0;
    static size_t g_total_allocated = 0;

    static volatile sig_atomic_t g_running = 1;
    static void handle_sig(int sig) {
        (void)sig;
        g_running = 0;
    }

    // SplitMix64 supplies inexpensive, non-cryptographic page contents.
    static inline uint64_t splitmix64(uint64_t *state) {
        uint64_t z = (*state += 0x9e3779b97f4a7c15ULL);
        z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ULL;
        z = (z ^ (z >> 27)) * 0x94d049bb133111ebULL;
        return z ^ (z >> 31);
    }

    // High-entropy contents reduce compression opportunities, not host swapping.
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

    // 16 distinct words (128 bytes) per page discourage equality-based merging.
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

    // 读取当前进程真实存活的 LazyFree 内存（字节）
    // 若读取失败（内核不支持 smaps_rollup、文件被拦截等），安全回退至已分配总量 g_total_allocated
    static unsigned long long get_self_lazyfree(void) {
        static int warned = 0;
        FILE *f = fopen("/proc/self/smaps_rollup", "r");
        if (!f) {
            if (!warned) {
                fprintf(stderr, "anti-balloon: warning: /proc/self/smaps_rollup unavailable, falling back to allocated tracking\n");
                warned = 1;
            }
            return g_total_allocated;
        }

        char line[256];
        unsigned long long lf = 0;
        int found = 0;
        while (fgets(line, sizeof(line), f)) {
            if (strncmp(line, "LazyFree:", 9) == 0) {
                sscanf(line + 9, "%llu", &lf);
                lf *= 1024ULL; // kB to bytes
                found = 1;
                break;
            }
        }
        fclose(f);

        if (!found) {
            if (!warned) {
                fprintf(stderr, "anti-balloon: warning: LazyFree field not found in smaps_rollup, falling back to allocated tracking\n");
                warned = 1;
            }
            return g_total_allocated;
        }

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
        int in_container = (getenv("container") != NULL);

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

                    if (strcmp(p, "/") != 0 && strncmp(p, "/system.slice", 13) != 0 && strncmp(p, "/user.slice", 11) != 0) {
                        in_container = 1;
                    }

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

        static int cg_warned = 0;
        if (!cg_warned && in_container && *out_limit == ULLONG_MAX) {
            fprintf(stderr, "anti-balloon: warning: running in container without cgroup memory limit, will allocate against host memory\n");
            cg_warned = 1;
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

    // 计算自适应安全内存余量（字节）
    static unsigned long long calc_safety_margin(unsigned long long total_bytes, int margin_mb) {
        unsigned long long safety_margin = (unsigned long long)margin_mb * 1024ULL * 1024ULL;
        if (total_bytes <= 512ULL * 1024 * 1024) {
            // 微型 VPS（<= 512MB，例如 350MB 实例）：
            // 默认的 512MB 会远超总内存；自适应采用总内存的 10%，保底 24MB，上限 48MB
            unsigned long long micro_margin = total_bytes / 10;
            if (micro_margin < 24ULL * 1024 * 1024) micro_margin = 24ULL * 1024 * 1024;
            if (micro_margin > 48ULL * 1024 * 1024) micro_margin = 48ULL * 1024 * 1024;
            if (safety_margin > micro_margin) safety_margin = micro_margin;
            if (safety_margin < 24ULL * 1024 * 1024) safety_margin = 24ULL * 1024 * 1024;
        } else {
            // 常规服务器：保留上限不超过 1/3 总内存，保底不少于 64MB
            if (safety_margin > total_bytes / 3) safety_margin = total_bytes / 3;
            if (safety_margin < 64ULL * 1024 * 1024) safety_margin = 64ULL * 1024 * 1024;
        }
        return safety_margin;
    }

    // 计算自适应单次最小扩容步长
    static size_t calc_min_expand_sz(unsigned long long total_bytes) {
        if (total_bytes <= 512ULL * 1024 * 1024) {
            return 8ULL * 1024 * 1024; // 小内存 8MB 步长
        }
        return 128ULL * 1024 * 1024; // 常规 128MB 步长
    }

    // 计算自适应脏页分块大小（限制 MADV_FREE 前的未标记脏页峰值）
    static size_t calc_chunk_sz(unsigned long long total_bytes) {
        if (total_bytes <= 512ULL * 1024 * 1024) {
            return 4ULL * 1024 * 1024; // Limit the dirty window on small guests.
        }
        return BATCH_FLUSH_LIMIT; // Keep the initial dirty window bounded too.
    }

    static int allocate_and_fill_block(size_t alloc_sz, int is_full, uint64_t *prng_state, size_t chunk_sz) {
        if (alloc_sz == 0) return 0;

        alloc_sz = (alloc_sz / 4096) * 4096;
        if (alloc_sz < 4096) return 0;

        if (g_num_blocks >= g_blocks_cap) {
            size_t new_cap = (g_blocks_cap == 0) ? 16 : g_blocks_cap * 2;
            MemBlock *new_blocks = realloc(g_blocks, new_cap * sizeof(MemBlock));
            if (!new_blocks) {
                fprintf(stderr, "anti-balloon: realloc failed for block list: %m\n");
                return -1;
            }
            g_blocks = new_blocks;
            g_blocks_cap = new_cap;
        }

        char *buf = mmap(NULL, alloc_sz, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (buf == MAP_FAILED) {
            fprintf(stderr, "anti-balloon: mmap failed for %zu bytes: %m\n", alloc_sz);
            return -1;
        }

        // 显式禁用 THP (Transparent Huge Pages)，避免 2MB 拆分延迟，保证 4KB 粒度可控
        madvise(buf, alloc_sz, MADV_NOHUGEPAGE);

        for (size_t offset = 0; offset < alloc_sz && g_running; offset += chunk_sz) {
            size_t this_chunk = chunk_sz;
            if (offset + this_chunk > alloc_sz) this_chunk = alloc_sz - offset;

            for (size_t i = 0; i < this_chunk && g_running; i += 4096) {
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
        g_total_allocated += alloc_sz;

        fprintf(stderr, "anti-balloon: allocated block %zu (%zu MB, mode=%s, total_held=%zu MB)\n",
                g_num_blocks, alloc_sz / 1024 / 1024, is_full ? "full" : "sparse", g_total_allocated / 1024 / 1024);
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
                if (margin_mb < 16) margin_mb = 16;
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
            unsigned long long safety_margin = calc_safety_margin(total_bytes, margin_mb);
            unsigned long long min_headroom = (total_bytes <= 512ULL * 1024 * 1024)
                                              ? (4ULL * 1024 * 1024)
                                              : (16ULL * 1024 * 1024);
            size_t chunk_sz = calc_chunk_sz(total_bytes);

            if (avail_bytes > safety_margin + min_headroom) {
                size_t alloc_sz = (size_t)(avail_bytes - safety_margin);
                allocate_and_fill_block(alloc_sz, is_full, &prng_state, chunk_sz);
            } else {
                fprintf(stderr, "anti-balloon: available memory (%llu MB) <= safety margin (%llu MB), waiting for memory\n",
                        avail_bytes / 1024 / 1024, safety_margin / 1024 / 1024);
            }
        }

        if (interval_sec <= 0) {
            while (g_running) pause();
            for (size_t b = 0; b < g_num_blocks; b++) munmap(g_blocks[b].buf, g_blocks[b].sz);
            free(g_blocks);
            return 0;
        }

        while (g_running) {
            for (int s = 0; s < interval_sec && g_running; s++) {
                sleep(1);
            }
            if (!g_running) break;

            // Accesses may influence host aging, but cannot prohibit host swap.
            // They also affect guest aging and must remain optional.
            for (size_t b = 0; b < g_num_blocks && g_running; b++) {
                char *buf = g_blocks[b].buf;
                size_t sz = g_blocks[b].sz;

                char *batch_start = NULL;
                size_t batch_len = 0;

                for (size_t i = 0; i < sz && g_running; i += 4096) {
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

                            // Bound newly dirtied memory before making it reclaimable.
                            if (batch_len >= BATCH_FLUSH_LIMIT) {
                                madvise(batch_start, batch_len, MADV_FREE);
                                batch_start = NULL;
                                batch_len = 0;
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

            // 2. 动态自适应扩容：分步平滑推进（单次上限 512MB），避免过大脏页峰值冲顶 cgroup limit
            if (get_effective_memory(&total_bytes, &avail_bytes) == 0) {
                unsigned long long safety_margin = calc_safety_margin(total_bytes, margin_mb);
                size_t min_expand = calc_min_expand_sz(total_bytes);
                size_t chunk_sz = calc_chunk_sz(total_bytes);

                if (avail_bytes > safety_margin + min_expand) {
                    size_t expand_sz = (size_t)(avail_bytes - safety_margin);
                    if (expand_sz > MAX_EXPAND_PER_STEP) {
                        expand_sz = MAX_EXPAND_PER_STEP;
                    }
                    fprintf(stderr, "anti-balloon: dynamic expansion triggered (+%zu MB)\n", expand_sz / 1024 / 1024);
                    allocate_and_fill_block(expand_sz, is_full, &prng_state, chunk_sz);
                }
            }
        }

        fprintf(stderr, "anti-balloon: shutting down, unmapping %zu blocks\n", g_num_blocks);
        for (size_t b = 0; b < g_num_blocks; b++) {
            munmap(g_blocks[b].buf, g_blocks[b].sz);
        }
        free(g_blocks);
        return 0;
    }
  '';
  antiBalloonDaemon = (pkgs.writeCBin "anti-balloon-daemon" antiBalloonSource).overrideAttrs (_: {
    # writeCBin invokes $CC directly without an optimization level.
    env.NIX_CFLAGS_COMPILE = "-O2";
  });
in
{
  options.services.anti-balloon = {
    enable = lib.mkEnableOption "anti-balloon and memory protection" // {
      default = true;
    };

    memoryFiller = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        是否运行随机内存填充进程。设为 false 时仅保留气球驱动阻断与内核配置，
        不分配内存、不周期扫描，也不降低宿主机去重或压缩的收益。
        填充进程的 MADV_FREE 页面仍计入 RSS/cgroup，并非对其它程序不可见。
        无论是否填充，客户机都不能保证宿主机不换出内存。
      '';
    };

    kernel.enable = lib.mkEnableOption ''
      experimental Linux 7.3 x86_64 free-page randomization without a retained
      userspace pool. This uses a conservative order-0 release tracepoint and
      the kernel's isolated page-reporting API, not unsafe refcount/PFN scans.
      Some frees are skipped; there is no periodic EPT or host swap guarantee.
      Filling adds CPU cost to free calls, outside userspace CPU quotas.
      Reporting temporarily isolates up to one 4 MiB block on this kernel
    '';

    cpuQuotaPercent = lib.mkOption {
      type = lib.types.ints.between 1 100;
      default = 5;
      description = ''
        填充进程的 CPU 硬上限，按单个 CPU 的百分比计算，包含初始化与重填。
        默认 5 表示最多占用 0.05 个 CPU，而非整机 CPU 的 5%。
        更低的上限会延长初始化及扫描耗时；Nice 不能代替此上限。
      '';
    };

    interval = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "3m";
      description = ''
        best-effort 内存触碰与重填间隔。访问可能影响宿主机的活跃度估计，但不能阻止 host swap。
        默认为 3m。设为 null 或 "" 可禁用后台常驻保温与动态扩容（仅保留开机一次性初始分配）。
      '';
    };

    safetyMarginMB = lib.mkOption {
      type = lib.types.int;
      default = 512;
      description = ''
        保留给系统与业务突发使用的安全内存余量（MB）。
        注意：在 <= 512MB 的微型机型上，守护进程会自动将余量智能缩放至总内存的 10%（保底 24MB），避免小内存机型分配失效。
      '';
    };

    bootMemtest = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        是否启用内核早期 memtest=1。它测试可用物理内存范围，会增加启动耗时，
        不是随机填充或宿主机内存预留机制，也不能持续阻止去重、压缩或换出。
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
        - "full": 整页 4096 字节填满 SplitMix64 伪随机数，降低压缩与整页去重收益；
        - "sparse": 每页散布 16 个 8 字节随机数，降低整页去重收益，页面仍高度可压缩。
        两种模式都不能阻止气球驱动回收或宿主机换出。
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = lib.optionals cfg.kernel.enable [
      {
        assertion = !cfg.memoryFiller;
        message = "anti-balloon: disable memoryFiller when enabling the kernel backend.";
      }
      {
        assertion = pkgs.stdenv.hostPlatform.isx86_64 && kernel.modDirVersion == "7.3.0";
        message = "anti-balloon: the experimental kernel backend is audited only for x86_64 Linux 7.3.0.";
      }
    ];
    boot.extraModulePackages = lib.optional cfg.kernel.enable kernelModule;
    system.build.anti-balloon-kernel = kernelModule;

    systemd.services.anti-balloon-kernel = lib.mkIf cfg.kernel.enable {
      description = "Best-effort kernel free-page randomization";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-modules-load.service" ];
      unitConfig.ConditionVirtualization = "vm";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # modprobe uses the booted generation's module tree after a live switch.
        # Load this built artifact directly; vermagic still rejects a wrong ABI.
        ExecStart = "${pkgs.kmod}/bin/insmod ${kernelModule}/lib/modules/${kernel.modDirVersion}/updates/kfree_hybrid_ept.ko.xz";
        ExecStop = "${pkgs.kmod}/bin/rmmod kfree_hybrid_ept";
        TimeoutStartSec = "2min";
        TimeoutStopSec = "2min";
      };
    };

    # Optional early memory test, not a residency guarantee.
    boot.kernelParams = lib.mkIf cfg.bootMemtest [ "memtest=1" ];

    # QEMU Guest Agent is independent of ballooning; preserve its configured state.
    # Block loadable balloon drivers and their free-page reporting channels.
    # 注意：若内核将 virtio_balloon 等驱动编译为 built-in (=y)，modprobe 黑名单无法阻止驱动加载，
    # 内置驱动需要对应内核/宿主机配置；填充进程不能替代驱动阻断。
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

    # 3. 内核倾向于丢弃 clean/lazyfree 内存而非将匿名页换入 Guest Swap
    boot.kernel.sysctl = {
      "vm.swappiness" = lib.mkDefault 0;
    };

    # 4. 内存常驻保护守护进程
    systemd.services.anti-balloon = lib.mkIf cfg.memoryFiller {
      description = "Best-effort random memory filler (not a host memory reservation)";
      wantedBy = [ "multi-user.target" ];
      after = [
        "multi-user.target"
        "systemd-oomd.service"
        "earlyoom.service"
      ];
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
        # Unmapping a large pool also needs CPU time under the quota/host steal.
        TimeoutStopSec = "2min";

        # Prevent guest cgroup swapping; this does not control host swapping.
        MemorySwapMax = "0";

        # 初始化填充窗口期若突发极端内存压力，优先牺牲本守护进程，保护业务服务
        OOMScoreAdjust = 1000;

        # 降权与安全加固
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
        PrivateTmp = true;

        # Limit CPU bursts as well as lowering scheduling priority.
        CPUQuota = "${toString cfg.cpuQuotaPercent}%";
        Nice = 19;
        CPUSchedulingPolicy = "batch";
        IOSchedulingClass = "idle";
      };
    };
  };
}
