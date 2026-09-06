# 04 — Staying up

## Three layers, from cheapest to most disruptive

A dropped link is handled at the lowest layer that can deal with it.

**1. In-place reconnect (olcRTC).** The link is re-established inside the same
room. Costs nothing, keeps the session.

**2. Failover to the next room (olcRTC supervisor).** The session ends and the
supervisor advances to the next profile, re-reading the config file first so any
newly delivered rooms are used. This is what a handover triggers. The supervisor
has no `max_cycles`, so it never stops trying.

**3. Process restart (olcbox).** If olcRTC or the TUN process exits, olcbox
relaunches the whole thing onto the **stored** active location. No network fetch
is involved, deliberately: there is no tunnel at that moment, so a fetch could
only fail.

## The reconnect loop no longer gives up

It used to stop after 6 attempts — about two minutes — and leave the app in
`Error` until the user pressed connect.

Two minutes is shorter than a laptop waking, a Wi-Fi roam, or a provider hiccup.
And on a whitelist the consequence is not an inconvenience: reconnecting is the
only path to a tunnel, and a tunnel is the only path to a fresh room list. Giving
up early converts a temporary outage into a permanent one.

It now retries indefinitely with the existing capped backoff (2 s doubling to
20 s), which makes an endless retry cheap. The user can still stop it — that
bumps the generation counter and the loop drops out at its next check.

Logging is throttled so a long outage leaves a trail without burying everything
else: the drop reason once up front, then every attempt for the first six, then
one line in twenty.

## What is deliberately not attempted

The client never tries to *discover* a room. It uses what it was given. Every
recovery path above works from the stored list, because inventing a room id is
not possible — the provider assigns them.

That is also the shape of the remaining gap: see `05-operations.md`.
