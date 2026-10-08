# Local status API

**Status:** implemented as a development-only loopback endpoint.

`GET http://127.0.0.1:3707/api/status` returns JSON:

```json
{
  "mode": "local_scaffold",
  "identity": "not_implemented",
  "messaging": "not_implemented",
  "calls": "not_implemented",
  "peer_connections": 0
}
```

`GET /health` returns `ok`. The server binds only to
`127.0.0.1:3707`. There is no authentication, network peer endpoint, or
public API here; the status route exposes only implementation state.

The standalone static frontend runs on a different origin, so it cannot
consume this endpoint in a browser without an explicit local integration
layer. No cross-origin access is enabled by default. A future client/core
contract must define versioning, authentication, event delivery, and
capability-specific state before extending this API.
