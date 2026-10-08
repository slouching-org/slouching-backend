# Backend fichas

Domain-sized notes and decisions for the standalone Slouching backend:

| Domain | Fichas |
| --- | --- |
| Architecture | [Backend specification](architecture/backend.md), [Technology stack](architecture/tech-stack.md), [Original PDF](architecture/sources/README.md), [Workspace](architecture/workspace.md), [Local status API](architecture/local-status-api.md) |
| Identity | [Local identity](identity/identity.md) |
| Groups and MLS | [Commit chain](groups/commits.md), [ADR 0002](groups/adr-0002-designated-committer.md) |
| Delivery | [Replication](delivery/replication.md) |
| Transport | [Routes](transport/routes.md) |
| Media | [Calls](media/calls.md) |

The architecture specification is a target. Domain fichas mark which pieces
exist today and which require implementation or security review. The
[centralized draft](architecture/archive/centralized-draft.md) is historical.

## Accepted decisions

- [ADR 0001: peer-first core](architecture/adr-0001-peer-first.md)
- [ADR 0002: designated committer](groups/adr-0002-designated-committer.md)
- [ADR 0003: Rust/Iced client](architecture/adr-0003-rust-iced-client.md)
- [ADR 0004: separate repositories](architecture/adr-0004-separate-repositories.md)
