#!/usr/bin/env bash
set -euo pipefail

server_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
temp_dir="$(mktemp -d)"
server_pid=""

cleanup() {
  if [[ -n "${server_pid}" ]] && kill -0 "${server_pid}" 2>/dev/null; then
    kill "${server_pid}" 2>/dev/null || true
    wait "${server_pid}" 2>/dev/null || true
  fi
  rm -rf -- "${temp_dir}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

database_path="${temp_dir}/smoke.sqlite3"
port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
database_log="${temp_dir}/database.log"

cd "${server_root}"
if ! env -u SLOUCHING_DATABASE_URL MIX_ENV=dev \
  SLOUCHING_SQLITE_PATH="${database_path}" \
  mix ecto.create >"${database_log}" 2>&1; then
  cat "${database_log}" >&2
  exit 1
fi
if ! env -u SLOUCHING_DATABASE_URL MIX_ENV=dev \
  SLOUCHING_SQLITE_PATH="${database_path}" \
  mix ecto.migrate --pool-size 1 >>"${database_log}" 2>&1; then
  cat "${database_log}" >&2
  exit 1
fi

(exec env -u SLOUCHING_DATABASE_URL MIX_ENV=dev \
  SLOUCHING_SQLITE_PATH="${database_path}" \
  SLOUCHING_PORT="${port}" \
  mix run --no-halt) >"${temp_dir}/server.log" 2>&1 &
server_pid=$!

base_url="http://127.0.0.1:${port}"
ready=0
for _attempt in $(seq 1 40); do
  if curl --fail --silent "${base_url}/health" >"${temp_dir}/health.txt"; then
    ready=1
    break
  fi
  if ! kill -0 "${server_pid}" 2>/dev/null; then
    break
  fi
  sleep 0.25
done

if [[ "${ready}" != 1 ]]; then
  cat "${temp_dir}/server.log" >&2
  echo "Elixir server did not become healthy on port ${port}." >&2
  exit 1
fi

if [[ "$(cat "${temp_dir}/health.txt")" != "ok" ]]; then
  echo "Unexpected /health response." >&2
  exit 1
fi

if grep -Eiq 'database( table)? is locked' "${database_log}" "${temp_dir}/server.log"; then
  cat "${database_log}" "${temp_dir}/server.log" >&2
  echo "SQLite startup logged a database lock." >&2
  exit 1
fi

curl --fail --silent --show-error "${base_url}/api/status" >"${temp_dir}/status.json"
python3 - "${temp_dir}/status.json" <<'PY'
import json
import pathlib
import sys

status = json.loads(pathlib.Path(sys.argv[1]).read_text())
expected = {
    "backend": "elixir_scaffold",
    "contract_version": 1,
    "identity": "not_implemented",
    "messaging": "not_implemented",
    "calls": "not_implemented",
    "peer_connections": 0,
}
for key, value in expected.items():
    if status.get(key) != value:
        raise SystemExit(f"Unexpected /api/status field {key}: {status.get(key)!r}")
print("SQLite startup, migrations, /health, and /api/status passed without PostgreSQL.")
PY

python3 - "${base_url}" <<'PY'
import base64
import json
import sys
import urllib.error
import urllib.request

base_url = sys.argv[1]

def request(method, path, payload=None, session_id=None):
    body = None if payload is None else json.dumps(payload).encode()
    headers = {} if body is None else {"content-type": "application/json"}
    if session_id is not None:
        headers["authorization"] = "Bearer " + session_id
    request = urllib.request.Request(base_url + path, data=body, headers=headers, method=method)
    try:
        response = urllib.request.urlopen(request, timeout=3)
    except urllib.error.HTTPError as error:
        return error.code, error.read()
    return response.status, response.read()

status, body = request("POST", "/api/pairing-sessions")
assert status == 201, (status, body)
session = json.loads(body)
session_id = session["session_id"]
assert len(session_id) == 64
assert session["expires_in_seconds"] == 120
assert session["attempts_per_session"] == 1

spake_messages = {
    "inviter": base64.b64encode(bytes([0x41]) * 33).decode(),
    "invitee": base64.b64encode(bytes([0x53]) * 33).decode(),
}
for role in ("inviter", "invitee"):
    status, body = request(
        "POST", f"/api/pairing-sessions/{role}/spake2",
        {"message": spake_messages[role]},
        session_id,
    )
    assert status == 204, (status, body)

for role, expected in (("inviter", spake_messages["invitee"]), ("invitee", spake_messages["inviter"])):
    status, body = request("GET", f"/api/pairing-sessions/{role}/spake2", session_id=session_id)
    assert status == 200 and json.loads(body)["message"] == expected, (status, body)

for role in ("inviter", "invitee"):
    confirmation = base64.b64encode(bytes([0x10 if role == "inviter" else 0x20]) * 32).decode()
    status, body = request(
        "POST", f"/api/pairing-sessions/{role}/confirm",
        {"message": confirmation},
        session_id,
    )
    assert status == 204, (status, body)

for role in ("inviter", "invitee"):
    identity_message = base64.b64encode(bytes([0x30 if role == "inviter" else 0x40]) * 128).decode()
    status, body = request(
        "POST", f"/api/pairing-sessions/{role}/identity",
        {"message": identity_message},
        session_id,
    )
    assert status == 204, (status, body)

status, body = request("GET", "/api/pairing-sessions/inviter/identity", session_id=session_id)
assert status == 200 and len(json.loads(body)["message"]) == 172, (status, body)

status, body = request("DELETE", "/api/pairing-sessions", session_id=session_id)
assert status == 204, (status, body)
status, _body = request("GET", "/api/pairing-sessions/inviter/spake2", session_id=session_id)
assert status == 404, status
print("SPAKE2 rendezvous HTTP create, exchange, confirmation, and cancellation passed.")
PY
