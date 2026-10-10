# Slouching backend

The current architecture assigns the server core to **Elixir/OTP** and the
desktop client to **Rust/Iced**. The [owner's architecture PDF](docs/fichas/architecture/sources/architecture-p2p-v0.1.pdf)
describes direct peer communication where possible and Elixir services for
offline delivery, MLS ordering, group calls, and relay support. A member may
self-host those services. [ADR 0005](docs/fichas/architecture/adr-0005-elixir-server-core.md)
records the correction from the earlier Rust-only backend interpretation.

**Current state:** `server/` is an Elixir Mix application with a supervised
Bandit diagnostic API, a persistent local WebSocket transport after a
protobuf v2 handshake, an experimental in-memory SPAKE2 rendezvous API, and
an optional SQLite/PostgreSQL encrypted-copy mailbox API.
The rendezvous stores bounded exchange messages for 120 seconds and permits
one attempt per session. It also relays opaque encrypted identity statements
after both key confirmations. The Rust/Iced identity screen uses it for
experimental SPAKE2 code pairing and validates transcript-bound signed device
proofs. That flow does not authenticate a human or automatically trust a
contact. The mailbox stores only bounded signed opaque copies, enforces
per-device quotas and expiry, and requires Ed25519 proof of possession to list
or ACK. The Rust/Iced client now supports opt-in remote helper settings, signed
fallback uploads, and manual fetch with local persistence before helper ACK.
Remote deployment and cross-device runtime validation remain open. The backend has
no product messaging routes, P2P transport, call admission, or SFU. The
frontend does implement a two-party direct-call slice; the participant limit
and remaining work are tracked in [the calls ficha](docs/fichas/media/calls.md). The
existing `peer/` Rust crate is preserved as a historical scaffold and is
not the approved server core.

`ex_webrtc` 0.17.0 is pinned as the planned Elixir SFU runtime and compiles in
both the test application and packaged release. No SFU rooms, call admission,
signaling, RTP forwarding, or Rust client route uses it yet.

From the project root, run `./scripts/smoke-pairing-e2e.sh` to exercise
two Rust client roles against a live local Elixir helper. The test validates
the pairing protocol and mismatched-code rejection with test identities; it
does not validate remote helper deployment or physical devices.

Run `./scripts/smoke-gateway-auth-e2e.sh` from the project root to verify the
Ed25519 device challenge over a live WebSocket using the Rust Iroh signer and
Elixir OTP verifier.

The first directory storage increment adds an optional SQLite/Ecto repo for
local development, the `devices` table, and a 32-byte public signing key
constraint. PostgreSQL remains available for a deployment that chooses to run
the optional helper. This schema exposes no enrollment endpoint and does not
authenticate or authorize any device.

## Run the Elixir scaffold

```sh
cd server
mix deps.get
mix ecto.create
mix ecto.migrate --pool-size 1
mix test
mix run --no-halt
```

For a fresh checkout, `mix setup` runs dependency setup and the two Ecto
database tasks. Local development uses SQLite at
`server/priv/repo/slouching_dev.sqlite3`; it creates the file on first use and
does not need a PostgreSQL service. The local SQLite Repo uses one connection
because the optional helper has no high-concurrency workload. Run
`mix ecto.migrate --pool-size 1` after new migrations.
This database belongs to the optional Elixir helper and is not a per-user
desktop-client database; peer-first operation does not require that helper.
Run `server/scripts/smoke-local-sqlite.sh` to verify setup and the local HTTP
status endpoints against an isolated temporary SQLite database. It unsets
`SLOUCHING_DATABASE_URL`, selects an available loopback port, and removes the
database and server process on exit. `SLOUCHING_SQLITE_PATH` and
`SLOUCHING_PORT` are optional local overrides for the database file and HTTP
port. `SLOUCHING_BIND_IP` defaults to `127.0.0.1`; a non-loopback bind requires
TLS. To serve HTTPS directly, set both PEM paths:

```sh
export SLOUCHING_BIND_IP=0.0.0.0
export SLOUCHING_TLS_CERTFILE=/etc/letsencrypt/live/helper.example/fullchain.pem
export SLOUCHING_TLS_KEYFILE=/etc/letsencrypt/live/helper.example/privkey.pem
mix run --no-halt
```

The same listener serves the mailbox and pairing APIs over HTTPS. For a TLS
terminating proxy, keep Bandit bound to loopback and proxy to its HTTP port.
The SPAKE2 rendezvous API contract and HTTP examples are in the
[main project's pairing-rendezvous-v1.md](https://github.com/slouching-org/slouching/blob/main/docs/fichas/identity/pairing-rendezvous-v1.md).

## Build and run a packaged helper

The Mix release contains the optional Elixir service and its SQLite or
PostgreSQL adapter. Create the database directory first, then build and migrate
before starting the long-running service:

```sh
MIX_ENV=prod mix release
export SLOUCHING_SQLITE_PATH=/var/lib/slouching/helper.sqlite3
_build/prod/rel/slouching_server/bin/slouching_server eval 'SlouchingServer.Release.migrate()'
_build/prod/rel/slouching_server/bin/slouching_server start
```

`start` stays in the foreground and stops cleanly on SIGTERM or Ctrl+C, so a
service manager can supervise it. Set the TLS and bind variables in the same
environment for a remotely reachable helper. During an upgrade, stop the
service, install the new release, run the migration command, and start it
again. `server/scripts/smoke-release.sh` builds a release, migrates an isolated
SQLite database, and verifies the packaged HTTP process.

To choose PostgreSQL for a deployment, set `SLOUCHING_DATABASE_URL` to a
PostgreSQL URL and optionally `SLOUCHING_DATABASE_POOL_SIZE` (default `5`),
then run `MIX_ENV=prod mix ecto.create` and `MIX_ENV=prod mix ecto.migrate`
with the same environment before starting the service. When the URL is absent,
the runtime selects the local SQLite Repo. The PostgreSQL Repo is a deployment
option and is not started or contacted in the default local configuration.

In another terminal:

```sh
curl http://127.0.0.1:3707/health
curl http://127.0.0.1:3707/api/status
```

The [versioned status response](docs/fichas/architecture/local-status-api.md)
reports only process availability and unavailable capabilities. The native
Rust/Iced client can use the binary protobuf `ws://127.0.0.1:3707/ws`
handshake. It checks protocol version and proves possession of the local
Ed25519 device key using a fresh challenge, then stays open while the client
sends WebSocket Ping frames every 5 seconds. This grants no product
authorization and carries no application traffic. The server closes an idle
session after 15 seconds without Ping. `peer/` also binds port
3707 when run, so only start one scaffold at a time.

The experimental `POST /api/pairing-sessions` route creates a volatile
two-minute rendezvous session. Its API relays one SPAKE2 message, one
confirmation message, and one encrypted identity statement from each role;
`GET` polls for the other role's message and `DELETE` cancels the session. The
helper limits itself to 10,000 concurrent sessions and clears state on process
restart. The Rust/Iced identity screen uses this route for experimental
SPAKE2 code pairing; physical-device use and remote deployment still need
validation.

The optional delivery API is documented in the
[mailbox HTTP v1 contract](docs/fichas/delivery/mailbox-http-v1.md). Uploads
require an author-signed delegated copy grant. Listing and ACK requests use
short-lived, nonce-protected Ed25519 request signatures. Mailbox ACK means the
helper removed or accepted removal of its stored copy; it does not mean the
recipient processed or read a message. The client persists a fetched MLS event
before sending this ACK; the separate MLS/device receipt still depends on
successful processing by the recipient.

The service starts the SQLite Repo by default after setup, or the PostgreSQL
Repo when configured as above. The [device directory boundary](docs/fichas/identity/device-directory.md)
still applies before adding enrollment or lookup routes.

## Repository layout

```text
server/              Elixir/OTP diagnostics, experimental SPAKE2 rendezvous, and directory schema
proto/               Shared v1 protobuf handshake schema
peer/                Preserved Rust peer-first experiment
docs/fichas/         Source notes, architecture decisions, domain plans
```

See the [technology plan](docs/fichas/architecture/tech-stack.md) and
[fichas index](docs/fichas/README.md). Documents based on ADR 0001's removal
of the Elixir server need reconciliation before implementation.
