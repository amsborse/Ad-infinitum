#!/usr/bin/env bash
# Trace F2FS garbage collection using kernel ftrace (replaces 2016 printk approach).
#
# Requirements: root, mounted F2FS, debugfs, ftrace enabled
#
# Usage:
#   sudo ./tools/trace-gc.sh                  # trace for 60s
#   sudo ./tools/trace-gc.sh -d /mnt/f2fs -t 120 -o /tmp/gc-trace.txt

set -euo pipefail

DURATION=60
MOUNT=""
OUTPUT=""
TRACE_DIR="/sys/kernel/debug/tracing"

usage() {
	cat <<'EOF'
Usage: trace-gc.sh [options]

Options:
  -d PATH    F2FS mount point (auto-detect if omitted)
  -t SEC     Trace duration (default: 60)
  -o FILE    Write trace output to FILE
  -h         Help

Captures f2fs tracepoints: gc events, block I/O, checkpoint.
EOF
}

while getopts "d:t:o:h" opt; do
	case "$opt" in
	d) MOUNT="$OPTARG" ;;
	t) DURATION="$OPTARG" ;;
	o) OUTPUT="$OPTARG" ;;
	h) usage; exit 0 ;;
	*) usage; exit 1 ;;
	esac
done

if [[ $EUID -ne 0 ]]; then
	echo "error: run as root" >&2
	exit 1
fi

if [[ ! -d "$TRACE_DIR" ]]; then
	echo "error: debugfs tracing not available at $TRACE_DIR" >&2
	exit 1
fi

if [[ -z "$MOUNT" ]]; then
	MOUNT=$(findmnt -t f2fs -n -o TARGET 2>/dev/null | head -1 || true)
fi

echo "=== Ad-infinitum GC Trace (2026) ==="
echo "Mount:  ${MOUNT:-not found}"
echo "Duration: ${DURATION}s"
echo ""

# Snapshot sysfs GC policy state
if [[ -n "$MOUNT" ]]; then
	DEV=$(findmnt -T "$MOUNT" -n -o SOURCE)
	SYSFS="/sys/fs/f2fs/$(basename "$DEV")"
	if [[ -d "$SYSFS" ]]; then
		echo "--- sysfs policy state ---"
		for knob in gc_idle atgc_enabled migration_window_granularity \
			gc_valid_thresh_ratio gc_urgent_sleep_time; do
			if [[ -f "$SYSFS/$knob" ]]; then
				printf "  %-30s %s\n" "$knob" "$(cat "$SYSFS/$knob" 2>/dev/null || echo n/a)"
			fi
		done
		echo ""
	fi
fi

echo "--- enabling f2fs tracepoints ---"
echo 0 > "$TRACE_DIR/tracing_on"
echo nop > "$TRACE_DIR/current_tracer"
echo > "$TRACE_DIR/trace"
echo 1 > "$TRACE_DIR/events/f2fs/enable" 2>/dev/null || {
	echo "warn: f2fs tracepoints unavailable; falling back to kprobe on f2fs_gc"
	echo 'p:f2fs_gc f2fs_gc' >> "$TRACE_DIR/kprobe_events" 2>/dev/null || true
}
echo 1 > "$TRACE_DIR/tracing_on"

echo "tracing... (${DURATION}s)"
sleep "$DURATION"

echo 0 > "$TRACE_DIR/tracing_on"
echo 0 > "$TRACE_DIR/events/f2fs/enable" 2>/dev/null || true

TRACE_OUT=$(cat "$TRACE_DIR/trace")

if [[ -n "$OUTPUT" ]]; then
	echo "$TRACE_OUT" > "$OUTPUT"
	echo "written: $OUTPUT"
else
	echo "--- trace excerpt (last 40 lines) ---"
	echo "$TRACE_OUT" | tail -40
fi

GC_COUNT=$(echo "$TRACE_OUT" | grep -c -E 'f2fs.*gc|garbage' || true)
echo ""
echo "GC-related trace lines: $GC_COUNT"
