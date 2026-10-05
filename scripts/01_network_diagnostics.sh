#!/usr/bin/env bash
# ARUGA network diagnostics — Layer A (read-only).
# Usage: ./01_network_diagnostics.sh <target-ip> [interface]
# Observes link state, routing, ARP, and LAN reachability. Changes nothing.

set -u

TARGET="${1:?usage: $0 <target-ip> [interface]}"
IFACE="${2:-}"

echo "=== ARUGA network diagnostics — target $TARGET ==="

if [ -z "$IFACE" ]; then
    IFACE=$(ip route show default 2>/dev/null | awk '{print $5; exit}')
    echo "default interface: ${IFACE:-unknown}"
fi

echo
echo "--- 1. interface address ---"
ip addr show "$IFACE" 2>/dev/null | grep -E "^[0-9]+:|inet |link/ether"

echo
echo "--- 2. routes ---"
ip route

echo
echo "--- 3. link health (carrier/speed/duplex/errors) ---"
for f in carrier speed duplex operstate; do
    printf "%s: " "$f"; cat "/sys/class/net/$IFACE/$f" 2>/dev/null || echo "n/a"
done
ip -s link show "$IFACE" 2>/dev/null | sed -n '3,8p'

echo
echo "--- 4. current ARP table ---"
ip neigh show

echo
echo "--- 5. gateway ping ---"
GW=$(ip route show default 2>/dev/null | awk '{print $3; exit}')
if [ -n "$GW" ]; then
    ping -c 4 -W 2 "$GW" | tail -2
else
    echo "no default gateway found"
fi

echo
echo "--- 6. target ping ($TARGET) ---"
ping -c 4 -W 2 "$TARGET"; PING_RC=$?
echo "ping exit: $PING_RC"

echo
echo "--- 7. ARP state for target ---"
ip neigh show "$TARGET"

echo
echo "--- 8. arping (L2 probe, optional) ---"
if command -v arping >/dev/null 2>&1; then
    arping -c 5 -I "$IFACE" "$TARGET" 2>&1 || \
        echo "arping blocked (needs CAP_NET_RAW/root) — run: sudo arping -c 5 -I $IFACE $TARGET"
else
    echo "arping not installed (apt install iputils-arping)"
fi

echo
echo "--- 9. privileged flush+re-probe (optional, sudo only) ---"
if sudo -n true 2>/dev/null; then
    sudo ip neigh flush dev "$IFACE"
    ping -c 2 -W 2 "$TARGET" | tail -2
    ip neigh show "$TARGET"
else
    echo "skipped (no passwordless sudo). To run manually:"
    echo "  sudo ip neigh flush dev $IFACE && ping -c 2 $TARGET && ip neigh show $TARGET"
fi

echo
echo "--- 10. /24 reachability sweep (broadcast-domain check) ---"
PREFIX=$(echo "$TARGET" | cut -d. -f1-3)
ALIVE=0
for i in $(seq 1 254); do
    ping -c 1 -W 1 "$PREFIX.$i" >/dev/null 2>&1 && {
        echo "ICMP-ALIVE $PREFIX.$i"; ALIVE=$((ALIVE+1))
    } &
done
wait
echo "alive hosts: $ALIVE"
echo "--- ARP successes ---"
ip neigh show | grep -vE "FAILED|INCOMPLETE" || echo "(none)"
echo "--- ARP unresolved ---"
ip neigh show | grep -E "FAILED|INCOMPLETE" | head -20

echo
echo "=== interpretation hints ==="
echo "- ARP FAILED/INCOMPLETE + gateway pings OK = L2 isolation or host offline"
echo "- Only gateway + self alive on /24 = client/port isolation on switch or AP"
echo "- Zero RX errors + carrier 1 = physical link is fine"
exit $PING_RC
