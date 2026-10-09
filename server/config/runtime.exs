import Config

if database_url = System.get_env("SLOUCHING_DATABASE_URL") do
  config :slouching_server, SlouchingServer.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("SLOUCHING_DATABASE_POOL_SIZE", "5"))

  config :slouching_server, start_repo: true
end
