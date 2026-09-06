# 05 — The srv container

## Image

Built from `backend/olcrtc/Dockerfile`. Note that it obtains olcrtc by cloning
upstream at build time:

```dockerfile
RUN git clone --depth=1 https://github.com/openlibrecommunity/olcrtc.git olcrtc
RUN mage build
```

**Deployment note:** this deployment currently overrides that binary with a
locally cross-compiled one carrying fixes not yet upstream (a per-connection
record stream fix, a Windows socket-pinning feature, a shutdown ordering fix).
The override is a single extra `COPY olcrtc-linux-amd64 ./olcrtc` line; the
original Dockerfile is kept beside it as `Dockerfile.upstream-clone.bak`. Remove
both once the fixes land upstream, or the build will keep silently shipping the
local binary.

## Shutdown, and why it matters

The container runs two processes: the SOCKS proxy and olcrtc. The entrypoint was
changed to forward `SIGTERM` to **olcrtc** and wait for it to actually exit:

```sh
trap 'kill "$proxy_pid" 2>/dev/null || true' EXIT
trap 'kill -TERM "$olcrtc_pid" 2>/dev/null || true' INT TERM

while kill -0 "$olcrtc_pid" 2>/dev/null; do
  wait "$olcrtc_pid" || true
done
```

Previously the trap killed only the proxy. olcrtc never saw the signal, never ran
its shutdown, and never sent connected clients the "I am leaving" notification —
so every handover looked to the client like an unexplained silence, and it waited
out its liveness window (about a minute of dead tunnel) before failing over.

With the signal forwarded, a handover costs the client about two seconds.

The `while kill -0` loop is not decorative: a trapped signal makes `wait` return
while the child is still shutting down, so a plain `wait` would let the container
exit before the notification reached the wire.

## Naming, and why the standby is invisible

- primary: `olcwave-<tag>-<uuid>` — three parts
- standby: `olcwave-<tag>-<uuid>-nx` — four parts

Container discovery only recognises the three-part form, so the standby is
invisible to `/sub`, to the panel and to the rotator's own slot loop. It is a
warm server, not a slot of its own. The rotator reaches it explicitly by name.

## Container helpers

`backend/src/olcrtc/{sdk,service}.py` gained `stop`, `rename` and a
read-the-container's-config path. `rename` is what makes the promotion atomic
from the rest of the system's point of view: the standby becomes the canonical
name, and everything that looks up a slot by name finds the new room.
