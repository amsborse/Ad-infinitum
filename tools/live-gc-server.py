#!/usr/bin/env python3
"""
Live F2FS garbage-collection demo — 3 policies in parallel.

Usage:
  python tools/live-gc-server.py

Open: http://localhost:8765/live.html
"""

from __future__ import annotations

import argparse
import json
import os
import queue
import random
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from copy import deepcopy
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
PORT = int(os.environ.get("LIVE_GC_PORT", "8765"))

POLICIES = ("greedy", "cost-benefit", "atgc")

# Slow timing (seconds) — easy to follow visually
PAUSE = {
    "wake": 1.4,
    "victim": 1.6,
    "scan": 1.2,
    "migrate": 0.55,
    "checkpoint": 1.0,
    "free": 0.8,
    "between_rounds": 2.0,
}

subscribers: list[queue.Queue] = []
sub_lock = threading.Lock()
arena_lock = threading.Lock()


class LaneState:
    def __init__(self, policy: str) -> None:
        self.policy = policy
        self.segments = 16
        self.valid_blocks = [5] * 16
        self.ages = [50] * 16
        self.cycles = 0
        self.blocks_freed = 0
        self.blocks_migrated = 0
        self.performance = 100
        # Live / per-round metrics
        self.round_freed = 0
        self.round_migrated = 0
        self.last_cycle_ms = 0
        self.clean_speed = 0.0  # blocks freed per second (last completed cycle)
        self.fg_cycles = 0
        self.bg_cycles = 0
        self.current_gc_type = "BG_GC"
        self._cycle_started_at = 0.0
        self.speed_history: list[float] = []

    def load_snapshot(self, valid: list[int], ages: list[int]) -> None:
        self.valid_blocks = deepcopy(valid)
        self.ages = deepcopy(ages)

    def reset_metrics(self) -> None:
        self.cycles = 0
        self.blocks_freed = 0
        self.blocks_migrated = 0
        self.performance = 100
        self.round_freed = 0
        self.round_migrated = 0
        self.last_cycle_ms = 0
        self.clean_speed = 0.0
        self.fg_cycles = 0
        self.bg_cycles = 0
        self.speed_history = []

    def metrics_dict(self) -> dict:
        wa = round(self.blocks_migrated / max(1, self.blocks_freed), 2)
        avg_freed = round(self.blocks_freed / max(1, self.cycles), 1)
        return {
            "blocks_freed_total": self.blocks_freed,
            "blocks_freed_round": self.round_freed,
            "blocks_migrated_total": self.blocks_migrated,
            "blocks_migrated_round": self.round_migrated,
            "clean_speed": round(self.clean_speed, 2),
            "cycle_ms": self.last_cycle_ms,
            "cycles": self.cycles,
            "fg_cycles": self.fg_cycles,
            "bg_cycles": self.bg_cycles,
            "performance": self.performance,
            "gc_type": self.current_gc_type,
            "write_amplification": wa,
            "avg_blocks_per_cycle": avg_freed,
            "speed_history": self.speed_history[-12:],
        }


class Arena:
    def __init__(self) -> None:
        self.running = False
        self.utilization = 72
        self.lanes = {p: LaneState(p) for p in POLICIES}
        self.round_num = 0
        self.session_started_at = time.time()
        self._seed_disk()

    def _seed_disk(self) -> None:
        random.seed(42)
        ratio = self.utilization / 100.0
        valid = [
            random.randint(0, 2) if random.random() < ratio else random.randint(4, 9)
            for _ in range(16)
        ]
        ages = [random.randint(15, 95) for _ in range(16)]
        for lane in self.lanes.values():
            lane.load_snapshot(valid, ages)
            lane.reset_metrics()

    def reset(self, utilization: int) -> None:
        self.utilization = utilization
        self.round_num = 0
        self.session_started_at = time.time()
        self._seed_disk()

    def snapshot(self) -> tuple[list[int], list[int]]:
        lane = self.lanes["greedy"]
        return deepcopy(lane.valid_blocks), deepcopy(lane.ages)

    def apply_write_pressure(self) -> None:
        with arena_lock:
            for lane in self.lanes.values():
                for i in range(len(lane.valid_blocks)):
                    if random.random() < 0.18:
                        lane.valid_blocks[i] = min(9, lane.valid_blocks[i] + 1)
            self.utilization = min(98, self.utilization + random.randint(0, 2))


arena = Arena()


def emit(event: dict) -> None:
    event["ts"] = time.time()
    with sub_lock:
        for q in subscribers:
            try:
                q.put_nowait(event)
            except queue.Full:
                pass


def emit_metrics(policy: str, stage: str = "") -> None:
    with arena_lock:
        lane = arena.lanes[policy]
        m = lane.metrics_dict()
        util = arena.utilization
        rnd = arena.round_num
    emit({
        "type": "metrics",
        "policy": policy,
        "stage": stage,
        "round": rnd,
        "utilization": util,
        **m,
    })


