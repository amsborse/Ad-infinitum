#!/usr/bin/env bash
# Run the 2026 Ad-infinitum GC policy experiment matrix.
#
# Compares Greedy, Cost-Benefit, and ATGC via mainline F2FS sysfs knobs
# (no kernel recompile required on modern kernels).
#
# Usage:
#   sudo ./tools/run-experiment.sh -d /mnt/f2fs -p greedy
#   sudo ./tools/run-experiment.sh -d /mnt/f2fs -p all -u 90

set -euo pipefail

MOUNT=""
POLICY="all"
UTIL=0
RUNS=3
RESULTS_DIR="benchmarks/results"

usage() {
	cat <<'EOF'
Usage: run-experiment.sh -d MOUNT [options]

Options:
  -d PATH    F2FS mount point (required)
  -p POLICY  greedy | cost-benefit | atgc | all (default: all)
  -u PCT     Pre-fill disk to PCT% utilization before test (0=skip)
  -r N       Repeat each config N times (default: 3)
  -h         Help

Example:
  sudo ./tools/run-experiment.sh -d /mnt/f2fs -p all -u 90 -r 5
EOF
}

while getopts "d:p:u:r:h" opt; do
	case "$opt" in
	d) MOUNT="$OPTARG" ;;
	p) POLICY="$OPTARG" ;;
	u) UTIL="$OPTARG" ;;
	r) RUNS="$OPTARG" ;;
	h) usage; exit 0 ;;
	*) usage; exit 1 ;;
	esac
done

[[ -n "$MOUNT" ]] || { echo "error: -d MOUNT required" >&2; exit 1; }
[[ $EUID -eq 0 ]] || { echo "error: run as root" >&2; exit 1; }

DEV=$(findmnt -T "$MOUNT" -n -o SOURCE)
SYSFS="/sys/fs/f2fs/$(basename "$DEV")"
[[ -d "$SYSFS" ]] || { echo "error: sysfs not found: $SYSFS" >&2; exit 1; }

mkdir -p "$RESULTS_DIR"
STAMP=$(date +%Y%m%d-%H%M%S)
LOG="$RESULTS_DIR/experiment-${STAMP}.log"

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

apply_policy() {
	local name="$1"
	log "Applying policy: $name"
	case "$name" in
	greedy)
		# gc_idle=2 → greedy BG; disable ATGC if present
		echo 2 > "$SYSFS/gc_idle" 2>/dev/null || true
		echo 0 > "$SYSFS/atgc_enabled" 2>/dev/null || true
		;;
	cost-benefit)
		echo 1 > "$SYSFS/gc_idle" 2>/dev/null || true
		echo 0 > "$SYSFS/atgc_enabled" 2>/dev/null || true
		;;
	atgc)
		echo 1 > "$SYSFS/gc_idle" 2>/dev/null || true
		echo 1 > "$SYSFS/atgc_enabled" 2>/dev/null || {
			log "warn: atgc_enabled not available on this kernel"
		}
		;;
	*) echo "unknown policy: $name" >&2; return 1 ;;
	esac
	# policy2 early-exit analogue: scan one segment at a time
	echo 1 > "$SYSFS/migration_window_granularity" 2>/dev/null || true
}

fill_disk() {
	local pct="$1"
	log "Pre-filling to ~${pct}% utilization..."
	local avail kb size fill
	avail=$(df -k "$MOUNT" | awk 'NR==2{print $4}')
	size=$(( avail * pct / (100 - pct) ))
	fill="$MOUNT/.fill-${STAMP}.bin"
	log "Writing ${size}KB to $fill"
	dd if=/dev/zero of="$fill" bs=1M count=$((size / 1024)) status=progress 2>&1 | tee -a "$LOG" || true
	sync
}

run_fio() {
	local tag="$1" run="$2"
	local out="$RESULTS_DIR/${STAMP}-${tag}-run${run}.json"
	log "fio run: $tag #$run → $out"
	fio benchmarks/fio/fsync-latency.fio \
		--directory="$MOUNT" \
		--output="$out" \
		--output-format=json 2>&1 | tee -a "$LOG"
}

POLICIES=()
case "$POLICY" in
all) POLICIES=(greedy cost-benefit atgc) ;;
*) POLICIES=("$POLICY") ;;
esac

log "=== Ad-infinitum Experiment Matrix 2026 ==="
log "Mount: $MOUNT  Device: $DEV  Runs: $RUNS"

[[ "$UTIL" -gt 0 ]] && fill_disk "$UTIL"

for pol in "${POLICIES[@]}"; do
	apply_policy "$pol"
	sleep 5
	for ((i=1; i<=RUNS; i++)); do
		run_fio "$pol" "$i"
	done
done

log "=== complete ==="
log "Results: $RESULTS_DIR/"
log "Analyze latency percentiles from JSON with: jq '.jobs[].read.clat_ns.percentile' $RESULTS_DIR/*.json"
