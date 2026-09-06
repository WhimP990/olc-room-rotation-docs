# olcbox — surviving a moving target

What this documents: everything added to olcbox on top of
`alananisimov/olcbox @ 6e26b50` so a desktop client keeps its tunnel while the
server continuously moves it between short-lived conference rooms.

Companion document: the server side is described in `olcwave/`.

## The constraint everything follows from

The client's tunnel lives inside a conference room. The server retires rooms
constantly — they expire on the provider's side after about a day — so the room
under the client is always temporary.

The client's users sit behind a whitelist: they can reach the conference
provider, and nothing else. **The subscription that says where to go next is
itself only reachable through the tunnel.** So a client holding nothing but dead
rooms cannot ask for live ones. It does not recover slowly; it does not recover.

Two obligations follow, and every change here serves one of them:

1. **Never be down to one live room** if it can be helped — learn the next room
   early and keep it.
2. **Never let the client's own traffic depend on the tunnel it is trying to
   build** — the calls that join a room must go around it.

## What changed

431 lines across 7 files.

| file | what |
|------|------|
| `data/datasource/LocationsDatasource.kt` | parse the `##rooms` subscription header |
| `data/model/LocationConfig.kt` | carry failover rooms — **and persist them** |
| `ui/features/home/HomeScreenModel.kt` | refresh the room list on connect and before stop |
| `vpn/DesktopVpnManager.kt` | refresh after a handover; reconnect forever; pin olcRTC's sockets; live config rewrite |
| `vpn/desktop/OlcRtcCommand.kt` | always emit a failover `profiles:` config |
| `vpn/desktop/WindowsTunController.kt` | IPv6 blackhole; physical interface discovery; quieter tun2socks |
| two test files | pin the room-list persistence and the handover trigger |

## Read in this order

1. `01-dynamic-room-list.md` — how a room id travels from the server into a live
   olcRTC session. Start here; most of the value is in this path.
2. `02-handover.md` — what the client does when the server retires its room.
3. `03-windows-tun.md` — the TUN, and the Windows-specific reason re-joining used
   to be impossible.
4. `04-resilience.md` — the reconnect layers and why the client no longer gives up.
5. `05-operations.md` — reading the log, and what is still missing.
