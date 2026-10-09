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
transport alive. It has no identity, MLS, messaging, persistence,
authenticated WebSocket gateway, P2P transport, or calls. The
existing `peer/` Rust crate is preserved as a historical scaffold and is
not the approved server core.

## Run the Elixir scaffold

```sh
cd server
mix deps.get
mix test
mix run --no-halt
```

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

## Repository layout

```text
server/              Elixir/OTP server scaffold and loopback status
proto/               Shared v1 protobuf handshake schema
peer/                Preserved Rust peer-first experiment
docs/fichas/         Source notes, architecture decisions, domain plans
```

See the [technology plan](docs/fichas/architecture/tech-stack.md) and
[fichas index](docs/fichas/README.md). Documents based on ADR 0001's removal
of the Elixir server need reconciliation before implementation.
