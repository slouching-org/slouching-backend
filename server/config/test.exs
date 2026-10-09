import Config

config :slouching_server,
  start_server: false,
  start_repo: true

config :slouching_server, SlouchingServer.Repo,
  database: ":memory:",
  pool_size: 1
