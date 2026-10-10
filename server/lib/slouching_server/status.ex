defmodule SlouchingServer.Status do
  @moduledoc """
  Versioned diagnostic snapshot. Capability values reflect implemented behavior only.
  """

  @contract_version 1

  @spec snapshot() :: map()
  def snapshot do
    %{
      contract_version: @contract_version,
      backend: "elixir_scaffold",
      identity: "not_implemented",
      messaging: "not_implemented",
      calls: "available",
      peer_connections: 0
    }
  end
end
