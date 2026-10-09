# Local status API

**Status:** implemented by the Elixir server scaffold as a development-only loopback endpoint.

`GET http://127.0.0.1:3707/api/status` returns JSON contract version 1:

```json
{
  "contract_version": 1,
  "backend": "elixir_scaffold",
  "identity": "not_implemented",
  "messaging": "not_implemented",
  "calls": "not_implemented",
  "peer_connections": 0
}
```

`GET /health` returns `ok`. Bandit binds only to `127.0.0.1:3707`.
These routes prove only that the local process answers. They do not
authenticate a peer or provide messaging, MLS, media, delivery, or a
production client/server protocol. The Rust/Iced client may use the versioned
snapshot for a development status view; it must keep unavailable features
disabled. The original source proposes a binary WebSocket/protobuf gateway.
That protocol still needs design and implementation before product traffic.

The preserved Rust `peer/` crate has its own older diagnostic route on the
same port. Do not run it together with the Elixir server. It is not the
authoritative backend status for the current architecture.

## Binary WebSocket handshake

`ws://127.0.0.1:3707/ws` accepts one binary protobuf `ClientFrame` carrying
`ClientHello { protocol_version: 1 }`. The server responds with one binary
`ServerFrame` carrying `ServerHello { protocol_version: 1,
server_role: "elixir", identity_available: false, messaging_available: false,
calls_available: false }` and keeps the WebSocket open. The client sends
WebSocket control Ping frames every 5 seconds; Bandit replies with control
Pong frames. The server closes with code `1001` and reason `heartbeat timeout`
after 15 seconds without Ping. A missing hello closes after 5 seconds with
code `1001` and reason `hello timeout`. The adapter's idle timeout is 20
seconds so these explicit deadlines apply first. Other versions receive
`VersionError { supported_version: 1 }` before normal closure. Malformed protobuf,
missing `ClientHello`, and text frames are rejected with a WebSocket protocol
close; data frames after hello close with code `1003` because product traffic
is not implemented. The [shared schema](../../../proto/slouching/v1/handshake.proto) is the
wire source of truth; `server/lib/slouching/v1/handshake.pb.ex` is generated
from it with `protoc-gen-elixir` 0.17.0.

This is a development transport session only. Its role and capability flags
do not authenticate the server. A live Ping/Pong exchange means only the
loopback transport is responsive; it does not prove peer connectivity or
service capabilities. The endpoint carries no messages, calls, MLS state,
or identity material. A real WebSocket check kept a session open for 16.4
seconds with four Pings and matching Pongs; a silent session closed with
`1001 heartbeat timeout`.
