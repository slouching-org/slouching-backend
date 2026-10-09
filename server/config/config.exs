import Config

config :slouching_server, start_server: config_env() != :test

config :slouching_server,
  ecto_repos: [SlouchingServer.Repo],
  start_repo: false
