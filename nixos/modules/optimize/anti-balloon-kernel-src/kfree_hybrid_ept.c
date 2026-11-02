// SPDX-License-Identifier: GPL-2.0-only
/* Best-effort free-page randomization, not a host memory reservation.
 * Audited against Linux 7.3: mm_page_free precedes free-page preparation.
 * Never access arbitrary PFNs based on a snapshot of their reference count.
 */
#include <linux/atomic.h>
#include <linux/init.h>
#include <linux/kfence.h>
#include <linux/mm.h>
#include <linux/module.h>
#include <linux/page_reporting.h>
#include <linux/random.h>
#include <linux/sched.h>
#include <linux/tracepoint.h>
#include <linux/version.h>

#if !defined(CONFIG_X86_64) || LINUX_VERSION_CODE != KERNEL_VERSION(7, 3, 0)
#error "Re-audit allocator lifetime and reporting APIs before supporting another kernel"
#endif
#if defined(CONFIG_KASAN) || defined(CONFIG_KMSAN) || \
    defined(CONFIG_DEBUG_PAGEALLOC) || defined(CONFIG_DEBUG_OBJECTS_FREE) || \
    defined(CONFIG_DEBUG_LOCK_ALLOC) || defined(CONFIG_PREEMPT_RT)
#error "Unsupported allocator instrumentation: do not disable it to load this module"
#endif

static struct tracepoint *free_tracepoint;
static u64 seed;
static atomic64_t sequence = ATOMIC64_INIT(0);
static atomic64_t free_pages_colored = ATOMIC64_INIT(0);
static atomic64_t free_events_skipped = ATOMIC64_INIT(0);
static atomic64_t reported_pages_colored = ATOMIC64_INIT(0);

static int read_counter(char *buffer, const struct kernel_param *kp)
{
	return sysfs_emit(buffer, "%lld\n", (long long)atomic64_read(kp->arg));
}

static const struct kernel_param_ops counter_ops = { .get = read_counter };
module_param_cb(free_pages_colored, &counter_ops, &free_pages_colored, 0444);
module_param_cb(free_events_skipped, &counter_ops, &free_events_skipped, 0444);
module_param_cb(reported_pages_colored, &counter_ops, &reported_pages_colored, 0444);

static u64 next_word(u64 *state)
{
	u64 value = (*state += 0x9e3779b97f4a7c15ULL);

	value = (value ^ (value >> 30)) * 0xbf58476d1ce4e5b9ULL;
	value = (value ^ (value >> 27)) * 0x94d049bb133111ebULL;
	return value ^ (value >> 31);
}

static void color_page(struct page *page)
{
	u64 *address = page_address(page);
	u64 state = seed + (u64)atomic64_inc_return(&sequence);
	unsigned int i;

	/* Local state also works in interrupt/nested contexts. No shared per-CPU
	 * PRNG state can be lost to preemption. Always rewrite the entire page:
	 * preserved endpoint signatures do not prove the interior is unchanged.
	 */
	/* The release tracepoint may run in preemptible context. SFENCE must
	 * execute on the same CPU that issued these streaming stores.
	 */
	preempt_disable();
	for (i = 0; i < PAGE_SIZE / sizeof(*address); i++) {
		u64 value = next_word(&state);

		asm volatile("movnti %1, %0" : "=m" (address[i]) : "r" (value));
	}
	/* Complete streaming stores before the allocator can reuse the page. */
	asm volatile("sfence" ::: "memory");
	preempt_enable();
}

