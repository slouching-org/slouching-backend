# Standalone backend workspace

**Status:** initial repository layout implemented.

```text
slouching-backend/
  Cargo.toml
  Cargo.lock
  peer/
    Cargo.toml
    src/
      lib.rs       # policy gate for already verified commit envelopes
      main.rs      # loopback-only health and status API
  docs/fichas/     # domain notes and ADRs
```

The frontend is a separate repository, `slouching-org/slouching-frontend`.
The backend does not serve its files. The current process is neither a
mandatory central server nor a peer network implementation; it only runs
locally and reports missing capabilities accurately.

Future crates may separate identity, encrypted storage, MLS adapters,
authenticated transport, replication, files, and call signaling. Those
modules must have reviewed contracts and tests before being presented as
implemented features.
