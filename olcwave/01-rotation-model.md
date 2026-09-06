# 01 — The rotation model

## When it runs at all

Activation is implicit and per-profile, by token count
(`MIN_TOKENS_FOR_ROTATION = 2`):

- 0 or 1 token — no rotation. The profile behaves exactly as before.
- 2 or more — the rotator drives a state machine for that profile's containers.

The reason is practical: rotation needs to mint rooms on one account while the
client sits in a room on another, so a single token cannot rotate without
disturbing the room it is already serving.

## Cadence

Two profiles, chosen live from the panel toggle (`RuntimeSettings.rotation_mode`)
with no restart:

| mode | hold between handovers | tick |
|------|------------------------|------|
| `prod` | random 4–14 h | 45 s |
| `test` | random 3–8 min | 10 s |

Only the cadence differs. The physical-expiry limits below are the same in both,
because they are tied to Telemost's room lifetime, not to our preferences:

- `ROOM_LIFETIME_SECONDS` 24 h — the assumed provider expiry
- `SWAP_SAFETY_SECONDS` 1 h — never schedule a handover later than this before expiry
- `BROKEN_BUFFER_SECONDS` 30 min — stop waiting for the client this long before expiry

## The state machine, per slot

A slot is one container name, `olcwave-<tag>-<uuid>`. Its state lives in
`RoomRotator._state[name]`.

```
HOLD  ──client seen──▶  ARMED  ──deadline + gate──▶  handover ──▶  HOLD (armed)
 ▲                                                                     │
 └─────────────────────────────────────────────────────────────────────┘
```

**HOLD, not armed.** A freshly built slot serves its room and does nothing else.
No swap time is picked and no standby is built until a client actually shows up.
"A client showed up" is proxied by a `/sub` fetch, which on a whitelist can only
have travelled through the live tunnel — so a fetch is proof of a working client.

**ARMED.** A random hold is picked from the cadence, then capped against the
room's remaining life: `min(hold, remaining - SWAP_SAFETY_SECONDS)`, with a
60-second floor for the degenerate case of an already-old room. A hold never
runs past the point where a handover would still be safe. A warm
standby is built immediately and advertised.

**Handover.** Covered below.

## The swap gate

This is the centre of the design. A scheduled handover fires only when **all** of
these hold:

| condition | why |
|-----------|-----|
| a standby room is chosen | there is somewhere to go |
| `srv_up` — the standby container is in its room | the destination is actually live |
| `client_has_current` | the client's last subscription contained the room it is in |
| `client_has_standby` | ...and the room it must move to |
| `fetched_ok` | that subscription went out after we advertised the standby |
| `client_live` | a tunnel client is attached to the primary **right now** |

`client_has_*` are checked against `RoomState.delivered` — the exact set of room
ids the client's most recent `/sub` actually handed it. Not "a fetch happened",
but "these specific rooms were in it".

`client_live` is read from the srv's own log: it prints `Current peers count: N`
on every peer open and close, so the newest such line is the live count.

### Why `client_live` had to be added

Without it, the first `/sub` fetch after a lapsed deadline opened the gate and
the handover fired instantly — retiring the very room the client was in the
middle of dialling. Observed live: fetch at 15:54:03, handover at 15:54:07,
client dialled the now-dead room at 15:54:08 and never got through the handshake.

A fetch happens *moments before* a client connects. It is proof the client is
alive, not proof it has arrived.

## The two ungated paths

Everything above is gated. Exactly two paths can retire a room without asking
whether the client can follow. Both are deliberate, and both are the sharp edges
of the design.

**1. `primary died`.** The room is confirmed gone, so there is nothing to
protect. "Confirmed" is load-bearing: the check is tri-state (alive / the
provider says it does not exist / could not find out) and only an explicit
"no such meeting" counts, three times in a row (`DEAD_STRIKES_REQUIRED`). Any
other answer clears the streak. A timeout, a 5xx or a captcha page is *not* a
death sentence.

**2. `near expiry`.** The room is within `BROKEN_BUFFER_SECONDS` of its 24 h
expiry and the gate is still not satisfied. Rather than ride it to its death, the
rotator forces a handover.

Path 2 is a known hazard when no warm standby exists — see
`06-operations.md`, "Known limitations".

## The handover itself

```python
await Containers.stop(name)        # SIGTERM -> srv tells the client it is leaving
await Containers.remove(name)      # remove the stopped old primary
await Containers.rename(sb, name)  # promote standby -> canonical primary
```

The `stop` is the interesting one. It is a graceful stop on purpose: the srv
catches SIGTERM and sends each connected client a close notification before
exiting. The client reacts immediately instead of waiting out its liveness
window — about 2 seconds instead of about a minute. See `05-srv-container.md`.

The room just torn down is recorded as `vacated` and excluded from the next
standby, so a client still finishing its move cannot be handed back to it.

Immediately after promotion the next warm standby is built, restoring the
two-container invariant.
