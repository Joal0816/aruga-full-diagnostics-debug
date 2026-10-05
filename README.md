# ARUGA Full Diagnostics Debug

Standalone diagnostic toolkit for debugging the ARUGA fall-detection pipeline
from the network up: physical link → LAN/ARP → RTSP → frame acquisition →
CV pipeline. Kept separate from the production repo
(`ARUGA-fall-detection-and-inactivity-monitoring-system`) so debugging
artifacts never mix with production code.

## Principles

- **Read-only diagnostics.** Scripts observe and report; they never change
  network settings, camera settings, or ARUGA code.
- **No credentials in the repo.** RTSP username/password are read from
  environment variables at runtime and are never echoed, logged, or committed.
- **Fail at the layer that fails.** Each script maps to one layer of the stack
  and reports PASS/FAIL with the exact underlying error.

## Layout

```
scripts/
  01_network_diagnostics.sh   Layers A: link, route, ARP, LAN reachability
  02_rtsp_probe.sh            Layer B/C: RTSP auth + frame acquisition
  03_pipeline_probe.py        Layers D-J: FramePump -> HallwayManager -> YOLO -> HUD
docs/
  findings-network-2026-10-05.md   Session findings (LAN isolation incident)
```

## Usage

```bash
# 1. Network layer (no credentials needed)
./scripts/01_network_diagnostics.sh 192.168.1.15

# 2. RTSP layer (credentials from env — never on the command line)
export ARUGA_CAM_IP=192.168.1.15
export ARUGA_CAM_USER='<username>'
export ARUGA_CAM_PASS='<password>'   # do not commit; do not echo
./scripts/02_rtsp_probe.sh

# 3. Full CV pipeline on real camera frames
./scripts/03_pipeline_probe.py
```

## Layer map (A–J)

| Layer | What | Script |
|---|---|---|
| A | Network connectivity (link, ARP, LAN) | `01_network_diagnostics.sh` |
| B | RTSP authentication | `02_rtsp_probe.sh` |
| C | RTSP frame acquisition | `02_rtsp_probe.sh` |
| D | FramePump | `03_pipeline_probe.py` |
| E | HallwayManager | `03_pipeline_probe.py` |
| F | YOLO inference | `03_pipeline_probe.py` |
| G | Person tracking | `03_pipeline_probe.py` |
| H | Fall/inactivity detection | `03_pipeline_probe.py` |
| I | Risk/HUD rendering | `03_pipeline_probe.py` |
| J | Clean shutdown | `03_pipeline_probe.py` |

## Requirements

- Linux (tested on Ubuntu), `iproute2`, `ping`
- `arping` optional (needs `CAP_NET_RAW` / root) — scripts degrade gracefully
- For scripts 02–03: the ARUGA project's Python environment (OpenCV, ONNX Runtime)
