# Delivery mailbox HTTP v1

This optional helper API carries opaque delegated MLS copies. It does not
replace direct peer transport, own group keys, decrypt events, or provide
message history. The Rust client must verify the event digest and persist the
copy locally before sending its ACK.

## Upload

`POST /api/delivery/copies` accepts JSON:

```json
{"copy":"<base64 SLDG v1 envelope>"}
```

The envelope is limited to 96 KiB and must contain a valid author Ed25519
grant, matching event metadata, and an expiry no more than 30 days ahead. The
grant is the upload authorization. The helper stores the original bytes
without decrypting them. The same recipient, event ID, and bytes are
idempotent; reusing that event ID with different bytes returns `409`.

Successful responses are `201` with `{"status":"stored"}` or
`{"status":"already_stored"}`. Each recipient is limited to 64 MiB and
4,096 live copies. Expired copies are removed during mailbox operations.

## List

`GET /api/delivery/copies?after_id=0&limit=16` returns up to 16 copies for the
signing device. `after_id` is the numeric cursor returned by the helper;
`next_after_id` is `null` when the page is complete. Copy payloads are
base64-encoded original envelopes.

## Acknowledge

`POST /api/delivery/copies/<event-id-lowercase-hex>/ack` has an empty body.
ACK is idempotent and always returns `204` for a valid recipient request,
including when the copy has already expired or been removed. The client must
only send it after local persistence succeeds.

## Request authentication

List and ACK use these lowercase hexadecimal headers:

- `x-slouching-device`: 32-byte Ed25519 public key (64 hex characters)
- `x-slouching-timestamp`: Unix seconds, within 60 seconds of helper time
- `x-slouching-nonce`: fresh random 32-byte value (64 hex characters)
- `x-slouching-signature`: Ed25519 signature (128 hex characters)

The signature is over this exact byte sequence, with no trailing newline:

```text
slouching/delivery-http-request/v1\0<METHOD>\n<PATH-AND-QUERY>\n<TIMESTAMP>\n<NONCE-LOWERCASE-HEX>\n<SHA256-BODY>
```

Angle-bracketed parts are replaced by their bytes. `SHA256-BODY` means the
raw 32-byte SHA-256 digest of the HTTP body, not its hexadecimal form. The
path includes the query string in transmitted order. The helper accepts each
`(device, nonce)` once and retains nonces for 120 seconds. Invalid, stale, or
replayed requests return `401`.

This contract currently has backend tests against SQLite. The desktop HTTP
client and user-facing helper configuration remain in development.
