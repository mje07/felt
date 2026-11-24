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

## Deploy to Fly.io (free allowance)

1. Install `flyctl` and sign in with `fly auth login`.
2. In `fly.toml`, change `app = "felt-relay"` to a name of your own.
3. From this folder, run:

   ```sh
   fly launch --copy-config --no-deploy
   fly deploy
   ```

4. In Felt, set **Invite-code server** to `your-app-name.fly.dev`. Everyone at
   the table needs the same address.

The Dockerfile builds a native binary on a `scratch` image, so you can deploy
it on any container host (Railway, Render, a VPS) the same way. Point the
platform's HTTPS port at the container's `$PORT`.

Check that it's up at `https://your-app-name.fly.dev/health`.

## Tests

```sh
dart test
```
