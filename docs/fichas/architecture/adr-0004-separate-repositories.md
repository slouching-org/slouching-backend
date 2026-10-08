# ADR 0004 — Separate frontend and backend repositories

**Status:** accepted by the owner on 2026-10-08.

## Context

The first implementation used one Cargo workspace with `frontend/`,
`backend/peer/`, and a combined Git repository. The owner then directed
the project to use separate organization repositories.

## Decision

Keep native UI code and visual sources in
`slouching-org/slouching-frontend`. Keep the Rust peer core, optional
helper implementations, and backend protocol/security fichas in
`slouching-org/slouching-backend`. The old `slouching-org/slouching`
repository remains a historical snapshot until separately revised.

Build integration must pin compatible revisions and test the pair together.
The preferred application boundary is a Rust library API, not an
unauthenticated loopback HTTP server. The current status endpoint is a
development diagnostic and does not decide the product boundary.

## Consequences

Source ownership is clearer, but cross-repository CI, compatibility,
packaging, and release coordination must be designed. Each release must
identify the exact frontend and core commits it contains. A crew-owned
helper remains optional; repository separation does not make a hosted
backend mandatory.
