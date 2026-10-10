#!/usr/bin/env bash
set -euo pipefail

server_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
temp_dir="$(mktemp -d)"
release_bin="${server_root}/_build/prod/rel/slouching_server/bin/slouching_server"
release_pid=""

cleanup() {
  if [[ -n "${release_pid}" ]] && kill -0 "${release_pid}" 2>/dev/null; then
    "${release_bin}" stop >/dev/null 2>&1 || true
    wait "${release_pid}" 2>/dev/null || true
  fi
  rm -rf -- "${temp_dir}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
database_path="${temp_dir}/release.sqlite3"

cd "${server_root}"
if ! MIX_ENV=prod mix release --overwrite >"${temp_dir}/build.log" 2>&1; then
  cat "${temp_dir}/build.log" >&2
  exit 1
fi

export SLOUCHING_SQLITE_PATH="${database_path}"
export SLOUCHING_PORT="${port}"
export RELEASE_NODE="slouching_release_smoke_${BASHPID}@localhost"
export RELEASE_COOKIE="slouching_release_smoke_cookie"
export RELEASE_TMP="${temp_dir}/release-tmp"

if ! "${release_bin}" eval 'SlouchingServer.Release.migrate()' >"${temp_dir}/migration.log" 2>&1; then
  cat "${temp_dir}/migration.log" >&2
  exit 1
fi
if grep -Eiq 'database( table)? is locked' "${temp_dir}/migration.log"; then
  cat "${temp_dir}/migration.log" >&2
  echo "Release migration logged a SQLite lock." >&2
  exit 1
fi

python3 - "${database_path}" <<'PY'
import sqlite3
import sys

with sqlite3.connect(sys.argv[1]) as connection:
    tables = {row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
required = {"devices", "delivery_copies", "delivery_mailbox_usage", "delivery_request_nonces"}
if not required <= tables:
    raise SystemExit(f"Release migrations are missing tables: {sorted(required - tables)}")
PY

"${release_bin}" start >"${temp_dir}/release.log" 2>&1 &
release_pid=$!

ready=0
for _attempt in $(seq 1 40); do
  if curl --fail --silent "http://127.0.0.1:${port}/health" >"${temp_dir}/health.txt"; then
    ready=1
    break
  fi
  if ! kill -0 "${release_pid}" 2>/dev/null; then
    break
  fi
  sleep 0.25
done

if [[ "${ready}" != 1 ]] || [[ "$(cat "${temp_dir}/health.txt")" != "ok" ]]; then
  cat "${temp_dir}/release.log" >&2
  echo "Packaged Elixir release did not become healthy on port ${port}." >&2
  exit 1
fi

"${release_bin}" rpc 'SlouchingServer.Release.migrate()'
"${release_bin}" stop
wait "${release_pid}" || true
release_pid=""

echo "Packaged Elixir release migrated SQLite and served /health successfully."
