#!/usr/bin/env python3
"""Summarize fio JSON results from benchmarks/results/ into a comparison table."""

import json
import sys
from pathlib import Path

RESULTS = Path(__file__).resolve().parent.parent / "benchmarks" / "results"


def pct(job, key="write"):
    clat = job.get(key, {}).get("clat_ns", {})
    p = clat.get("percentile", {})
    return {
        "p50_us": p.get("50.000000", 0) / 1000,
        "p95_us": p.get("95.000000", 0) / 1000,
        "p99_us": p.get("99.000000", 0) / 1000,
        "mean_us": clat.get("mean", 0) / 1000,
        "iops": job.get(key, {}).get("iops", 0),
    }


def main():
    files = sorted(RESULTS.glob("*.json"))
    if not files:
        print("No JSON results in benchmarks/results/", file=sys.stderr)
        print("Run: sudo ./tools/run-experiment.sh -d /mnt/f2fs", file=sys.stderr)
        sys.exit(1)

    print(f"{'File':<45} {'p50 µs':>10} {'p95 µs':>10} {'p99 µs':>10} {'IOPS':>10}")
    print("-" * 90)

    for f in files:
        data = json.loads(f.read_text())
        for job in data.get("jobs", []):
            s = pct(job)
            label = f.name.replace(".json", "")
            print(
                f"{label:<45} {s['p50_us']:>10.1f} {s['p95_us']:>10.1f} "
                f"{s['p99_us']:>10.1f} {s['iops']:>10.1f}"
            )


if __name__ == "__main__":
    main()
