# Backend repository layout

**Status:** Elixir service scaffold implemented; product domains are planned.

```text
slouching-backend/
  server/              # Elixir/OTP Mix application and loopback status
  peer/                # preserved Rust peer-first experiment
  docs/fichas/         # source PDF, architecture decisions, domain notes
```

The frontend is a separate Rust/Iced repository,
`slouching-org/slouching-frontend`. The Elixir service currently exposes
`/health`, versioned `/api/status`, and a persistent development WebSocket
transport after a binary protobuf handshake at `/ws` on `127.0.0.1:3707`; it has no authenticated gateway,
database, delivery, identity, media, or peer transport. The old Rust `peer/`
crate can also bind port 3707, so do not run both scaffolds together.

The planned server domains are described in the [Elixir backend boundary](elixir-backend.md)
and [ADR 0005](adr-0005-elixir-server-core.md). Code and release compatibility
between the two repositories remain to be specified for product traffic.
