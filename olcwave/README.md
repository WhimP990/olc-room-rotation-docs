# olcWave — room rotation subsystem

What this documents: everything added to olcWave on top of
`invdevv/olcwave @ 641feb8` to make a client's tunnel survive being moved
between short-lived conference rooms, indefinitely and without the user
noticing.

## The problem in one paragraph

A client's tunnel lives inside a Telemost conference room. Telemost kills
instant rooms after roughly 24 hours, so a room is a wasting asset. Worse, the
clients this is built for sit behind a whitelist: they can reach the conference
provider, and nothing else. The subscription that would tell a client where to
go next is itself only reachable **through the tunnel**. So a client that loses
its room cannot ask for a new one — it is not slow to recover, it is gone.

Everything here follows from that single constraint. The server may never take
away a room until it has proof the client is already holding a live alternative.

## Mental model

Two containers per slot at all times:

- the **primary**, `olcwave-<tag>-<uuid>`, serving the room the client is in
- a **warm standby**, `olcwave-<tag>-<uuid>-nx`, already sitting in the *next*
  room, idle

A handover is: stop the primary (it tells the client "I'm leaving" on the way
out), remove it, rename the standby to the canonical name, and immediately build
the next standby. Make-before-break — the destination is live and joined before
the source goes away.

The client learns the standby's room id from its subscription, as a `##rooms`
header, while the current room is still up.

## What was added

| file | lines | what |
|------|-------|------|
| `backend/src/room_rotator.py` | 884, new | the state machine: holds, handover, gate, health |
| `backend/src/profiles/roomGenerator.py` | +311 | fixed room pool per token, ages, dead-token handling |
| `backend/src/subscriptions/service.py` | +240 | `##rooms` delivery and recording exactly what went out |
| `backend/src/room_state.py` | 114, new | shared state between `/sub` and the rotator |
| `backend/src/persistence.py` | 75, new | what survives a restart |
| `backend/src/settings/{schemas,router}.py` | +97 | live prod/test cadence toggle |
| `backend/src/olcrtc/{sdk,service}.py` | +29 | container stop / rename / read-config helpers |
| `backend/src/locks.py` | 20, new | per-user lock around cutovers |
| `backend/olcrtc/entrypoint.sh` | +28 | forward SIGTERM to olcrtc so it can say goodbye |
| `backend/src/main.py` | +10 | run the rotator as a background task |
| frontend | ~200 | rotation-mode toggle, profile auto-refresh, i18n |

## Read in this order

1. `01-rotation-model.md` — the state machine and the swap gate. Start here.
2. `02-room-pool.md` — where rooms come from and how their age is tracked.
3. `03-subscription-protocol.md` — how a client is told about the next room.
4. `04-persistence.md` — what survives a restart, and what deliberately does not.
5. `05-srv-container.md` — the srv container, its shutdown, standby adoption.
6. `06-operations.md` — the panel toggle, reading the logs, known limitations.
7. `07-token-vault.md` — the token vault sidecar: why, how a login happens, what to know before enabling it.

## Scope note

The rotation subsystem is documented from the code and from live behaviour.
The token vault (a Playwright/noVNC sidecar that keeps Yandex sessions warm and
refreshes managed tokens) was built in the same tree and is described in
`07-token-vault.md`. Two smaller things changed alongside and are covered only
by their commit messages: the `users/` per-user profile column and the
container image changes.
