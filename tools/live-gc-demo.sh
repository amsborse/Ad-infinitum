#!/usr/bin/env bash
# Real F2FS GC demo — emits JSON events on stdout prefixed with EVENT:
# Usage: sudo ./tools/live-gc-demo.sh [utilization_pct] [policy]
# Requires: f2fs kernel support, root, f2fs-tools, fio

set -euo pipefail

UTIL="${1:-75}"
POLICY="${2:-greedy}"
MOUNT="/tmp/ad-infinitum-f2fs"
IMG="/tmp/ad-infinitum-f2fs.img"
SIZE_MB=256

event() {
	printf 'EVENT:%s\n' "$(python3 -c "import json,sys; print(json.dumps(json.loads(sys.argv[1])))" "$1")"
}

cleanup() {
	umount "$MOUNT" 2>/dev/null || true
}
trap cleanup EXIT

modprobe f2fs 2>/dev/null || true
if ! grep -q f2fs /proc/filesystems; then
	echo "F2FS not supported in this kernel"
	exit 1
fi

mkdir -p "$MOUNT"
truncate -s "${SIZE_MB}M" "$IMG"
mkfs.f2fs -f "$IMG" 2>/dev/null
mount -t f2fs -o loop "$IMG" "$MOUNT"

event "{\"type\":\"gc_thread_wake\",\"gc_type\":\"BG_GC\",\"policy\":\"$POLICY\",\"message\":\"Real F2FS mounted at $MOUNT\"}"

# Fill disk to target utilization
FILL_KB=$(( SIZE_MB * 1024 * UTIL / 100 ))
if [[ "$FILL_KB" -gt 0 ]]; then
	dd if=/dev/zero of="$MOUNT/fill.bin" bs=1K count="$FILL_KB" 2>/dev/null || true
	sync
fi

event "{\"type\":\"victim_select\",\"policy\":\"$POLICY\",\"message\":\"Running fio to trigger GC pressure on real F2FS\"}"

# Short fio run to trigger cleaning
fio --name=gc-pressure --directory="$MOUNT" --rw=randwrite --bs=4k \
	--size=32m --numjobs=1 --time_based --runtime=15 --ioengine=sync \
	--output-format=normal 2>&1 | while read -r line; do
	event "{\"type\":\"real_log\",\"message\":$(python3 -c "import json; print(json.dumps('$line'))")}"
done || true

# Read GC stats from debugfs if available
if [[ -d /sys/kernel/debug/f2fs ]]; then
	for dev in /sys/kernel/debug/f2fs/*/; do
		[[ -f "${dev}gc" ]] && cat "${dev}gc" 2>/dev/null | head -5 | while read -r line; do
			event "{\"type\":\"scan_sit\",\"message\":\"debugfs: $line\"}"
		done
	done
fi

event "{\"type\":\"gc_complete\",\"message\":\"Real F2FS GC demo cycle finished\",\"utilization\":$UTIL}"
