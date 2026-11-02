#!/usr/bin/env python3
"""Bounded userspace memory-integrity fixture for an isolated NixOS test VM."""

import hashlib
import mmap
import multiprocessing
import time


WORKERS = 2
MAPPING_BYTES = 8 * 1024 * 1024
RUN_SECONDS = 15
TIMEOUT_SECONDS = 25


def worker(worker_id, ready, deadline):
    # Two workers peak at 64 MiB of mappings, payloads and comparison buffers,
    # leaving room for Python overhead within the 128 MiB fixture budget.
    zeroes = bytes(MAPPING_BYTES)
    ready.wait(timeout=5)
    iteration = 0
    while time.monotonic() < deadline:
        label = f"worker={worker_id} iteration={iteration}"
        with mmap.mmap(
            -1, MAPPING_BYTES,
            flags=mmap.MAP_PRIVATE | mmap.MAP_ANONYMOUS,
            prot=mmap.PROT_READ | mmap.PROT_WRITE,
        ) as region:
            if hasattr(mmap, "MADV_HUGEPAGE"):
                region.madvise(mmap.MADV_HUGEPAGE)
            # Reading may use the global zero page; the full write below also
            # exercises private backing pages rather than only read faults.
            if region[:] != zeroes:
                raise AssertionError(f"Nonzero fresh memory: {label}")
            payload = hashlib.shake_256(label.encode("ascii")).digest(MAPPING_BYTES)
            region[:] = payload
            if region[:] != payload:
                raise AssertionError(f"Corruption immediately after write: {label}")
            # Stagger holding times so the faster worker churns allocations
            # while the slower worker retains and rechecks its mapping.
            time.sleep(0.005 if worker_id == 0 else 0.15)
            if region[:] != payload:
                raise AssertionError(f"Corruption after yielding: {label}")
        del payload
        iteration += 1
    if iteration < 2:
        raise AssertionError(f"Worker {worker_id} completed too few iterations")
    print(f"worker={worker_id}: verified {iteration} mappings", flush=True)


def main():
    started = time.monotonic()
    # This fixture targets Linux; fork avoids extra interpreter/tracker startup.
    context = multiprocessing.get_context("fork")
    ready = context.Barrier(WORKERS)
    processes = []
    try:
        for worker_id in range(WORKERS):
            process = context.Process(
                target=worker,
                args=(worker_id, ready, started + RUN_SECONDS),
            )
            process.start()
            processes.append(process)
        for process in processes:
            process.join(timeout=max(0, started + TIMEOUT_SECONDS - time.monotonic()))
            if process.is_alive():
                raise AssertionError("Memory-integrity worker timed out")
            if process.exitcode != 0:
                raise AssertionError(f"Memory-integrity worker exited {process.exitcode}")
    finally:
        for process in processes:
            if process.is_alive():
                process.kill()
        for process in processes:
            process.join(timeout=1)
    elapsed = time.monotonic() - started
    print(f"PASS: memory integrity verified; wall elapsed {elapsed:.2f}s", flush=True)


if __name__ == "__main__":
    main()
