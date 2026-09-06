# 03 — How a client is told about the next room

`backend/src/subscriptions/service.py`, `backend/src/room_state.py`

## The constraint

On a whitelist the client can reach the conference provider and nothing else. The
subscription URL is not whitelisted, so `/sub` is reachable **only through the
live tunnel**. Two consequences shape everything:

1. A `/sub` fetch is proof that the client had a working tunnel at that moment.
   The rotator uses it as the "client is really there" signal.
2. A client with no live room can never fetch `/sub` again. There is no recovery
   path from a fully stale room list, which is why the gate exists.

## The wire format

Per location, after the URI line:

```
olcrtc://...
##name: <label>
##rooms: <room id> [<room id> ...]
##icon: <emoji>
```

`##rooms` carries the failover-group extras — rooms that share this location's
key, provider and transport. A dynamic-list client adds them to its in-process
failover set. An older client that does not understand `##rooms` ignores the line
and keeps using the primary room, so the format is backward compatible.

## Recording what actually went out

`RoomState.note_delivered(tag, uuid, rooms)` records the exact set of room ids a
`/sub` response contained, with a timestamp. `RoomState.delivered_rooms()` reads
it back.

This is the hard half of the swap gate. An earlier version only tracked "a fetch
happened after we advertised the standby", which is weaker than it sounds: it
proves a fetch occurred, not that the response contained the room the client is
about to be moved to. Recording the delivered set turns the check from a timing
argument into a fact.

The log line makes it auditable:

```
[sub] <uuid>/test: delivered rooms ['<room>', '<room>']
      (primary=<room>, ##rooms=['<room>'])
```

## A caution for anyone testing

`note_fetch` and `note_delivered` cannot tell a real client from a `curl`. Any
manual fetch of `/sub` during a live test satisfies the gate on the client's
behalf and can let a handover through that should have been held. Do not curl
`/sub` while testing a connected client — it corrupts exactly the signal you are
trying to observe.
