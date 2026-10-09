# Slouching backend

The current architecture assigns the server core to **Elixir/OTP** and the
desktop client to **Rust/Iced**. The [owner's architecture PDF](docs/fichas/architecture/sources/architecture-p2p-v0.1.pdf)
describes direct peer communication where possible and Elixir services for
offline delivery, MLS ordering, group calls, and relay support. A member may
self-host those services. [ADR 0005](docs/fichas/architecture/adr-0005-elixir-server-core.md)
records the correction from the earlier Rust-only backend interpretation.

**Current state:** `server/` is a minimal Elixir Mix application with a
supervised Bandit HTTP diagnostic and a persistent local WebSocket transport
session after a protobuf v1 handshake. Control Ping/Pong frames keep the
transport alive. It has no authenticated identity, MLS, messaging,
authenticated WebSocket gateway, P2P transport, or calls. The
existing `peer/` Rust crate is preserved as a historical scaffold and is
not the approved server core.

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
port.

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
handshake. It checks protocol version and reports unavailable features, then
stays open while the client sends WebSocket Ping frames every 5 seconds. The
server closes an idle session after 15 seconds without Ping. This is only
transport reachability; application traffic is still unimplemented. A real
WebSocket smoke test kept the connection alive for 16.4 seconds with four
Pings and observed Pong for each. `peer/` also binds port
3707 when run, so only start one scaffold at a time.

The service starts the SQLite Repo by default after setup, or the PostgreSQL
Repo when configured as above. The [device directory boundary](docs/fichas/identity/device-directory.md)
still applies before adding enrollment or lookup routes.

## Repository layout

```text
server/              Elixir/OTP server scaffold, loopback transport, and directory schema
proto/               Shared v1 protobuf handshake schema
peer/                Preserved Rust peer-first experiment
docs/fichas/         Source notes, architecture decisions, domain plans
```

See the [technology plan](docs/fichas/architecture/tech-stack.md) and
[fichas index](docs/fichas/README.md). Documents based on ADR 0001's removal
of the Elixir server need reconciliation before implementation.
