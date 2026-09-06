# olc room rotation — design notes

Design documentation for a set of changes to three projects that together let a
client's tunnel survive being moved between short-lived conference rooms, on
networks where only the conference provider is reachable.

The code lives as patch series on branches of the respective forks:

| project | upstream | branch with the series | pull request |
|---|---|---|---|
| olcWave (server, panel) | [invdevv/olcwave](https://github.com/invdevv/olcwave) | [WhimP990/olcwave `room-rotation`](https://github.com/WhimP990/olcwave/tree/room-rotation) | [invdevv/olcwave#14](https://github.com/invdevv/olcwave/pull/14) |
| olcbox (desktop / Android client) | [alananisimov/olcbox](https://github.com/alananisimov/olcbox) | [WhimP990/olcbox `dynamic-room-list`](https://github.com/WhimP990/olcbox/tree/dynamic-room-list) | [alananisimov/olcbox#156](https://github.com/alananisimov/olcbox/pull/156) |
| olcRTC (transport) | [openlibrecommunity/olcrtc](https://github.com/openlibrecommunity/olcrtc) | [WhimP990/olcrtc `fixes-and-failover`](https://github.com/WhimP990/olcrtc/tree/fixes-and-failover) | [openlibrecommunity/olcrtc#152](https://github.com/openlibrecommunity/olcrtc/pull/152) |

Each commit on those branches carries its own description. The documents here
explain the design behind them:

- [`olcwave/`](olcwave/README.md) — the room rotation subsystem: state machine,
  swap gate, room pool, subscription protocol, persistence, srv container, and
  the token vault sidecar.
- [`olcbox/`](olcbox/README.md) — how the client follows a moving room: dynamic
  room list, handover, Windows TUN, resilience, operations.
- [`olcrtc-verify-graceful-close.sh`](olcrtc-verify-graceful-close.sh) — the
  live harness used to confirm olcRTC's graceful close reaches the peer.

Read `olcwave/01-rotation-model.md` first.
