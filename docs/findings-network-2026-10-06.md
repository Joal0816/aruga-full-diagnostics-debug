# Findings — ARUGA network diagnostics (2026-10-06)

## Scope

Physical-hardware validation of the ARUGA pipeline
(Tapo C230 → RTSP → FramePump → HallwayManager → YOLOv8-pose → tracking →
fall/inactivity → risk/HUD) was **blocked at Layer A (network)**.

Machine under test: Ubuntu ARUGA/debug PC, `192.168.1.11/24`, `enp3s0`
(USB/dock ethernet, altname `enx3497f68d9737`), gateway `192.168.1.1`.
Target: Tapo C230 at `192.168.1.15`, confirmed alive from a separate Windows
PC on the same LAN (0% loss, TTL=64, 5–112 ms).

## Probe results (exact)

| Probe | Result |
|---|---|
| `ip addr show enp3s0` | 192.168.1.11/24, MAC 34:97:f6:8d:97:37, UP |
| `ip route` | default via 192.168.1.1; connected 192.168.1.0/24 — correct |
| `ip neigh show` | `.15` FAILED/INCOMPLETE; gateway `.1` REACHABLE (f4:2d:06:a5:da:d6) |
| `ping 192.168.1.1` | 0% loss, 0.47–0.54 ms, TTL=64 |
| `ping 192.168.1.15` | 100% loss — `Destination Host Unreachable` generated **locally** at ARP resolution failure |
| `arping 192.168.1.15` | not runnable (no CAP_NET_RAW / passwordless sudo) — tool limitation, not a network result |
| `ip neigh flush` | not runnable (needs CAP_NET_ADMIN) — nothing changed |
| post-probe `ip neigh show .15` | INCOMPLETE — ARP requests sent, no reply ever |
| link health | carrier 1, 1000 Mb/s full duplex, RX/TX errors 0, drops 0 |
| /24 sweep from .11 | **only** .11 (self) and .1 (gateway) alive; all 252 other addresses INCOMPLETE |

## Conclusion

**Layer-2 client/port isolation** between the Ubuntu PC's switch port and all
other client ports. Not a camera problem, not wrong camera IP, not ARUGA code,
not a host misconfiguration.

Evidence chain:

1. Failure is below IP — the ICMP error originates at 192.168.1.11 because ARP
   resolution never completes (`INCOMPLETE`).
2. Gateway ARPs and pings perfectly while **no other host on the /24 answers
   ARP** — the textbook signature of port/client isolation (uplink to router
   works; client↔client bridging blocked).
3. The Windows PC reaches the camera fine — the camera is alive and correctly
   addressed, it is simply not in the Ubuntu PC's working bridged segment.
4. Ubuntu host config is clean: correct prefix/route/DHCP, no bridge or VLAN
   mangling, zero interface errors.
5. `enp3s0` is USB/dock ethernet — if that dock hangs off a different switch,
   mesh node, or a router port configured as guest/isolated, that is the
   isolation source.

## Smallest next steps (no code / no camera changes)

1. **Decisive test:** plug the Windows PC into the same ethernet port/cable the
   Ubuntu PC uses. If Windows then also loses the camera → confirmed port
   isolation.
2. Check router/switch admin for "AP Isolation / Client Isolation / Guest
   Network / IoT network / Port isolation / VLAN" on that port or network.
3. If a mesh node or secondary switch is in the path, attach the Ubuntu PC to
   the device the camera hangs off (or the node the Windows PC uses).
4. Optional confirmation (with sudo):
   `sudo tcpdump -i enp3s0 arp and host 192.168.1.15` while pinging — requests
   leaving with no replies returning proves network-side isolation.

## Status of pipeline validation

Layers B–J remain **NOT TESTED** on real hardware (blocked by A). They were
proven only with stubs/mocks offline and must not be marked PASS until the
camera path is live. Once ARP to .15 works, run:

```bash
export ARUGA_CAM_IP=192.168.1.15
export ARUGA_CAM_USER='<username>'
export ARUGA_CAM_PASS='<password>'   # env only — never commit
./scripts/02_rtsp_probe.sh
./scripts/03_pipeline_probe.py
```

## Security notes

- Camera password was never used, printed, stored, or committed during this
  session; diagnostics ran entirely credential-free.
- This repo stores no credentials; runtime probes read them from env vars only.
