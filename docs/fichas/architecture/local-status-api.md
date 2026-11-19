# Local status API

**Status:** implemented by the optional Elixir helper; loopback is the default listener.

`GET http://127.0.0.1:3707/api/status` returns JSON contract version 1:

```json
{
  "contract_version": 1,
  "backend": "elixir_scaffold",
  "identity": "not_implemented",
  "messaging": "not_implemented",
  "calls": "available",
  "peer_connections": 0
}
```

`GET /health` returns `ok`. Bandit defaults to `127.0.0.1:3707`; a configured
non-loopback bind requires TLS.
These routes prove only that the local process answers. They do not
authenticate a peer or provide messaging, MLS, media, delivery, or a
production client/server protocol. The Rust/Iced client may use the versioned
snapshot for a development status view. `calls: available` means only that the
development gateway exposes experimental SFU signaling; the helper does not
independently verify the signed roster against MLS membership.

The preserved Rust `peer/` crate has its own older diagnostic route on the
same port. Do not run it together with the Elixir server. It is not the
authoritative backend status for the current architecture.

## Binary WebSocket handshake

`ws://127.0.0.1:3707/ws` accepts a binary `ClientFrame.hello` with protocol
version 2 and a 32-byte device public key. `ServerFrame.hello` includes a fresh
32-byte nonce. The Rust client signs
`"slouching/gateway-auth/v1\0" || uint32_be(version) || device_public_key || nonce`
with its Ed25519 identity and sends `ClientFrame.auth_proof`. Elixir verifies
the signature and returns `ServerFrame.authenticated`, echoing the device key
and `application_routes_available: true`. This proves key possession only;
it does not authenticate a human or server, establish group membership, or
authorize product actions. Missing or invalid proofs close the socket;
unanswered challenges expire after 5 seconds.

After authentication, the client sends WebSocket control Ping frames every 5
seconds; Bandit replies with Pong. The server closes with code `1001` after 15
seconds without Ping. A missing hello closes after 5 seconds. Other versions
receive `VersionError { supported_version: 2 }`; product data frames beyond
the experimental SFU signaling route remain unavailable. The [shared schema](../../../proto/slouching/v1/handshake.proto)
is the wire source of truth, with the Elixir protobuf module in
`server/lib/slouching/v1/handshake.pb.ex`, generated with `protoc-gen-elixir` 0.17.0.
