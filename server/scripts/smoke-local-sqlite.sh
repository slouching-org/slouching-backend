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
