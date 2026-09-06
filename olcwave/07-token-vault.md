# 09 — Token vault sidecar: the service behind the panel's managed tokens

Patch 07 gave the panel and the rotator a vault *client*. This is the vault
itself, plus the wiring that lets `docker compose up -d` bring it up: a `vault`
service in `docker-compose.yaml`, a noVNC route in the Caddyfile template, and
a generated `VAULT_SECRET` in `install.sh`.

## Why it exists

A telemost profile authenticates with a Yandex `Session_id`. Pasted in by hand
it expires after roughly a month, and the profile silently stops minting rooms.
Yandex, however, rotates that cookie on activity: a browser session kept warm
keeps a valid `Session_id` indefinitely. So the vault holds one persistent
Chromium profile per account and, on request, opens it, touches Telemost, reads
the *current* cookie and closes again. The rotator calls this every
`TOKEN_REFRESH_INTERVAL` and rewrites the managed token in place, so a stored
token never rots.

Creating rooms from the browser is deliberately not automated - that trips bot
detection. Only the login is interactive, and a human does it.

## How a login happens

1. Panel: "add self-refreshing token" -> `POST /vault/login/start` (patch 07's
   admin-authenticated router) -> the vault launches a headed Chromium on a
   fresh account profile, showing telemost.yandex.ru.
2. The panel embeds noVNC (`/vault-vnc/`, proxied by Caddy to the sidecar's
   websockify on 6080), and the operator logs in by hand: password, 2FA,
   captcha, whatever Yandex asks. Nothing but the resulting browser profile is
   stored.
3. The panel polls `/vault/login/status`. Once a `Session_id` is present and
   unchanged for three consecutive reads, and the page has left
   passport.yandex, it calls `/login/commit`: the vault reads the cookie,
   closes the browser and releases its single-browser mutex.
4. `GET /token?account=` is what the backend uses from then on: open the
   profile, refresh, read, close, return the raw cookie. It is the only
   endpoint that ever returns the token, and it is reachable only inside the
   compose network.

## Shape of the service

- `vault/vault.js` (Playwright, on the official Playwright image) - the HTTP
  API: `/health`, `/accounts`, `/login/start|status|commit|cancel`, `/token`,
  `DELETE /account`. Everything but `/health` requires `X-Vault-Secret`.
- `vault/entrypoint.sh` - Xvfb :99, x11vnc bound to localhost and
  websockify/noVNC run continuously and are cheap. The browser is launched per
  operation and closed after it, which is what keeps a 2 GB box usable.
- `init: true` in compose: Node as PID 1 does not reap Chromium's exiting
  helpers, and they accumulate as zombies without it.
- Sessions live in the `vault_data` volume under `/data/accounts/<key>/profile`.
  Stale `Singleton*` locks left by an ungraceful stop are cleared on start and
  before every open; Chromium refuses the profile otherwise.

## What to know before enabling it

- A `Session_id` is a full login to that Yandex account. Treat the `vault_data`
  volume like a password store, and use dedicated accounts.
- The noVNC websocket is reachable by anyone who can reach the panel host and
  knows the path; it is not gated by the panel's JWT. The deployment this comes
  from hides the whole panel behind an unguessable path prefix on a private
  port. Gating the websocket properly is the obvious next step, not done here.
- `VAULT_SECRET` is shared between the api and the vault through the compose
  project's `.env`; `install.sh` generates it. Left empty, the vault answers
  without authentication - acceptable only if nothing but the api can reach it.
- Whether a warm session outlives Yandex's idle expiry over months is not yet
  known. The deployment has run it since late August.
