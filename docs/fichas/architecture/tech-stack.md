# Technology stack and maturity

**Status:** source-aligned architecture direction with a minimal Elixir
server scaffold. See [ADR 0005](adr-0005-elixir-server-core.md) and the
[owner's source PDF](sources/README.md).

| Layer | Direction | Current state |
| --- | --- | --- |
| Desktop UI and client core | Rust/Iced and Tokio | Native frontend in separate repository; local HTTP status and protobuf WebSocket handshake only. |
| Client cryptography and P2P | Rust; OpenMLS, iroh, SFrame candidates | Not implemented. PDF dependency list is provisional. |
| Server core | Elixir/OTP, supervised processes | `server/` Mix app with Bandit, development status, and local WebSocket transport session. |
| Gateway | Binary WebSocket with shared protobuf schema | Bandit/WebSock handshake v1 and control Ping/Pong only; no authenticated session or application traffic. |
| Device directory | Ecto with local SQLite; PostgreSQL deployment option | Optional helper Repo and public-key table; no enrollment or lookup. |
| Delivery and group ordering | Elixir processes, Ecto/Oban candidate | Not implemented; no queue, ACK, or ordering. |
| Group media | Elixir `ex_webrtc` candidate | Not implemented. |
| Relay | Member-operated TURN/iroh relay candidate | Not implemented. |
| Historic Rust `peer/` crate | Prior peer-first scaffold | Preserved for review, not the approved Elixir server core. |

The source PDF describes a Rust client that connects directly to peers when
possible and an Elixir server for offline delivery, MLS ordering, group SFU,
and relay support. Deployment may be self-hosted by a member; availability
depends on the services actually deployed and reachable. The current code
has none of those production functions. See the [status and handshake contract](local-status-api.md)
for the working development integration surface.
