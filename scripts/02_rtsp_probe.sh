#!/usr/bin/env bash
# ARUGA RTSP probe — Layers B/C (read-only).
# Tests RTSP authentication and frame acquisition against a Tapo camera.
#
# Credentials come from environment variables and are NEVER echoed or logged:
#   ARUGA_CAM_IP    camera IP        (required)
#   ARUGA_CAM_USER  RTSP username    (required)
#   ARUGA_CAM_PASS  RTSP password    (required)
#   ARUGA_CAM_STREAM stream1|stream2 (optional, default stream2)
#
# Usage: ./02_rtsp_probe.sh

set -u

: "${ARUGA_CAM_IP:?set ARUGA_CAM_IP}"
: "${ARUGA_CAM_USER:?set ARUGA_CAM_USER}"
: "${ARUGA_CAM_PASS:?set ARUGA_CAM_PASS}"
STREAM="${ARUGA_CAM_STREAM:-stream2}"

echo "=== ARUGA RTSP probe — ${ARUGA_CAM_IP}:554/${STREAM} ==="
echo "(credentials read from env; nothing is printed)"

# URL built in Python so the password never appears in process listings' output
# or in shell traces.
RTSP_URL=$(python3 - "$ARUGA_CAM_IP" "$ARUGA_CAM_USER" "$ARUGA_CAM_PASS" "$STREAM" <<'PY'
import sys
from urllib.parse import quote
ip, user, pw, stream = sys.argv[1:5]
print(f"rtsp://{quote(user, safe='')}:{quote(pw, safe='')}@{ip}:554/{stream}")
PY
)
# Belt and braces: never let bash trace this variable.
set +x 2>/dev/null

echo
echo "--- B. RTSP authentication + C. frame acquisition (10s capture) ---"
python3 - "$RTSP_URL" <<'PY'
import sys, time
import cv2

url = sys.argv[1]
import os
os.environ["OPENCV_FFMPEG_CAPTURE_OPTIONS"] = "rtsp_transport;tcp|stimeout;5000000|reorder_queue_size;0"

cap = cv2.VideoCapture(url, cv2.CAP_FFMPEG)
if not cap.isOpened():
    print("B/C FAIL: could not open RTSP stream (auth failure, wrong URL, or no route)")
    sys.exit(2)

frames, shapes, t0 = 0, set(), time.time()
while time.time() - t0 < 10.0:
    ok, frame = cap.read()
    if ok and frame is not None:
        frames += 1
        shapes.add((frame.shape, str(frame.dtype)))
    if frames >= 30:
        break

w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH) or 0)
h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT) or 0)
fps = cap.get(cv2.CAP_PROP_FPS) or 0.0
cap.release()

if frames == 0:
    print("B PASS (connected) / C FAIL: stream opens but no frames decoded")
    sys.exit(3)

print(f"B PASS: RTSP authenticated (stream opened)")
print(f"C PASS: {frames} frames in {time.time()-t0:.1f}s")
print(f"   reported: {w}x{h} @ {fps:.1f} fps")
for shape, dtype in shapes:
    print(f"   decoded:  shape={shape} dtype={dtype}")
print("   note: frame must be (H, W, 3) uint8 BGR for the ARUGA pipeline")
PY
