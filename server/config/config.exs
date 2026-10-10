import Config

config :slouching_server, start_server: config_env() != :test

config :slouching_server,
  ecto_repos: [SlouchingServer.Repo],
  repo_module: SlouchingServer.Repo,
  start_repo: true,
  server_ip: {127, 0, 0, 1},
  server_port: 3707,
  server_tls_options: []

config :slouching_server, SlouchingServer.Repo,
  database: Path.expand("../priv/repo/slouching_dev.sqlite3", __DIR__),
  # The local helper has light load; serial startup avoids parallel WAL setup locks.
  pool_size: 1

import_config "#{config_env()}.exs"