static void on_page_free(void *unused, struct page *page, unsigned int order)
{
	/* The tracepoint provides ownership, not the reference-count check.
	 * It runs BEFORE allocator validation and debug checks in this kernel.
	 * Reject complex/unprepared pages rather than duplicating that logic.
	 */
	if (in_nmi() || order || PageCompound(page) || PageReserved(page) ||
	    PageHWPoison(page) || PageOffline(page) || PageHighMem(page) ||
	    is_zone_device_page(page) || page_ref_count(page) ||
	    atomic_read(&page->_mapcount) != -1 || READ_ONCE(page->mapping) ||
	    (READ_ONCE(page->flags.f) & PAGE_FLAGS_CHECK_AT_FREE) ||
	    page_pool_page_is_pp(page) ||
	    is_kfence_address(page_address(page)))
		goto skip;
#ifdef CONFIG_MEMCG
	if (READ_ONCE(page->memcg_data))
		goto skip;
#endif
	color_page(page);
	atomic64_inc(&free_pages_colored);
	return;
skip:
	atomic64_inc(&free_events_skipped);
}

static int color_reported_pages(struct page_reporting_dev_info *prdev,
			       struct scatterlist *sgl, unsigned int nents)
{
	struct scatterlist *sg;
	unsigned int entry;

	/* The reporting core isolates these buddy blocks under zone->lock and
	 * calls us after unlocking. No allocator can reuse them until we return.
	 * Nothing is reported to a hypervisor and no pointer survives this call.
	 */
	for_each_sg(sgl, sg, nents, entry) {
		unsigned int i, count = sg->length >> PAGE_SHIFT;
		struct page *page = sg_page(sg);

		for (i = 0; i < count; i++) {
			struct page *sub = page + i;

			/* Isolation prevents reuse, not hardware-poison marking. An
			 * error keeps a partially filled block from being reported.
			 */
			if (PageHWPoison(sub) || PageOffline(sub) ||
			    PageReserved(sub) || PageHighMem(sub) ||
			    is_zone_device_page(sub) ||
			    is_kfence_address(page_address(sub))) {
				atomic64_add(i, &reported_pages_colored);
				return -EIO;
			}
			color_page(page + i);
			if ((i & 15) == 15)
				cond_resched();
		}
		atomic64_add(count, &reported_pages_colored);
	}
	return 0;
}

static struct page_reporting_dev_info reporter = {
	.report = color_reported_pages,
	.order = 0,
	/* One isolated buddy block, not a retained allocation pool. Its maximum
	 * size is PAGE_SIZE << MAX_PAGE_ORDER, not necessarily one base page.
	 */
	.capacity = 1,
};

static void find_free_tracepoint(struct tracepoint *tp, void *unused)
{
	if (!strcmp(tp->name, "mm_page_free"))
		free_tracepoint = tp;
}

static int __init kfree_hybrid_init(void)
{
	int error;

	/* Preserve security policy. Allocation-time zeroing remains enabled. */
	if (want_init_on_free() || page_poisoning_enabled_static()) {
		pr_err("kfree_hybrid_ept: incompatible init_on_free/page_poison policy\n");
		return -EOPNOTSUPP;
	}
	get_random_bytes(&seed, sizeof(seed));
	for_each_kernel_tracepoint(find_free_tracepoint, NULL);
	if (!free_tracepoint)
		return -ENOENT;
	error = tracepoint_probe_register(free_tracepoint, on_page_free, NULL);
	if (error)
		return error;

	/* Do not displace another reporter, including virtio-balloon. Reporting
	 * processes initial/newly freed buddy pages, NOT every idle page every N
	 * seconds. PCP pages are not covered by this asynchronous pass.
	 */
	error = page_reporting_register(&reporter);
	if (error) {
		tracepoint_probe_unregister(free_tracepoint, on_page_free, NULL);
		tracepoint_synchronize_unregister();
		pr_err("kfree_hybrid_ept: reporting registration failed: %d\n", error);
		return error;
	}
	pr_info("kfree_hybrid_ept: active (order-0 release hook, isolated reporting, movnti; no host residency guarantee)\n");
	return 0;
}

static void __exit kfree_hybrid_exit(void)
{
	tracepoint_probe_unregister(free_tracepoint, on_page_free, NULL);
	tracepoint_synchronize_unregister();
	page_reporting_unregister(&reporter);
	pr_info("kfree_hybrid_ept: unloaded\n");
}

module_init(kfree_hybrid_init);
module_exit(kfree_hybrid_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Audited best-effort free-page randomization for Linux 7.3 x86_64");
