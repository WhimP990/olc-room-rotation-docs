# 01 — How a room id reaches a running tunnel

Five hops. A break at any one of them leaves the client with a single live room,
which is the state the whole design exists to avoid.

```
/sub  ──▶  parse  ──▶  storage  ──▶  olcRTC config file  ──▶  supervisor reload
```

## 1. The wire

The subscription carries extra rooms as a header under each location:

```
olcrtc://...
##name: <label>
##rooms: <id> [<id> ...]
```

These share the location's key, provider and transport — they are the same
location, reachable in several rooms. A client that does not understand `##rooms`
ignores the line and uses the primary, so the format is backward compatible.

## 2. Parsing

`parseFailoverRooms` splits on comma or whitespace into
`LocationConfig.failoverRoomIds`. `normalized()` trims, drops blanks and removes
any entry equal to the primary id, so the primary can never appear twice.

`failoverRooms()` is the ordered list the rest of the app uses: **primary first,
then the extras.**

## 3. Storage — where this used to break

`LocationEntry` is the persisted shape (`endpoint{room_id,key}`, `auth_provider`,
`transport{}`), and it originally had **no field for failover rooms**. The parse
above worked perfectly, and then `LocationEntry.from()` dropped the list on save
while the `location` getter rebuilt a config without it. `failoverRooms()`
therefore always returned exactly one room.

The effect was invisible from the client side and total: the server could hand
over as correctly as it liked, and the client had nowhere to go. Confirmed from a
real `locations_v4.json` whose stored entry held only `room_id`, on a refresh
whose response provably contained a second room.

Fixed by adding `failover_rooms` to `LocationEntry` and carrying it through
`from()`, `normalized()` and the `location` getter.
`keepsFailoverRoomsAcrossASaveAndLoad` pins it.

## 4. The olcRTC config

`OlcRtcCommand` **always** emits a failover `profiles:` block, even for a
single-room location:

```yaml
liveness:
  interval: 5s
  timeout: 8s
  failures: 2
profiles:
  - name: '<room a>'
    room:
      id: '<room a>'
  - name: '<room b>'
    room:
      id: '<room b>'
failover:
  retry_delay: 2s
```

Always, because that is what puts olcRTC under its supervisor, and the
supervisor re-reads this file on every hop. A single-room location becomes a
one-profile supervisor that reconnects in place rather than exiting — same
behaviour as before, but now the list can grow underneath it.

Note there is no `max_cycles`, so the supervisor never gives up.

## 5. Live reload, no restart

`rewriteActiveConfigIfConnected` rewrites the config file in place whenever the
stored locations change while connected. It writes to a temp file and moves it
atomically, so olcRTC can never read a half-written config.

olcRTC picks the new list up on its next hop. The running session is untouched —
rooms added while a tunnel is live are simply there when it next needs one.

The log line prints the ids, not a count:

```
olcRTC room list refreshed (2 rooms: <room>, <room>) - live reload, no restart
```

A bare count could not distinguish "the standby is missing" from "there is one",
which is exactly the question that mattered while the storage bug above was live.
