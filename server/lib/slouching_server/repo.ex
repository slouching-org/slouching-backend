defmodule SlouchingServer.Repo do
  use Ecto.Repo,
    otp_app: :slouching_server,
    adapter: Ecto.Adapters.Postgres
end
