# Backend repository layout

**Status:** optional Elixir helper with pairing, ciphertext delivery, and experimental SFU services.

```text
slouching-backend/
  server/              # Elixir/OTP Mix application and loopback status
  peer/                # preserved Rust peer-first experiment
  docs/fichas/         # source PDF, architecture decisions, domain notes
```

The frontend is a separate Rust/Iced repository,
`slouching-org/slouching-frontend`. The Elixir service currently exposes
`/health`, versioned `/api/status`, SPAKE2 pairing rendezvous, a signed opaque-copy
mailbox, and experimental SFU signaling and encrypted-media forwarding. The `/ws`
gateway uses a protobuf v2 device-key challenge; SFU admission separately checks
signed roster consistency, without independently verifying MLS membership.
SQLite is the default helper store; `SLOUCHING_DATABASE_URL` selects PostgreSQL,
whose migration directory is currently missing. There is no device enrollment
or lookup route, required identity directory, or direct P2P transport in the
helper. The old Rust `peer/`
crate can also bind port 3707, so do not run both scaffolds together.

The server boundaries and planned domains are described in the [Elixir backend boundary](elixir-backend.md)
and [ADR 0005](adr-0005-elixir-server-core.md). The shared protobuf schema and HTTP helper contracts describe the current
client/backend interfaces; remote deployment and physical-device validation remain open.
