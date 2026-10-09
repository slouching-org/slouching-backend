# Backend fichas

Domain-sized notes and decisions for the standalone Slouching backend:

| Domain | Fichas |
| --- | --- |
| Architecture | [Elixir backend boundary](architecture/elixir-backend.md), [Technology stack](architecture/tech-stack.md), [Original PDF](architecture/sources/README.md), [Workspace](architecture/workspace.md), [Local status API](architecture/local-status-api.md) |
| Identity | [Local identity](identity/identity.md) |
| Groups and MLS | [Commit chain](groups/commits.md), [ADR 0002](groups/adr-0002-designated-committer.md) |
| Delivery | [Replication](delivery/replication.md) |
| Transport | [Routes](transport/routes.md) |
| Media | [Calls](media/calls.md) |

The [peer-first backend specification](architecture/backend.md) predates the
Elixir correction in ADR 0005 and is historical where it removes the server
role. Domain fichas require reconciliation before implementation. The
[centralized draft](architecture/archive/centralized-draft.md) is also
historical; consult the source PDF and current ADR for the active direction.

## Accepted decisions

- [ADR 0001: peer-first core, partially superseded](architecture/adr-0001-peer-first.md)
- [ADR 0002: designated committer](groups/adr-0002-designated-committer.md)
- [ADR 0003: Rust/Iced client](architecture/adr-0003-rust-iced-client.md)
- [ADR 0004: separate repositories](architecture/adr-0004-separate-repositories.md)
- [ADR 0005: Elixir server core and Rust client](architecture/adr-0005-elixir-server-core.md)
