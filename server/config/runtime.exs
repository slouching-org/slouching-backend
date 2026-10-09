import Config

config :slouching_server,
  server_port: String.to_integer(System.get_env("SLOUCHING_PORT", "3707"))

if sqlite_path = System.get_env("SLOUCHING_SQLITE_PATH") do
  config :slouching_server, SlouchingServer.Repo, database: Path.expand(sqlite_path)
end

if database_url = System.get_env("SLOUCHING_DATABASE_URL") do
  config :slouching_server,
    ecto_repos: [SlouchingServer.PostgresRepo],
    repo_module: SlouchingServer.PostgresRepo,
    start_repo: true

  config :slouching_server, SlouchingServer.PostgresRepo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("SLOUCHING_DATABASE_POOL_SIZE", "5")),
    show_sensitive_data_on_connection_error: false
end
