#!/usr/bin/env bash
# Verify Ad-infinitum can run locally (Linux / macOS / WSL)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo ""
echo "=== Ad-infinitum Local Verification ==="
PASS=0 FAIL=0

check() {
	if [[ -e "$1" ]]; then
		echo "[OK]   $2"
		PASS=$((PASS+1))
	else
		echo "[FAIL] $2 — missing: $1"
		FAIL=$((FAIL+1))
	fi
}

check docs/index.html "Landing page"
check docs/assets/hero-2026.png "Hero image"
check fs/f2fs/gc.c "Kernel sources"
check tools/run-experiment.sh "Experiment runner"
check docker-compose.yml "Docker Compose"

command -v docker >/dev/null && echo "[OK]   Docker: $(docker --version)" && PASS=$((PASS+1)) || echo "[SKIP] Docker not installed"
grep -q f2fs /proc/filesystems 2>/dev/null && echo "[OK]   F2FS in kernel" && PASS=$((PASS+1)) || echo "[INFO] F2FS not in kernel (use lab container or enable module)"
command -v fio >/dev/null && echo "[OK]   fio installed" && PASS=$((PASS+1)) || echo "[INFO] fio not installed (lab container has it)"

echo ""
echo "--- Quick start ---"
echo "  Docs:     docker compose up docs     → http://localhost:8080"
echo "  Lab:      docker compose --profile lab run --rm lab"
echo "  Module:   make                         (needs kernel headers)"
echo ""

[[ $FAIL -eq 0 ]] && echo "Project structure: OK ($PASS checks passed)" || echo "Project structure: $FAIL issue(s)"
