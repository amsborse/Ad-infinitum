#!/usr/bin/env bash
# Bootstraps a loop-mounted F2FS filesystem and runs a smoke test.
set -euo pipefail

MOUNT="${MOUNT:-/mnt/f2fs-test}"
IMG="/tmp/f2fs-test.img"
SIZE_MB=512

echo "=== Ad-infinitum Lab Container ==="
echo "Kernel: $(uname -r)"
echo ""

# Check F2FS kernel support
if ! grep -q f2fs /proc/filesystems; then
	# try loading module
	modprobe f2fs 2>/dev/null || true
fi

if ! grep -q f2fs /proc/filesystems; then
	echo "WARN: F2FS not available in this kernel."
	echo "      Docs site works without F2FS. Full GC experiments need Linux with CONFIG_F2FS_FS."
	echo ""
	echo "Smoke test (tools only):"
	python3 --version
	fio --version
	[[ -x /workspace/tools/trace-gc.sh ]] && echo "trace-gc.sh: OK" || echo "trace-gc.sh: missing"
	exit 0
fi

echo "F2FS supported. Creating ${SIZE_MB}MB test filesystem..."
mkdir -p "$MOUNT"
truncate -s "${SIZE_MB}M" "$IMG"
mkfs.f2fs -f "$IMG" > /dev/null
mount -t f2fs -o loop "$IMG" "$MOUNT"
echo "Mounted F2FS at $MOUNT"
df -h "$MOUNT"
echo ""

echo "--- Smoke test: fio fsync (10s) ---"
fio /workspace/benchmarks/fio/fsync-latency.fio \
	--directory="$MOUNT" \
	--runtime=10 \
	--output-format=normal

echo ""
echo "--- Smoke test: trace-gc.sh (5s) ---"
if [[ -d /sys/kernel/debug/tracing ]]; then
	/workspace/tools/trace-gc.sh -d "$MOUNT" -t 5 || true
else
	echo "ftrace not available (need debugfs mounted) — skipping trace"
fi

echo ""
echo "=== Lab smoke test PASSED ==="
echo "Run full matrix: docker compose --profile lab run --rm lab /workspace/tools/run-experiment.sh -d $MOUNT -p greedy -u 0 -r 1"

# Keep container alive if no args
if [[ $# -gt 0 ]]; then
	exec "$@"
else
	echo "Container ready. Mount at $MOUNT"
	sleep infinity
fi
