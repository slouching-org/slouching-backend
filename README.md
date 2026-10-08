# Slouching backend

This is the standalone Rust backend workspace for Slouching's peer-first
architecture. Each friend's device is intended to own its keys, MLS state,
encrypted local history, and outgoing queue. A crew-owned helper may later
assist with rendezvous, ciphertext delivery, or media relay; it is optional.

**Current status:** an early local scaffold, not a secure messaging backend.
The process exposes a loopback-only status API and a pure policy gate for
**already verified** MLS commit envelopes. It does not perform MLS,
cryptography, persistence, peer transport, or calls.

## Run

```sh
cargo test --workspace
cargo run -p slouching-peer
curl http://127.0.0.1:3707/health
curl http://127.0.0.1:3707/api/status
```

The server binds to `127.0.0.1:3707`. It does not serve the frontend or
expose a public listener. The separate frontend lives in
[`slouching-org/slouching-frontend`](https://github.com/slouching-org/slouching-frontend).
Cross-repository integration is a future protocol contract; the static
frontend preview currently reports the core as unavailable.

## Structure

```text
peer/                 Rust peer core and local status process
docs/fichas/          architecture, identity, groups, delivery, transport, media
```

Read the [fichas index](docs/fichas/README.md), the
[backend architecture](docs/fichas/architecture/backend.md), and the
[designated-committer ADR](docs/fichas/groups/adr-0002-designated-committer.md).
