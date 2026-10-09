# Device directory boundary

**Status:** PostgreSQL schema and candidate key validation implemented;
enrollment, proof of possession, lookup, MLS KeyPackages, and authorization
are not implemented.

The `devices` table reserves one Ed25519 signing public key per device ID.
It stores no private key. The unique index prevents two rows from claiming
the same public key. The Elixir schema checks that a candidate key has
exactly 32 bytes; length alone does not establish that a device owns the
private key or that it may join a crew.

No HTTP or WebSocket route writes or reads this table. A later enrollment
protocol must bind a fresh server challenge, intended server, protocol
version, device public key, and expiry into a signed transcript. It must
also define who may authorize enrollment, how invitations expire or are
revoked, how a replaced or lost device key is handled, and how another
member verifies a fingerprint. Device proof and crew authorization are
distinct checks. The current WebSocket `ServerHello` remains an unauthenticated
transport diagnostic, and status capabilities remain unavailable.

Set `SLOUCHING_DATABASE_URL` to a PostgreSQL URL before starting the server
or running `mix ecto.create` and `mix ecto.migrate` from `server/`. The Repo
is optional for the present transport scaffold; product directory features
will require durable storage and an explicit enrollment protocol.
