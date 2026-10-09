import Config

config :slouching_server, start_server: config_env() != :test

config :slouching_server,
  ecto_repos: [SlouchingServer.Repo],
  repo_module: SlouchingServer.Repo,
  start_repo: true

config :slouching_server, SlouchingServer.Repo,
  database: Path.expand("../priv/repo/slouching_dev.sqlite3", __DIR__),
  pool_size: 5

import_config "#{config_env()}.exs"
