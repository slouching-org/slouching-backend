# Technology stack and maturity

**Status:** explicit architecture plan; implementation is still a scaffold.
Read the [complete source PDF](sources/README.md) alongside the decisions
below. The PDF's library list says it was written from memory, so dependency
choices are candidates until feasibility and security review.

| Layer | Planned technology | Decision / current state |
| --- | --- | --- |
| Desktop UI | **Rust + Iced**, with wgpu for rendering | Retained from the source PDF; [ADR 0003](adr-0003-rust-iced-client.md). The frontend repo now has a native scaffold; the JS design prototype is isolated under `prototypes/web/`. |
| Peer core and runtime | **Rust + Tokio** | Chosen. The current `peer/` crate has only a commit-chain policy gate and loopback status process. |
| Peer data transport | QUIC, with **iroh** as a candidate | Planned. Direct routes first; any relay must be explicitly crew-authorized. Library/version not yet selected. |
| Group cryptography | MLS, with **OpenMLS** as a candidate | Planned. No working MLS, credential validation, key storage, or recovery today. |
| Media protection | **SFrame** keys derived from a separate call MLS group | Planned; implementation and threat review pending. |
| Calls | WebRTC sans-IO, **str0m** candidate | Planned. Capture/codec dependencies in the PDF are candidates, not approved versions. |
| Local state | Encrypted SQLite / SQLCipher candidate plus OS key store | Planned. No persistent identity, message database, or SQLCipher integration today. |
| Optional helper | Headless member-operated peer, PC or VPS | Chosen role, not built. A protocol-compatible Elixir implementation remains possible later, never required for normal operation. |
| Central Elixir/PostgreSQL service | Mandatory in original PDF | **Superseded** by [ADR 0001](adr-0001-peer-first.md). Do not add it as a startup dependency. |
| Frontend/backend boundary | Rust library API preferred; versioned contract to be specified | Current `GET /api/status` is a diagnostic endpoint only. It is not a safe production IPC or the intended chat/call API. |

The target installed application runs the UI and peer core on each
participant's computer. Splitting source into
`slouching-frontend` and `slouching-backend` does **not** turn the backend
into a third-party server. The preferred packaging path is a desktop binary
that links a version-pinned Rust core library from the backend repository.
This requires a reviewed public Rust API, version compatibility checks, and
build/release plumbing before implementation. The current two-process
HTTP preview is not that architecture.

See [ADR 0002](../groups/adr-0002-designated-committer.md) for MLS commit
ordering and [ADR 0004](adr-0004-separate-repositories.md) for repository
ownership.
