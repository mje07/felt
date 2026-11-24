# Felt relay

A tiny server that lets friends join your Felt home game from anywhere with a
six-letter invite code. You don't need it to play on the same network or by
IP address. It's only for games over the internet when port forwarding isn't
an option.

## What it does

- The host's Felt connects to `/host` and gets a code such as `K7QH2M`.
- Friends connect to `/join/K7QH2M`.
- The relay passes messages between them. It doesn't store anything and has
  no accounts or logs of hands.

The host's PC still deals every hand and runs the game, and each player is
only ever sent their own hole cards. Note that the relay carries that traffic,
so whoever runs the relay could read it. Run your own relay, or use one run
by someone you trust.

Built-in limits keep a free-tier machine healthy:

| Limit | Default |
| --- | --- |
| Open tables | 500 |
| Friends per table | 8 |
| Message size | 16 KB |
| Messages per second, per friend | 40 |
| Connections per IP address | 20 |
| Idle table closed after | 15 minutes |

The relay closes a table's code as soon as the host leaves.

## Run it locally

```sh
cd server/relay
dart pub get
dart run bin/relay.dart          # listens on $PORT, default 8080
```

In Felt, open **Play with friends** and set **Invite-code server** to
`ws://localhost:8080` (or `ws://<this PC's address>:8080` for other PCs).

## Host it for free on Render (24/7)

The repository includes a Render Blueprint (`render.yaml` at the root), so
there's nothing to configure by hand.

1. Sign in at [render.com](https://render.com) with your GitHub account.
2. Choose **New → Blueprint**, pick your fork or copy of this repository, and
   click **Apply**. Render builds `server/relay/Dockerfile` on the free plan.
3. When the deploy finishes, open the service and copy its address, such as
   `https://felt-relay-ab12.onrender.com`. Check
   `https://felt-relay-ab12.onrender.com/health`, which should say
   `Felt relay: 0 tables open`.
4. In Felt, open **Play with friends** and paste that address into
   **Invite-code server**. Every friend enters the same address.

**Keeping it awake.** Render puts a free service to sleep after 15 minutes
with no traffic, and waking it takes up to a minute. Felt waits for it (and
says so), but you can keep it awake around the clock with a free uptime
monitor:

1. Create a free account at [uptimerobot.com](https://uptimerobot.com) (or any
   similar monitor).
2. Add an **HTTP(s)** monitor for `https://<your-service>.onrender.com/health`
   with a **5 minute** interval.

That's all. The free plan's 750 hours a month cover one service running all
month. Render redeploys automatically when `server/relay/` changes on your
default branch.

## Other hosts

The Dockerfile builds a native binary on a `scratch` image, so it runs on any
container host. Point the platform's HTTPS port at the container's `$PORT`.

- **Fly.io:** `fly.toml` is included. Change `app = "felt-relay"` to a name of
  your own, then run `fly launch --copy-config --no-deploy` and `fly deploy`
  from this folder. Fly.io no longer has a free tier for new accounts; the
  smallest machine costs about $2 a month.
- **Your own server or VM** (for example an Oracle Cloud Always Free VM):
  run the container, or `dart compile exe bin/relay.dart` and run the binary,
  behind a reverse proxy such as Caddy that provides HTTPS.

## Tests

```sh
dart test
```
