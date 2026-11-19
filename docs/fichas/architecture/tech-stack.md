# Technology stack and maturity

**Status:** optional Elixir helper with pairing, ciphertext delivery and experimental SFU services. See [ADR 0005](adr-0005-elixir-server-core.md) and the
[owner's source PDF](sources/README.md).

| Layer | Direction | Current state |
| --- | --- | --- |
| Desktop UI and client core | Rust/Iced and Tokio | Native client is implemented in the separate frontend repository. |
| Client cryptography and P2P | Rust; OpenMLS, iroh, SFrame | OpenMLS, SQLCipher, pinned direct QUIC messaging and MLS delivery are implemented in the frontend. |
| Client media | Rust; CPAL, Opus, SFrame, WebRTC | Two-party call, temporary call chat and protected camera/screen/window video have local loopback coverage; physical-device paths remain unvalidated. |
| Server core | Elixir/OTP, supervised processes | `server/` Mix app with supervised Bandit diagnostics, SPAKE2 rendezvous, signed-ciphertext mailbox and experimental SFU call coordinator. |
| Gateway | Binary WebSocket with shared protobuf schema | Protocol v2 Ed25519 device challenge, Ping/Pong and authenticated SFU signaling; proof establishes key possession, not human trust or MLS membership. |
| Device directory | Ecto with local SQLite; PostgreSQL deployment option | Helper defaults to SQLite; PostgreSQL is selectable by URL but its migration directory is missing. Public-key table exists without enrollment or lookup routes. |
| Delivery | Direct peer delivery and optional delegated ciphertext copies | Signed mailbox upload/list/ACK, recipient authentication, quota and expiry are implemented. The Rust client supports opt-in fallback upload and manual fetch with persistence before helper ACK; helper ACK confirms copy removal, not recipient processing. |
| MLS ordering | Designated member device per group; other clients validate | Commit creation and validation remain client responsibilities. The helper has no authority to create Commits or decide group state. |
| Group media | Elixir `ex_webrtc` SFU; SFrame remains end-to-end | Signed-roster admission, SDP/ICE signaling and opaque RTP/DataChannel forwarding are implemented; the helper does not independently verify MLS membership. A local three-client test covers protected audio. Multiparty chat/video integration, physical devices and cross-network calls remain unverified. |
| Relay | Optional member-operated Iroh relay; SFU for calls | The Rust client has Iroh relay URL/token settings and local message/ACK coverage. The Elixir helper provides experimental SFU services, not a TURN or Iroh relay server; remote deployment remains unverified. |
| Historic Rust `peer/` crate | Prior peer-first scaffold | Preserved for review, not the approved Elixir server core. |

The source PDF describes a Rust client that connects directly to peers when
possible and an Elixir server for offline delivery, MLS ordering, group SFU,
and relay support. Deployment may be self-hosted by a member; availability
depends on the services actually deployed and reachable. The implemented helper
services remain optional; clients own MLS ordering and cryptographic state. Local
integration coverage does not establish production readiness or remote connectivity.
See the [status and handshake contract](local-status-api.md) for the current interface.
