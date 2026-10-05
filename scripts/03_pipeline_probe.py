#!/usr/bin/env python3
"""ARUGA full pipeline probe — Layers D-J (read-only).

Runs real camera frames through the canonical ARUGA pipeline and reports
per-layer results. Uses the production repo's core modules unmodified.

Credentials from env (never printed):
  ARUGA_CAM_IP, ARUGA_CAM_USER, ARUGA_CAM_PASS, ARUGA_CAM_STREAM (opt)

Usage:
  python3 03_pipeline_probe.py [--seconds 30]

Layers verified:
  D FramePump | E HallwayManager | F YOLO inference | G tracking
  H fall/inactivity | I risk/HUD | J clean shutdown
"""

import argparse
import os
import sys
import time

ARUGA_ROOT = "/home/joal/Projects/ARUGA-fall-detection-and-inactivity-monitoring-system"
sys.path.insert(0, ARUGA_ROOT)
os.chdir(ARUGA_ROOT)  # model paths resolve from the production repo root


def fail(layer, msg):
    print(f"[FAIL] {layer}: {msg}")
    sys.exit(1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seconds", type=float, default=30.0)
    args = ap.parse_args()

    ip = os.environ.get("ARUGA_CAM_IP", "")
    user = os.environ.get("ARUGA_CAM_USER", "")
    pw = os.environ.get("ARUGA_CAM_PASS", "")
    stream = os.environ.get("ARUGA_CAM_STREAM", "stream2")
    if not (ip and user and pw):
        fail("config", "set ARUGA_CAM_IP / ARUGA_CAM_USER / ARUGA_CAM_PASS")

    import cv2
    import numpy as np
    from urllib.parse import quote

    from core.camera_sources import build_tapo_rtsp_url
    from core.frame_pump import FramePump, SourceLost
    from core.hallway_manager import HallwayManager
    from utils.hallway_overlay import draw_hallway_hud, worst_risk

    url = build_tapo_rtsp_url(ip, user, pw, stream)
    print(f"target: rtsp://<redacted>@{ip}:554/{stream}")

    # D — FramePump
    try:
        pump = FramePump(url, on_status=lambda m: print(f"[pump] {m}"))
    except SourceLost as e:
        fail("D FramePump", f"cannot open stream: {e}")
    print("[PASS] D FramePump: stream open")

    try:
        mgr = HallwayManager()
    except Exception as e:
        pump.release()
        fail("E/F HallwayManager+YOLO init", str(e))
    print(f"[PASS] E/F init: HallwayManager + YOLO backend ({mgr.backend.backend_name})")

    frames = 0
    processed = 0
    max_persons = 0
    id_sets = []
    saw_fall = saw_inactive = False
    hud_ok = False
    t0 = time.time()
    try:
        while time.time() - t0 < args.seconds:
            try:
                frame = pump.read()
            except SourceLost as e:
                print(f"[WARN] stream lost after {frames} frames: {e}")
                break
            if frame is None:
                continue
            frames += 1
            if not (isinstance(frame, np.ndarray) and frame.ndim == 3
                    and frame.shape[2] == 3 and frame.dtype == np.uint8):
                fail("C frames", f"unexpected frame type {type(frame)} {getattr(frame, 'shape', None)}")

            persons = mgr.process(frame, current_time=time.time())
            processed += 1
            max_persons = max(max_persons, len(persons))
            id_sets.append(sorted(p["track_id"] for p in persons))
            for p in persons:
                if p["fall_status"]["state"] in ("PRE_FALL", "FALLEN", "INACTIVE_ALERT"):
                    saw_fall = True
                if p["inactivity_status"]["is_inactive_alert"]:
                    saw_inactive = True

            disp = draw_hallway_hud(frame, persons, show_skeleton=True, show_bbox=True,
                                    extra_status=f"{len(persons)} tracked",
                                    lost_alarms=mgr.lost_alarms)
            if isinstance(disp, np.ndarray) and disp.shape == frame.shape:
                hud_ok = True

            if processed % 50 == 0:
                w = worst_risk(persons) if persons else "NONE"
                print(f"   frames={processed} persons={len(persons)} worst_risk={w}")
    finally:
        pump.release()          # J
        print("[PASS] J clean shutdown: pump released")

    stable = len(id_sets) > 3 and all(s == id_sets[3] for s in id_sets[3:])

    print()
    print("=== CHECKLIST ===")
    print(f"  D FramePump frames:        {'PASS' if frames else 'FAIL'} ({frames} read)")
    print(f"  E HallwayManager process:  {'PASS' if processed else 'FAIL'} ({processed} frames)")
    print(f"  F YOLO inference:          {'PASS' if processed else 'FAIL'}")
    print(f"  G person tracking:         {'PASS ' + str(max_persons) + ' max' if max_persons else 'NONE OBSERVED (person in view?)'}"
          f" stable_ids={'yes' if stable else 'insufficient/changed'}")
    print(f"  H fall/inactivity:         fall={'seen' if saw_fall else 'not observed'}"
          f" inactivity={'seen' if saw_inactive else 'not observed'}")
    print(f"  I risk/HUD rendering:      {'PASS' if hud_ok else 'FAIL'}")
    print(f"  J clean shutdown:          PASS")
    return 0 if processed else 1


if __name__ == "__main__":
    sys.exit(main())
