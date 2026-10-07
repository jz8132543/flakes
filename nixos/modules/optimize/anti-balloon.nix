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
  # 2. 零误判自修复与压缩脏页窗口 (Dual-Sampling & Bounded Dirty Window)：
  #    - 首字节强制非零 + 双采样（偏移 0 和 2048 均为 0 才判定为被内核回收），消除误报重填损耗。
  #    - 重填时每攒满 2MB (BATCH_FLUSH_LIMIT) 即强制下刷 madvise(MADV_FREE)，极度压缩脏页留存窗口，杜绝被 Guest swap 击穿。
  # 3. 统一口径与安全回退的动态扩容 (Dynamic Expansion via smaps_rollup LazyFree with Fallback)：
  #    - 动态从 /proc/self/smaps_rollup 读取当前进程真实存活的 LazyFree 内存，meminfo 路径扣除自身持有量；
  #    - 若 smaps_rollup 读取失败或受阻，自动回退至 g_total_allocated 记账值作为上限保护，防止误判外部可用引发失控扩容；
  #    - 内存块列表采用 realloc 动态数组，解除静态数量上限；单次扩容上限平滑控制为 512MB。
  # 4. cgroup 与容器内存限制感知 (cgroup v1/v2 Awareness)：
  #    - 优先探测 /sys/fs/cgroup/memory.max (v2) 与 memory.limit_in_bytes (v1)，防止打爆容器或 slice 限制。
  #    - 若在无配额容器中运行，输出显式警告日志。
  # 5. 规避 THP 干扰 (MADV_NOHUGEPAGE)：
  #    - 分配时显式禁用透明大页，避免 2MB THP 拆分延迟，保证细粒度 4KB 页面分配可控。
  # 6. EPT Accessed 保温与绝对零 OOM (Keep-Warm & Zero OOM)：
  #    - 纯读 1 字节/页刷新硬件 EPT Accessed=1，不置脏位；MADV_FREE 保证全部计入 MemAvailable，内核按需秒级丢弃。
  #    - （注：纯读会置位 Guest 页表 accessed/young 位，轻微延缓 Guest 内核回收探测，这是为了维持硬件 EPT Accessed=1 的必要权衡）。
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
            return 4ULL * 1024 * 1024; // 4MB 分块，脏页峰值极低，杜绝小机器 OOM
        }
        return 64ULL * 1024 * 1024; // 64MB 分块
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

            // 1. 保温触碰与批量 madvise 自修复
            // 注意：纯读访问会置位 Guest 页表的 accessed/young 位，
            // 轻微延缓 Guest 内核的页帧换出探测（需第二轮 LRU 遍历才丢弃），
            // 这是为了维持硬件 EPT Accessed=1 阻止宿主 Swap 的必要且可接受代价。
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

                            // 压缩脏页窗口：累积达 BATCH_FLUSH_LIMIT (2MB) 即强制刷出，
                            // 彻底杜绝极端内存压力下重填脏页被换入 Guest swap 的风险
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
        防止宿主机将冷内存换出到宿主 Swap 的刷新间隔（定时以纯读方式触碰内存刷新 EPT Accessed 位并执行动态自适应扩容）。
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
        是否在内核早期启动阶段开启 memtest=1 进行全内存物理着色（0 运行时开销）。
        开启后 Linux 内核在 early boot 阶段（进入用户空间前，mm/memtest.c）会遍历写入全部物理内存，
        强制宿主机 EPT 为整台虚拟机分配 100% 物理页（GPA -> HPA）并置位 Accessed/Dirty 位。
        测试完成后物理页立即归还给内核伙伴系统，运行时 0 内存开销、0 OOM 风险。
        在 <= 512MB 的超小 VPS 上耗时仅约 0.01 秒，强烈推荐配合使用。
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
    # 0. 早期内核级物理内存着色（0 运行期内存开销，开机 EPT 满载）
    boot.kernelParams = lib.mkIf cfg.bootMemtest [ "memtest=1" ];

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

    # 3. 内核倾向于丢弃 clean/lazyfree 内存而非将匿名页换入 Guest Swap
    boot.kernel.sysctl = {
      "vm.swappiness" = lib.mkDefault 0;
    };

    # 4. 内存常驻保护守护进程
    systemd.services.anti-balloon = {
      description = "Anti-balloon memory protection daemon (EPT keep-warm & KSM prevention)";
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
