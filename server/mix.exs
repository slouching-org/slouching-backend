defmodule SlouchingServer.MixProject do
  use Mix.Project

  def project do
    [
      app: :slouching_server,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      releases: [
        slouching_server: [applications: [runtime_tools: :permanent]]
      ],
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [extra_applications: [:logger], mod: {SlouchingServer.Application, []}]
  end

  defp deps do
    [
      {:bandit, "~> 1.12"},
      {:plug, "~> 1.20"},
      {:jason, "~> 1.4"},
      {:ecto_sql, "~> 3.13"},
      {:ecto_sqlite3, "~> 0.25"},
      {:postgrex, "~> 0.21"},
      {:protobuf, "~> 0.17"},
      {:websock_adapter, "~> 0.6"}
    ]
  end

  defp aliases do
    [
      setup: [
        "deps.get",
        "ecto.create",
        "ecto.migrate --pool-size 1"
      ]
    ]
  end
end
