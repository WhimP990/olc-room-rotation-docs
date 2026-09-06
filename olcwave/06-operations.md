# 06 — Operating it

## The panel toggle

Settings gained a rotation-mode control (`prod` / `test`), stored in
`RuntimeSettings.rotation_mode`. It is read on every rotator tick, so flipping it
takes effect within one tick with **no restart** — `prod` holds rooms for 4–14 h,
`test` for 3–8 min so a full handover can be watched end to end.

## Reading the log

Healthy handover:

```
[sub] <uuid>/<tag>: delivered rooms ['<current>', '<standby>'] (primary=<current>, ##rooms=['<standby>'])
[olcwave-rotator] <slot>: SWAP ok - client has current=<current> + standby=<standby>
[olcwave-rotator] <slot>: rotated -> <standby> (scheduled, warm standby promoted)
[olcwave-rotator] <slot>: warm standby up on <next> (##rooms)
```

Waiting, with the reason spelled out:

```
[olcwave-rotator] <slot>: swap HELD (deadline passed) - srv_up=True client_live=False
                  client_has_current=True client_has_standby=True standby=<room> client_list=[...]
```

Read `swap HELD` as the system working, not failing. Each flag says exactly which
precondition is missing. `client_live=False` with everything else true is the
normal idle state when nobody is connected — rotations correctly stop.

Worth noticing:

| line | meaning |
|------|---------|
| `room <id> reported gone (n/3) - confirming before acting` | a death verdict is accumulating; a single bad probe will not act |
| `adopted existing standby ... on <room>` | a restart kept a warm server instead of destroying it |
| `resumed: N slot(s), M pooled room(s)` | state came back from storage |
| `primary died -> fresh room <id> (HOLD)` | **see limitations below** |

## Known limitations

Two deliberate gaps remain. Both are understood and documented rather than
accidental.

**A confirmed-dead primary with no warm standby resets to a fresh room.** The
rotator mints a brand-new room and serves that. Any client still attached cannot
learn the new room id — it would need the tunnel to ask, and the tunnel is what
it just lost. This is harmless when the room really is dead (the client was
already stranded) but it also fires on the `near expiry` path, where the room is
still **alive** and the client is still using it. That case destroys a working
tunnel 30 minutes early. Observed once in ~30 hours of unattended running.

*Shape of the fix, if it is taken up:* never destroy a live room while a client
is attached and there is nowhere for it to go — keep serving and keep retrying
the standby; reset freely only when `client_live` is false.

**The 24-hour room lifetime is an assumption, and it was wrong at least once.**
`ROOM_LIFETIME_SECONDS` drives the `near expiry` path. On 2-6 September 2026 a
room stayed alive for over four days with the srv sitting in it, while the
rotator had no working token to build a standby (see `07-token-vault.md` for
why). The moment a standby appeared, `near expiry` promoted it within two
minutes, with `client_has_standby=False` - the client was not attached at the
time, so nothing broke, but its stored list was left holding only the retired
room. On a whitelist that is the stale-list dead end described below. Two
consequences: the near-expiry threshold should be measured, not assumed, and
the forced path should keep the old room (or keep serving it) until the client
has actually been told about the new one.

**There is no recovery from a fully stale room list.** Everything above reduces
the probability of a client holding only dead rooms; nothing recovers from it.
The fix has to come from outside the room system — a rescue transport that does
not itself depend on a room, or deeper overlap so more than one live room is
always in the client's list.

## Testing checklist

- Set rotation mode to `test` so a full handover happens in minutes.
- Watch a client's log for `control closed by peer` followed within ~2 s by the
  next `failover cycle=... starting profile=<new room>`. That is the fast path.
  Falling back to `missed pong` means the close did not arrive.
- Confirm the client's room list shows **two** ids after a handover, not one.
- **Do not curl `/sub` during a live test.** The rotator cannot distinguish your
  fetch from the client's, and it will satisfy the swap gate on the client's
  behalf. See `03-subscription-protocol.md`.
