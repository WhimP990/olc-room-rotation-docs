# 05 — Reading the client

## A healthy startup

```
Using DNS server 1.1.1.1:53 for olcRTC
Starting olcRTC provider=telemost, transport=vp8channel, room=<id>, port=10808
olcRTC sockets pinned to interface index 29 (keeps its own traffic off the TUN)
rtc: failover cycle=1 starting profile=<id> ...
rtc: session <uuid> opened (device=<uuid>)
rtc: SOCKS5 server listening on 127.0.0.1:10808
Windows TUN IPv6 leak protection enabled
Windows TUN connected on Olcbox
olcRTC room list refreshed (2 rooms: <a>, <b>) - live reload, no restart
```

Two things to check on sight:

- **`sockets pinned to interface index N`** — without it, re-joining a room after
  a handover will fail (see `03-windows-tun.md`).
- **`2 rooms:` with two ids** — one room means the client has no standby and the
  next handover will strand it.

## A healthy handover

```
rtc: control closed by peer (server retired this room) - failing over to next room now
rtc: failover cycle=1 profile=<old> ended
rtc: failover cycle=1 starting profile=<new>
rtc: session <uuid> opened (device=<uuid>)
olcRTC room list refreshed (2 rooms: <new>, <next standby>)
```

Roughly two seconds end to end, and the room list is current again immediately
after.

## Symptoms worth recognising

| what you see | what it means |
|---|---|
| `missed pong ... missed=3` then failover | the graceful close did not arrive; the slow path ran instead |
| `record too old` from muxconn | frames being dropped by the replay window — must not appear |
| `remote not ready (connect ack=0x04)` | the exit cannot route that target; normal in bursts for IPv6 at startup |
| `1 rooms:` after a refresh | no standby — investigate before the next handover |
| repeated `cloud-api.yandex.ru ... 10.0.88.88` | interface pinning is not in effect |

## Known limitation

**There is no recovery from a fully stale room list.** Everything here reduces
the chance of reaching that state — learn the standby early, never give up
reconnecting, keep olcRTC's own traffic off the tunnel — but nothing gets out of
it. If every room the client holds is dead, it cannot fetch the subscription that
would tell it about live ones.

Closing it needs something that does not itself depend on a room: a second
transport to the same server used only for rescue, deeper overlap so more than
one live room is always held, or a manual re-import by the user. This is a
deliberate open item, not an oversight.

## Building

The desktop app bundles the olcRTC binary inside `desktopApp-*.jar` at
`native/olcrtc-windows-amd64.exe`.

**The Gradle task that builds it declares no inputs**, so it considers itself up
to date whenever the output exists — a change to olcRTC source will be silently
ignored by a plain `createDistributable`. Force it:

```
./gradlew :desktopApp:buildOlcRtcWindowsAmd64 --rerun-tasks
./gradlew :desktopApp:createDistributable
```

Then verify the binary in the packaged jar actually contains the change before
shipping it. Assume nothing here.
