#!/bin/sh
# Proves (or disproves) the rotation switch command end to end: attach a real
# olcrtc client to the standby's room, stop that srv the way the rotator does,
# and see whether the client is told to leave instead of finding out via pongs.
set -u

SB="${1:?usage: verify-graceful-close.sh <srv-container-name>}"
BIN="${OLCRTC_BIN:-/opt/olcwave/backend/olcrtc/olcrtc-linux-amd64}"
CFG="${TMPDIR:-/tmp}/olcrtc-verify-client.yaml"
LOG="${TMPDIR:-/tmp}/olcrtc-verify-client.log"

ROOM=$(docker exec "$SB" sh -c "grep -A1 '^room:' /tmp/olcwave/config.yaml | grep id:" \
       | sed -E "s/.*id: *'?([0-9]+)'?.*/\1/")
KEY=$(docker exec "$SB" sh -c "grep -E '^  key:' /tmp/olcwave/config.yaml" \
      | sed -E "s/^  key: *'?([^']*)'?/\1/")

echo "room under test: $ROOM"
[ -n "$ROOM" ] || { echo "ABORT: no room"; exit 1; }
[ -n "$KEY" ] || { echo "ABORT: no key"; exit 1; }

cat > "$CFG" <<EOF
mode: cnc
auth:
  provider: telemost
crypto:
  key: '$KEY'
net:
  transport: vp8channel
  dns: '8.8.8.8:53'
socks:
  host: '127.0.0.1'
  port: 11080
liveness:
  interval: 5s
  timeout: 8s
  failures: 3
vp8:
  batch_size: 64
  fps: 30
profiles:
  - name: 'verify'
    room:
      id: '$ROOM'
failover:
  retry_delay: 2s
EOF
chmod 600 "$CFG"

rm -f "$LOG"
"$BIN" "$CFG" > "$LOG" 2>&1 &
CLIENT_PID=$!
echo "client pid=$CLIENT_PID, waiting for it to attach..."

i=0
while [ $i -lt 60 ]; do
    if grep -q "SOCKS5 server listening" "$LOG" 2>/dev/null; then
        echo "client attached after ${i}s"
        break
    fi
    if ! kill -0 "$CLIENT_PID" 2>/dev/null; then
        echo "ABORT: client exited early"
        sed -E "s/$KEY/<MASKED>/g" "$LOG" | tail -20
        exit 1
    fi
    i=$((i + 1))
    sleep 1
done

echo "=== srv sees the peer? ==="
docker logs --tail 5 "$SB" 2>&1 | grep -iE "peer connected|Current peers count" || echo "(no peer line yet)"

echo
echo "=== stopping the srv the way the rotator does (docker stop) ==="
docker stop "$SB" >/dev/null 2>&1
echo "stopped"

sleep 6

echo
echo "=== srv shutdown lines ==="
docker logs "$SB" 2>&1 | grep -iE "Shutting down|peer close:|Shutdown complete" || echo "(none)"

echo
echo "=== CLIENT REACTION ==="
if grep -q "control closed by peer" "$LOG"; then
    echo "RESULT: INSTANT SWITCH WORKS"
    grep -n "control closed by peer" "$LOG"
else
    echo "RESULT: NO CLOSE RECEIVED - client is on the slow path"
fi
echo "--- client log tail ---"
sed -E "s/$KEY/<MASKED>/g" "$LOG" \
    | grep -vE "\[ice\]|\[pc\]|Failed to (read|send)" | tail -20

kill "$CLIENT_PID" 2>/dev/null
rm -f "$CFG"
echo
echo "(standby container left stopped; the rotator recreates it)"
