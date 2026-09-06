# 02 — The room pool

`backend/src/profiles/roomGenerator.py`

## Why a pool and not "mint on demand"

Minting a room is an authenticated call to Yandex on a specific account. Doing it
at the moment of need makes a handover depend on that call succeeding right then,
and it produces an unbounded trail of abandoned rooms on the account.

Instead each token keeps a small fixed set of live rooms that are reused:

- `POOL_PER_TOKEN = 2` rooms per token
- `ROOM_MAX_AGE = 18 h` — a pooled room older than this is dropped and replaced,
  comfortably before the provider's own ~24 h expiry

`mint_room` picks at random from the pool, excluding rooms that are in play (the
current room, the current standby, and the room just vacated).

## Room age is a first-class fact

Each pooled entry is `{"room": id, "created": epoch}`, and `room_created_at()`
answers "how old is this room really".

This matters more than it looks. The rotator's expiry guard measures against
`current_created`, so if a room's real birth is unknown the guard is measuring
from the wrong instant — and the guard is the thing that stops a client riding a
room to its death. `_set_hold` falls back to "born now" when the age is unknown,
which is safe only if that case is rare. Making it rare is why the pool is
persisted (`04-persistence.md`) and why rooms found in running containers are
adopted into it.

## Tokens

Yandex `Session_id` is realm-bound: a `yandex.ru` session authenticates only
against `cloud-api.yandex.ru`, a `.com` session only against `.com`. Minting
therefore tries `.ru` then `.com` before drawing any conclusion.

Three token states:

| state | meaning | effect |
|-------|---------|--------|
| active | works | used normally |
| parked | failed to mint on both realms | dropped from the active set for `DEAD_TOKEN_TTL` (1 h), then retried |
| confirmed dead | **401/403 on both realms** (`TokenAuthDead`) | pruned from the profile config so the panel reflects it |

The distinction is deliberate. A 5xx, a timeout or a network error parks a token
for an hour; only an explicit auth rejection on both realms deletes it. A Yandex
outage must never delete a user's tokens.

Managed (vault-backed) tokens are refreshed from the vault every
`TOKEN_REFRESH_INTERVAL` (6 h), so a stored `Session_id` never goes stale in
place.

## Liveness checking

`room_alive(provider, room_id)` returns **three** values, and they are not
interchangeable:

- `True` — alive
- `False` — the provider explicitly says it does not exist
- `None` — could not find out

For Telemost, `False` means the page came back without the "no such meeting"
text absent — i.e. Yandex actually answered that the room is gone. A timeout
raises and becomes `None`; an error page or a captcha reads as alive. The three
cases exist precisely so the rotator can refuse to act on `None`.

This function was present in the original code but had **zero callers** until the
rotator's health check was wired to it.