def emit_all_metrics(stage: str = "") -> None:
    for policy in POLICIES:
        emit_metrics(policy, stage)
    with arena_lock:
        total_freed = sum(l.blocks_freed for l in arena.lanes.values())
        total_migrated = sum(l.blocks_migrated for l in arena.lanes.values())
        elapsed = time.time() - arena.session_started_at
    emit({
        "type": "metrics_global",
        "stage": stage,
        "round": arena.round_num,
        "utilization": arena.utilization,
        "total_blocks_freed": total_freed,
        "total_blocks_migrated": total_migrated,
        "session_elapsed_s": round(elapsed, 1),
        "aggregate_clean_speed": round(total_freed / max(0.1, elapsed), 2),
    })


def pick_victim(valid: list[int], ages: list[int], policy: str) -> int:
    best, best_score = 0, float("inf")
    for i, (v, age) in enumerate(zip(valid, ages)):
        if v == 0:
            continue
        if policy == "greedy":
            s = float(v)
        elif policy == "atgc":
            s = v * 0.4 if age > 55 else 800.0
        else:
            s = (100 - v * 10) * age / (100 + v * 10)
        if s < best_score:
            best_score, best = s, i
    return best


def run_lane_round(
    policy: str,
    round_num: int,
    util: int,
    base_valid: list[int],
    base_ages: list[int],
) -> dict:
    """One full GC cycle for a single policy (runs in its own thread)."""
    valid = deepcopy(base_valid)
    ages = deepcopy(base_ages)
    gc_type = "FG_GC" if util >= 88 else "BG_GC"
    active = "greedy" if gc_type == "FG_GC" and policy == "cost-benefit" else policy

    with arena_lock:
        lane = arena.lanes[policy]
        lane.round_freed = 0
        lane.round_migrated = 0
        lane.current_gc_type = gc_type
        lane._cycle_started_at = time.time()

    emit({"type": "gc_thread_wake", "policy": policy, "gc_type": gc_type,
          "round": round_num, "utilization": util,
          "message": f"{policy}: cleanup started ({gc_type})"})
    emit_metrics(policy, "wake")
    time.sleep(PAUSE["wake"])

    victim = pick_victim(valid, ages, active)
    vbefore = valid[victim]

    emit({"type": "victim_select", "policy": policy, "segment": victim,
          "section": victim // 4, "valid_blocks": vbefore, "active_policy": active,
          "round": round_num,
          "message": f"{policy}: picked chunk {victim} ({vbefore} good blocks inside)"})
    time.sleep(PAUSE["victim"])

    emit({"type": "scan_sit", "policy": policy, "segment": victim, "round": round_num,
          "message": f"{policy}: scanning chunk {victim} for still-needed data"})
    time.sleep(PAUSE["scan"])

    migrated = max(0, vbefore - random.randint(0, 1))
    for blk in range(migrated):
        with arena_lock:
            arena.lanes[policy].round_migrated += 1
        emit({"type": "migrate_valid", "policy": policy, "segment": victim, "block": blk,
              "round": round_num,
              "message": f"{policy}: copying good block {blk + 1} to fresh space"})
        emit_metrics(policy, "migrate")
        time.sleep(PAUSE["migrate"])

    emit({"type": "checkpoint", "policy": policy, "round": round_num,
          "message": f"{policy}: saving checkpoint (crash-safe bookmark)"})
    time.sleep(PAUSE["checkpoint"])

    valid[victim] = 0
    freed = vbefore

    with arena_lock:
        arena.lanes[policy].round_freed = freed

    emit({"type": "section_free", "policy": policy, "section": victim // 4,
          "segment": victim, "round": round_num,
          "message": f"{policy}: chunk {victim} is now EMPTY — {freed} blocks freed"})
    emit_metrics(policy, "free")
    time.sleep(PAUSE["free"])

    tick_cost = {"greedy": 3, "cost-benefit": 5, "atgc": 4}[active]
    if gc_type == "FG_GC":
        tick_cost += 4

    with arena_lock:
        lane = arena.lanes[policy]
        started_at = lane._cycle_started_at

    cycle_ms = int((time.time() - started_at) * 1000)

    with arena_lock:
        lane = arena.lanes[policy]
        lane.valid_blocks = deepcopy(valid)
        lane.blocks_migrated += migrated
        lane.blocks_freed += freed
        lane.performance = max(10, lane.performance - tick_cost + (freed // 2))
        lane.cycles += 1
        if gc_type == "FG_GC":
            lane.fg_cycles += 1
        else:
            lane.bg_cycles += 1
        lane.last_cycle_ms = cycle_ms
        lane.clean_speed = round(freed / max(0.001, cycle_ms / 1000), 2)
        lane.speed_history.append(lane.clean_speed)
        perf = lane.performance
        total_freed = lane.blocks_freed
        total_migrated = lane.blocks_migrated
        cycles = lane.cycles
        clean_speed = lane.clean_speed

    emit({
        "type": "gc_complete", "policy": policy, "gc_type": gc_type,
        "round": round_num, "migrated": migrated, "freed": freed, "segment": victim,
        "segments": list(valid), "utilization": util,
        "cycles": cycles, "blocks_freed": total_freed, "blocks_migrated": total_migrated,
        "performance": perf, "cycle_ms": cycle_ms, "clean_speed": clean_speed,
        "message": f"{policy}: done — freed {freed} blocks in {cycle_ms}ms ({clean_speed} blk/s)",
    })
    emit_metrics(policy, "complete")
    return {"freed": freed, "performance": perf, "clean_speed": clean_speed}


def run_parallel_round(round_num: int, util: int) -> None:
    """Start the same disk snapshot; run all 3 policy simulators concurrently."""
    with arena_lock:
        arena.round_num = round_num
        for lane in arena.lanes.values():
            lane.round_freed = 0
            lane.round_migrated = 0

    base_valid, base_ages = arena.snapshot()

    emit({
        "type": "round_start", "round": round_num, "utilization": util,
        "segments": list(base_valid),
        "message": f"Round {round_num}: all 3 strategies start with the SAME messy drive ({util}% full)",
    })
    emit_all_metrics("round_start")
    time.sleep(0.8)

    results: dict[str, dict] = {}
    with ThreadPoolExecutor(max_workers=3, thread_name_prefix="gc-lane") as pool:
        futures = {
            pool.submit(run_lane_round, policy, round_num, util, base_valid, base_ages): policy
            for policy in POLICIES
        }
        for fut in as_completed(futures):
            policy = futures[fut]
            results[policy] = fut.result()

    ranked = sorted(POLICIES, key=lambda p: arena.lanes[p].performance, reverse=True)
    speeds = {p: arena.lanes[p].clean_speed for p in POLICIES}
    emit({
        "type": "comparison",
        "round": round_num,
        "ranking": ranked,
        "scores": {p: arena.lanes[p].performance for p in POLICIES},
        "freed": {p: results[p]["freed"] for p in POLICIES},
        "clean_speed": speeds,
        "message": f"Round {round_num} winner: {ranked[0]} ({speeds[ranked[0]]} blk/s clean speed)",
    })
    emit_all_metrics("comparison")


def simulation_loop() -> None:
    round_num = 0
    while True:
        if not arena.running:
            time.sleep(0.3)
            continue

        round_num += 1
        util = arena.utilization
        run_parallel_round(round_num, util)
        arena.apply_write_pressure()
        time.sleep(PAUSE["between_rounds"])


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:
        pass

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path in ("/", "/live.html"):
            self._file(DOCS / "live.html", "text/html; charset=utf-8")
        elif path.startswith("/assets/"):
            self._file(DOCS / path.lstrip("/"), "image/png" if path.endswith(".png") else "application/octet-stream")
        elif path == "/events":
            self._sse()
        elif path == "/status":
            with arena_lock:
                elapsed = time.time() - arena.session_started_at
                total_freed = sum(l.blocks_freed for l in arena.lanes.values())
                lanes_out = {
                    p: {"policy": p, **arena.lanes[p].metrics_dict(),
                        "segments": arena.lanes[p].valid_blocks}
                    for p in POLICIES
                }
            self._json({
                "running": arena.running,
                "utilization": arena.utilization,
                "round": arena.round_num,
                "mode": "simulation-parallel",
                "session_elapsed_s": round(elapsed, 1),
                "total_blocks_freed": total_freed,
                "aggregate_clean_speed": round(total_freed / max(0.1, elapsed), 2),
                "lanes": lanes_out,
            })
        else:
            self.send_error(404)

    def do_POST(self) -> None:
        path = urlparse(self.path).path
        n = int(self.headers.get("Content-Length", 0))
        try:
            data = json.loads(self.rfile.read(n) if n else b"{}")
        except json.JSONDecodeError:
            data = {}
        if path == "/start":
            arena.reset(int(data.get("utilization", 72)))
            arena.running = True
            self._json({"ok": True})
        elif path == "/stop":
            arena.running = False
            self._json({"ok": True})
        elif path == "/config":
            if "utilization" in data:
                arena.utilization = int(data["utilization"])
            self._json({"ok": True})
        else:
            self.send_error(404)

    def _file(self, fp: Path, ctype: str) -> None:
        if not fp.is_file():
            self.send_error(404)
            return
        body = fp.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(body)

    def _json(self, obj: dict) -> None:
        body = json.dumps(obj).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def _sse(self) -> None:
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        q: queue.Queue = queue.Queue(maxsize=400)
        with sub_lock:
            subscribers.append(q)
        try:
            while True:
                try:
                    ev = q.get(timeout=15)
                    self.wfile.write(f"data: {json.dumps(ev)}\n\n".encode())
                    self.wfile.flush()
                except queue.Empty:
                    self.wfile.write(b": ping\n\n")
                    self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            with sub_lock:
                if q in subscribers:
                    subscribers.remove(q)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=PORT)
    args = ap.parse_args()

    threading.Thread(target=simulation_loop, daemon=True).start()
    arena.running = True

    srv = ThreadingHTTPServer(("0.0.0.0", args.port), Handler)
    srv.mode = "simulation-parallel"  # type: ignore[attr-defined]
    print(f"\n  Live F2FS GC (3-policy parallel) -> http://localhost:{args.port}/live.html\n")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        arena.running = False


if __name__ == "__main__":
    main()
