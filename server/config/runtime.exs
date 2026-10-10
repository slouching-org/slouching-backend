import Config

server_ip =
  System.get_env("SLOUCHING_BIND_IP", "127.0.0.1")
  |> String.to_charlist()
  |> :inet.parse_address()
  |> case do
    {:ok, ip} -> ip
    {:error, reason} -> raise "invalid SLOUCHING_BIND_IP: #{inspect(reason)}"
  end

config :slouching_server,
  server_ip: server_ip,
  server_port: String.to_integer(System.get_env("SLOUCHING_PORT", "3707"))

tls_certfile = System.get_env("SLOUCHING_TLS_CERTFILE")
tls_keyfile = System.get_env("SLOUCHING_TLS_KEYFILE")

tls_options =
  case {tls_certfile, tls_keyfile} do
    {nil, nil} ->
      []

    {certfile, keyfile}
    when is_binary(certfile) and certfile != "" and is_binary(keyfile) and keyfile != "" ->
      [scheme: :https, certfile: Path.expand(certfile), keyfile: Path.expand(keyfile)]

    _ ->
      raise "SLOUCHING_TLS_CERTFILE and SLOUCHING_TLS_KEYFILE must both name readable PEM files"
  end

loopback_ip =
  case server_ip do
    {127, _, _, _} -> true
    {0, 0, 0, 0, 0, 0, 0, 1} -> true
    _ -> false
  end

if not loopback_ip and tls_options == [] do
  raise "non-loopback SLOUCHING_BIND_IP requires TLS; configure SLOUCHING_TLS_CERTFILE and SLOUCHING_TLS_KEYFILE"
end

config :slouching_server, server_tls_options: tls_options

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
