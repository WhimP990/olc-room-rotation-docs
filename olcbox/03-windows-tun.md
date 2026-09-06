# 03 — Windows TUN

`vpn/desktop/WindowsTunController.kt`, plus the environment handed to olcRTC.

## Interface pinning — the reason re-joining used to be impossible

This is the most consequential change in the client.

Symptom: the first connect always worked, every later one failed.

```
failed to create link: open engine session: auth provider rejected the request:
get connection info: ... Get "https://cloud-api.yandex.ru/..."
read tcp 10.0.88.88:24062->213.180.204.127:443: forcibly closed
```

`10.0.88.88` is the TUN's own address. To join a room olcRTC must call the
provider's API — and that call was being routed **into the tunnel it was trying
to rebuild**. A deadlock: no tunnel, so no room; no room, so no tunnel. The first
connect escaped it only because the TUN did not exist yet.

The cause is that olcRTC's `protect` package only ever protected sockets on
Android — `controlFunc` returns immediately unless a `VpnService.protect`
callback is registered, and none exists on desktop. Linux worked around it by
running olcRTC privileged. Windows had nothing, so every "protected" socket
followed the route table into the TUN. (ICE survived only incidentally: WebRTC
binds its candidate sockets to enumerated interface addresses explicitly.)

The fix has two halves:

- **olcbox** reads the default route's interface index *before* the TUN is
  raised — `defaultRouteInterfaceIndex()`, excluding the TUN adapter by name —
  and passes it to olcRTC as `OLCRTC_BIND_IFINDEX`. Safe to read then, because
  olcRTC is always started before the TUN exists.
- **olcRTC** pins every socket it opens to that interface with `IP_UNICAST_IF`.

Confirmed in the log:

```
olcRTC sockets pinned to interface index 29 (keeps its own traffic off the TUN)
```

If the index cannot be determined the app says so and carries on with the old
behaviour, rather than refusing to connect.

## IPv6 blackhole

While connected, IPv6 is pulled into the TUN (`fd00:88::1/64` plus `::/1` and
`8000::/1`) so dual-stack traffic cannot leak around an IPv4-only tunnel.

A correction worth recording, because the original comment asserted otherwise:
**tun2socks does not discard the captured IPv6.** SOCKS5 carries v6 addresses
fine, so it forwards them upstream, where an IPv4-only exit answers
host-unreachable — after a full round trip over the tunnel. In real traffic that
was **91% of all tunnel streams**: 376 of 414 connections in a 2.5-minute window,
every one doomed before it started.

olcRTC now refuses IPv6 literals locally once the exit has reported it has no
IPv6 route, so the blackhole costs nothing and Happy Eyeballs falls back to IPv4
immediately.

## tun2socks log level

Raised from `warn` to `error`. tun2socks logs one warning per failed dial, and
between blackholed IPv6 and UDP the tunnel cannot carry, that was tens per
second — enough to overrun the in-app log ring and evict the tunnel events the log exists
to capture: a 5000-entry log covered about two and a half minutes, and at peak
2800 entries were produced in 52 seconds.

olcRTC logs its own side of every connection, which is the half worth keeping.

## What the tunnel does not carry

olcRTC is a stream tunnel: SOCKS `CONNECT` only, no UDP `ASSOCIATE`. So QUIC and
UDP DNS do not traverse it and applications fall back to TCP. Unsupported SOCKS
commands are now answered with a proper refusal rather than a dropped connection,
so a client sees a clear error instead of a broken proxy.
