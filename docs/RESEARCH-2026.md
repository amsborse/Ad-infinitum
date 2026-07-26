# Ad-infinitum 2026 Research Program

> **Beyond Throughput: Latency-Aware Garbage Collection in Modern F2FS**  
> A continuation of the 2016 PICT survey, using mainline kernel infrastructure instead of forked `gc.c` patches.

---

## Executive Summary

The [2016 paper](https://www.ijtrd.com/papers/IJTRD3508.pdf) compared NILFS and F2FS cleaning policies using Compilebench **system time only**. It concluded that cost-benefit optimizes throughput but that **latency, write amplification, and tail behavior** need further study.

Ten years later, mainline F2FS provides:

- **Three GC policies** — Greedy, Cost-Benefit, and **ATGC** (Age-Threshold GC)
- **Sysfs tunables** — no kernel fork required for most experiments
- **Ftrace tracepoints** — structured observability replacing `printk`
- **Zoned-device support** — new constraints on cleaning

This document defines the **2026 methodology** to answer the questions we couldn't in 2015.

---

## 2016 → 2026: What Changed

| Dimension | 2016 approach | 2026 approach |
|-----------|---------------|---------------|
| Kernel | Linux 4.1.8 fork | Mainline 5.10+ with sysfs |
| Policies tested | Greedy (forced in code) | Greedy / CB / ATGC via sysfs |
| Observability | `printk(KERN_ERR, …)` | ftrace + `tools/trace-gc.sh` |
| Metrics | Compilebench system time | p99 fsync latency, IOPS, GC events |
| Latency fix | `policy2` early-exit patch | Patch reference + `migration_window_granularity` |
| Methodology | Ad-hoc policy edits | Controlled matrix (utilization × policy) |
| Reproducibility | Manual builds | `tools/run-experiment.sh` + fio jobs |

---

## Research Questions

1. **At 90–95% utilization**, which policy minimizes **p99 fsync latency**?
2. Does **ATGC** reduce background GC duty cycle vs Cost-Benefit (as [Huawei reported](https://lwn.net/Articles/825443/))?
3. Is the 2016 **`policy2` early-exit** equivalent to `migration_window_granularity=1` on modern kernels?
4. How does **write amplification** scale across policies under sustained random write?
5. On **zoned NVMe**, do `gc_boost_zoned_gc_percent` thresholds prevent FG_GC storms?

---

## Experiment Matrix

See [`benchmarks/experiment-matrix.yaml`](../benchmarks/experiment-matrix.yaml).

```
              │ Greedy      │ Cost-Benefit │ ATGC        │
──────────────┼─────────────┼──────────────┼─────────────│
 50% full     │ fio + trace │ fio + trace  │ fio + trace │
 75% full     │     …       │      …       │      …      │
 90% full     │     …       │      …       │      …      │
 95% full     │     …       │      …       │      …      │
```

**Controls:** 5 repeats per cell, sync between runs, same hardware, same fill pattern.

---

## Sysfs Policy Mapping

| Policy | `gc_idle` | `atgc_enabled` | FG behavior |
|--------|-----------|----------------|-------------|
| Greedy | `2` | `0` | min valid blocks |
| Cost-Benefit | `1` | `0` | utilization × age |
| ATGC | `1` | `1` | age-threshold + SSR target |

Additional knobs ([kernel ABI docs](https://github.com/torvalds/linux/blob/master/Documentation/ABI/testing/sysfs-fs-f2fs)):

| Knob | Purpose |
|------|---------|
| `migration_window_granularity` | Segments scanned per FG GC turn (policy2 analogue) |
| `gc_valid_thresh_ratio` | Skip high-validity sections (zoned) |
| `gc_boost_zoned_gc_percent` | Boost BG GC when free space low |
| `gc_urgent_sleep_time` | BG thread cadence under pressure |

---

## Tools

```bash
# 1. Trace GC (replaces printk-1 branch)
sudo ./tools/trace-gc.sh -d /mnt/f2fs -t 120 -o /tmp/gc.trace

# 2. Run full experiment matrix
sudo ./tools/run-experiment.sh -d /mnt/f2fs -p all -u 90 -r 5

# 3. Summarize fio JSON results
python3 tools/summarize-results.py
```

### Requirements

- Linux 5.10+ with F2FS and `CONFIG_F2FS_FS`, debugfs, ftrace
- `fio` >= 3.0
- Root access for sysfs and tracing
- Optional: NVMe or USB SSD with F2FS formatted partition

---

## Metrics (2016 gaps filled)

| Metric | Tool | Target |
|--------|------|--------|
| p50/p95/p99 fsync latency | `benchmarks/fio/fsync-latency.fio` | Primary — tail latency |
| Random write IOPS @ 90% full | `benchmarks/fio/random-write-gc.fio` | Throughput under pressure |
| Compile workload time | `benchmarks/fio/compile-workload.fio` | Paper-compatible comparison |
| GC event count | `tools/trace-gc.sh` | Background GC duty cycle |
| Write amplification | debugfs / `iostat` | Flash endurance impact |

---

## Historical Code Branches

The reorganized repo preserves 2016 research under `fs/f2fs/` (Linux 4.1.8 baseline):

| Branch | Content |
|--------|---------|
| `master` | Stock GC |
| `origin/policy2` | FG_GC early-exit (see `patches/policy2-fg-gc-early-exit.reference.patch`) |
| `origin/printk-1` | printk instrumentation |

**2026 work does not require these branches** for policy comparison — use sysfs on a modern kernel instead.

---

## Expected Outcomes

Based on upstream ATGC reports and our 2016 findings, we hypothesize:

1. **Greedy** wins on p99 fsync at high utilization (FG_GC path)
2. **ATGC** reduces BG GC calls and block migrations vs pure Cost-Benefit
3. **Compilebench-style throughput** remains F2FS > NILFS (confirmed 2016)
4. **`migration_window_granularity=1`** reproduces most of policy2 benefit without patching

Results land in `benchmarks/results/*.json` and feed the interactive dashboard at [`docs/index.html`](index.html).

---

## Publication Target

**Working title:** *Beyond Throughput: Latency-Aware Garbage Collection Policies in Modern F2FS*

**Authors:** Borse, Marathe, et al. (PICT lineage + 2026 contributors)

**Venue options:** USENIX ATC Fast Track, ACM SYSTOR, IEEE ICMDM, or extended tech report

---

## References

1. Marathe et al., *Survey of Cleaning Policies in LFS*, IJTRD 2016 — [PDF](https://www.ijtrd.com/papers/IJTRD3508.pdf)
2. Chao Yu, *ATGC for F2FS*, LWN 2020 — [Article](https://lwn.net/Articles/825443/)
3. Daeho Jeong, *Zoned F2FS GC sysfs*, Linux kernel 2024
4. Lee et al., *F2FS: A New File System for Flash Storage*, USENIX FAST 2015
5. F2FS sysfs ABI — [Documentation/ABI/testing/sysfs-fs-f2fs](https://github.com/torvalds/linux/blob/master/Documentation/ABI/testing/sysfs-fs-f2fs)
