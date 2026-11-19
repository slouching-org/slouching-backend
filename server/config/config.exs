import Config

config :slouching_server, start_server: config_env() != :test

# Ecto Mix tasks select repositories before loading runtime.exs.
# Tests only opt in to PostgreSQL through a separate, disposable database URL.
database_url =
  if config_env() == :test,
    do: System.get_env("SLOUCHING_TEST_DATABASE_URL"),
    else: System.get_env("SLOUCHING_DATABASE_URL")

repo = if database_url, do: SlouchingServer.PostgresRepo, else: SlouchingServer.Repo

config :slouching_server,
  ecto_repos: [repo],
  repo_module: repo,
  start_repo: true,
  server_ip: {127, 0, 0, 1},
  server_port: 3707,
  server_tls_options: []

config :slouching_server, SlouchingServer.Repo,
  database: Path.expand("../priv/repo/slouching_dev.sqlite3", __DIR__),
  # The local helper has light load; serial startup avoids parallel WAL setup locks.
  pool_size: 1

config :slouching_server, SlouchingServer.PostgresRepo, priv: "priv/repo"

import_config "#{config_env()}.exs"
