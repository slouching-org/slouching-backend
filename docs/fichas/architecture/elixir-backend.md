# Elixir service backend

**Status:** architecture direction accepted; local status and persistent
WebSocket transport after protobuf handshake are implemented. This is not a messaging or call
service.

## Boundary

The [source architecture](sources/README.md), especially
[page 8](sources/page-08.md) and [page 11](sources/page-11.md), assigns these
server responsibilities to Elixir/OTP:

| Domain | Target responsibility | Current implementation |
| --- | --- | --- |
| Gateway | Binary client/server WebSocket and signaling | Local protobuf handshake plus Ping/Pong transport only; signaling not implemented |
| Directory | Device public keys and MLS KeyPackages | PostgreSQL device public-key schema only; no enrollment, lookup, or KeyPackages |
| Delivery | Commit ordering, per-device encrypted inbox, ACK and expiry | Not implemented |
| Storage | PostgreSQL/Ecto, jobs with Oban, encrypted blob references | Optional Ecto/PostgreSQL Repo and first migration; jobs and blobs absent |
| Calls | Admission and SFU coordination with `ex_webrtc`; TURN/relay integration | Not implemented |
| Runtime | Supervision, telemetry, and later cluster coordination | Local Elixir application scaffold only |

The Rust/Iced client keeps private keys, MLS cryptography, local encrypted
storage, direct peer data transport, and media handling. The Elixir service
may route ciphertext and media packets but must not claim to read content or
hold client secrets. Its unavoidable metadata and availability limits need
explicit treatment before a public release.

The initial `GET /api/status` exchange is a local development diagnostic. A
binary WebSocket/protobuf handshake now checks protocol version and service
role, then maintains an unauthenticated transport session with Ping/Pong.
These report process availability and local reachability only. They do not
authenticate users, establish a secure channel, or send messages. Future
product WebSocket/protobuf contracts must specify identity, authorization,
versioning, retries, ordering, and error semantics before use.

## Deployment assumption

The service can be operated by a member or crew on a PC or VPS; no
vendor-operated Slouching service is required. Direct peer routes remain a
goal. Behavior when the service is unreachable must be defined feature by
feature; offline delivery, directory lookup, and group-call SFU cannot be
promised without available infrastructure.
