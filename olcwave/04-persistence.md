# 04 — What survives a restart

`backend/src/persistence.py`

## Why this exists

The rotator's working set used to live only in process memory. An api restart
therefore:

- reaped the warm standby container (it was not in the — now empty — tracking set)
- refilled the room pool with brand-new rooms no connected client could learn
- reset every room's `current_created` to "now", silently miscalibrating the
  expiry guard

The last one is the nasty one. A room that was 20 hours old at restart looked
newborn, so the guard believed it had a full day left. The room then died on
schedule with a client on it — and a restart is a routine deploy action, not an
incident.

## Two sources, in order of authority

**Docker is the truth for what is running.** Which room a container serves is
read back from its config, never from storage. A running container outlives the
api, so its state cannot be stale — whereas a persisted copy can disagree with
reality, and a wrong record is worse than no record.

`_adopt_running_rooms` puts rooms found in running containers back into the pool,
so their age is known rather than assumed.

**Postgres supplies only what cannot be observed:** real room birth times, dead
tokens, `RoomState.delivered`/`last_fetch`, and per-slot rotation bookkeeping.

## The store

One table, created by the existing `create_tables()` — this project has no
Alembic, so a new model is enough.

```sql
rotator_state (key text primary key, value json, updated_at timestamptz)
```

Three buckets: `room_pool`, `slots`, `room_state`.

Writes are write-through on change, driven from the rotator's own loop: each tick
serialises the current state and writes only if it differs from what storage
already holds. No background flusher, so storage never silently lags memory, and
an idle slot writes nothing.

Everything is best-effort. A storage failure logs and is swallowed — losing
persistence degrades the rotator to its old in-memory behaviour, it must never
take the API down.

## JSON, not pickle

Deliberate. The classes above this layer change often; a pickle written before a
refactor fails to load after one, and it fails *silently* because the load is
wrapped in a try. JSON survives a renamed field, and can be read with a query
when something needs explaining.

## Secrets are not stored

The in-memory pool is keyed by the `Session_id` itself, which is a full account
credential. The stored form is keyed by `sha256(token)[:8]` instead. On restore
the fingerprints are matched against the *current* tokens, so a token the user
has replaced simply does not claim its old pool — which is the desired
behaviour.

`standby_config` is deliberately excluded from the persisted slot fields: it
embeds the failover group's crypto key, and it is rebuilt by the next
`_ensure_standby` anyway.

Verified before shipping: neither the whole secret nor any 20-character run of it
appears in the stored blob.

## Resuming, not just remembering

- A `swap_deadline` that lapsed while the process was down is pushed out by
  `RESUME_GRACE_SECONDS` (120 s) rather than firing the instant the rotator
  returns. A client coming back needs to settle before it is moved.
- An untracked standby container whose slot is live and standby-less is
  **adopted**, not reaped. It is a warm server already sitting in a room the
  client was told about.
- If the slot has no state yet (first tick after a cold start), the reap decision
  is deferred by one tick rather than destroying a warm server for the sake of
  running early.

## What it looks like

```
[olcwave-rotator] started
[olcwave-rotator] resumed: 1 slot(s), 1 pooled room(s)
```

or, on a cold first run, `resumed: 0 slot(s), 0 pooled room(s)` followed by
`adopted existing standby olcwave-<tag>-<uuid>-nx on <room>`.
