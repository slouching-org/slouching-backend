defmodule SlouchingServer.Repo do
  use Ecto.Repo,
    otp_app: :slouching_server,
    adapter: Ecto.Adapters.SQLite3
end

defmodule SlouchingServer.PostgresRepo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :slouching_server,
    adapter: Ecto.Adapters.Postgres
end
