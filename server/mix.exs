defmodule SlouchingServer.MixProject do
  use Mix.Project

  def project do
    [
      app: :slouching_server,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
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
      {:postgrex, "~> 0.21"},
      {:protobuf, "~> 0.17"},
      {:websock_adapter, "~> 0.6"}
    ]
  end
end
