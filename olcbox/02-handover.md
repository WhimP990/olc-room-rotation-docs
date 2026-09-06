# 02 — What happens when the server retires the room

## The fast path

The server stops the old srv with SIGTERM; the srv tells each connected client it
is leaving before it exits. olcRTC turns that into an immediate failover instead
of waiting out its liveness window:

```
22:06:53  control stream ended ...: control stream closed by peer
22:06:53  control closed by peer (server retired this room) - failing over to next room now
22:06:53  failover cycle=1 profile=<room> ended
22:06:55  failover cycle=1 starting profile=<room>
```

Two seconds. The slow path — noticing by missed keepalives — takes about a
minute, during which the tunnel is dead. Both still exist: a graceful close takes
the fast path, a genuine drop still needs the timeout.

## Refreshing the room list afterwards, and why it is urgent

Right after a handover the client's list is `[the room just retired, the room it
is now in]` — **one live room**. It stays that way until the next subscription
fetch tells it about the new standby.

On the old fixed 5-minute timer that window was measured and found to be 2.5 to 5
minutes, and once two handovers landed 95 seconds apart — closer together than
the refresh interval, which no amount of waiting could have survived.

So the client now refreshes as soon as a handover completes. The trigger is
olcRTC's own log line:

```
22:06:57  session 4238c0b2-... opened (device=...)
```

which appears one to two seconds after a hop, once the tunnel is actually up on
the new room — so the fetch that follows can succeed. `isSessionOpenedLine`
recognises it; `DesktopVpnManagerLogParsingTest` pins it against real output and
against five near-miss lines that must not trigger (`session=... closed by peer`,
`session closed: id=...` and friends).

Two guards:

- **only when Connected** — the first session of a connection lands here while
  the app is still Connecting, and is already covered by the refresh on the
  Connected transition
- **at most one fetch per 15 s** — a client cycling through dead rooms every two
  seconds would otherwise turn one fetch per hop into a storm

## The four moments the room list is refreshed

| when | why |
|------|-----|
| tunnel comes up | begin the session with current rooms, in case we connected on an old one |
| **after a handover** | close the one-live-room window immediately |
| before a deliberate stop | leave the stored list current so the next start begins fresh |
| every 5 minutes | catch anything the three above missed |

All four ride the live tunnel's SOCKS proxy, because there is no other way out.
