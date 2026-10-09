# ADR 0005 — Elixir server core and Rust client

**Status:** accepted architecture correction, 2026-10-08.

## Context

The owner's 11-page architecture PDF specifies a Rust/Iced client and an
Elixir server. Pages 2, 8, and 11 assign offline delivery, MLS delivery
ordering, group SFU, and gateway duties to Elixir. The earlier peer-first
interpretation removed that server role and led to a Rust-only backend
scaffold. The owner explicitly clarified that Elixir remains the backend
core and Rust is the client.

## Decision

Build the server core in Elixir/OTP. Keep the Rust/Iced client and its Rust
network, media, and cryptography components where the PDF assigns them.
Peers may communicate directly when routes and protocol allow. An Elixir
service supplies the server roles required by a feature; a member may
self-host the service. This decision does not imply that a Slouching-operated
public service exists or that offline delivery works without a reachable
server or another implemented route.

The `server/` Mix application is the starting point. Its loopback HTTP
status and binary WebSocket/protobuf version handshake are diagnostic only.
Product traffic requires a reviewed authenticated protocol, persistence,
identity/MLS validation boundaries, and security tests. None are present
today.

## Consequences

The existing Rust `peer/` crate and its policy gate remain in the repository
for review. They are a historical scaffold and are not evidence of a
production Rust backend. ADR 0001's removal of the Elixir server role and
the corresponding parts of `backend.md` are superseded by this decision.
Detailed delivery, self-hosting, trust, and availability requirements need
reconciliation with the original PDF before those features are built.
