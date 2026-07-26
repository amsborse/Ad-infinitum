# Running Locally

Ad-infinitum has **three tiers** of local verification. On Windows, start with tier 1; F2FS experiments need tier 2 or 3.

---

## Tier 1 — Docs & landing page (works on Windows now)

No Linux, no kernel, no Docker required.

### Option A: Python (simplest)

```powershell
cd "d:\1 - Projects\log-structured\Ad-infinitum"
python -m http.server 8080 --directory docs
```

Open **http://localhost:8080** — you should see the 2026 landing page, hero image, simulator, and charts.

### Option B: Docker

```powershell
docker compose up --build docs
```

Same URL: **http://localhost:8080**

### Option C: Open file directly

Double-click `docs/index.html`. Most features work; some browsers restrict local file loading for Chart.js CDN (usually fine).

### Verify structure

```powershell
.\scripts\verify-local.ps1
```

---

## Tier 2 — F2FS lab smoke test (Docker + Linux kernel)

Runs a **512 MB loop-mounted F2FS filesystem** inside a privileged container and executes a short fio test.

**Requirements:**

- Docker Desktop (you have v29.x)
- WSL2 backend (Docker Desktop default on Windows)
- Host/WSL kernel with `CONFIG_F2FS_FS` (most Ubuntu WSL2 kernels have this)

```powershell
docker compose --profile lab run --rm lab
```

**Expected output:**

```
F2FS supported. Creating 512MB test filesystem...
Mounted F2FS at /mnt/f2fs-test
--- Smoke test: fio fsync (10s) ---
...
=== Lab smoke test PASSED ===
```

If F2FS is unavailable in the container kernel, the lab still verifies `fio` and tools are present and prints a warning.

---

## Tier 3 — Full kernel module build (WSL2 / Linux only)

Builds the historical **4.1.x-era** module from `fs/f2fs/`.

### WSL2 Ubuntu

```bash
# Inside WSL2
sudo apt install build-essential linux-headers-$(uname -r)
cd /mnt/d/1\ -\ Projects/log-structured/Ad-infinitum
make
# Produces fs/f2fs/f2fs.ko if headers match
```

> Note: The bundled sources target Linux **4.1.8** APIs. On a modern WSL kernel (6.x), the build will likely fail without porting. Use **Tier 2** for 2026 experiments instead.

### 2026 experiments on real F2FS (WSL2 or Linux)

Mount an F2FS partition (or loop device), then:

```bash
sudo ./tools/trace-gc.sh -d /mnt/f2fs -t 60
sudo ./tools/run-experiment.sh -d /mnt/f2fs -p all -u 90 -r 3
python3 tools/summarize-results.py
```

---

## What runs where?

| Component | Windows native | Docker `docs` | Docker `lab` | WSL2 / Linux |
|-----------|----------------|---------------|--------------|--------------|
| Landing page | ✅ | ✅ | — | ✅ |
| Interactive simulator | ✅ | ✅ | — | ✅ |
| fio benchmarks | ❌ | ❌ | ✅ | ✅ |
| F2FS mount + GC | ❌ | ⚠️ privileged | ✅ | ✅ |
| Kernel module build | ❌ | ❌ | ❌ | ⚠️ API mismatch |
| ftrace GC tracing | ❌ | ❌ | ⚠️ needs debugfs | ✅ |

---

## Troubleshooting

### Port 8080 in use

```powershell
python -m http.server 8888 --directory docs
# or change port in docker-compose.yml
```

### Docker lab: "F2FS not available"

The Docker Desktop VM kernel may lack F2FS. Options:

1. Run experiments in **WSL2 Ubuntu** directly (not Docker)
2. Enable F2FS in WSL kernel (advanced — custom WSL kernel build)

### `make` fails on WSL

Expected on modern kernels — the 2016 sources need API updates. The **2026 workflow uses mainline sysfs**, not this build.

---

## Recommended first check (30 seconds)

```powershell
.\scripts\verify-local.ps1
docker compose up --build docs
```

Then open **http://localhost:8080** and click through the simulator and experiment matrix.
