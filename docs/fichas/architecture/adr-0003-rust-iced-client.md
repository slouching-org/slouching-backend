# ADR 0003 — Native client in Rust and Iced

**Status:** accepted from the owner's original architecture source;
reaffirmed after review of the current frontend repository.

## Context

The [complete original PDF](sources/README.md) explicitly specifies a
Rust/Iced client and Rust/Tokio core. Its mandatory Elixir/PostgreSQL
server was later superseded by the peer-first decision, but the owner
did not replace the client technology choice. The first frontend repo
mistakenly put a vanilla JavaScript design preview at its root without
documenting this distinction.

## Decision

The product desktop UI is Rust/Iced. The peer core is Rust/Tokio and is
intended to be linked through a versioned Rust library API. The existing
HTML/CSS/JavaScript screens are **visual prototypes only**; they live
under `prototypes/web/` and are not the product runtime.
Iced UI state must be derived from authoritative core state, not mock
transport or cryptographic values.

## Consequences

The native UI must be built and visually compared with the eleven screen
references. Media rendering, accessibility, OS capture permissions,
packaging, and the core API need separate implementation and validation.
The current JS preview remains useful as a visual benchmark; it cannot
pass functional or security acceptance.
