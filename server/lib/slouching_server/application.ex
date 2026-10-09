defmodule SlouchingServer.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    repo_children =
      if Application.get_env(:slouching_server, :start_repo, false),
        do: [SlouchingServer.Repo],
        else: []

    children =
      if Application.get_env(:slouching_server, :start_server, true) do
        [{Bandit, plug: SlouchingServer.Router, ip: {127, 0, 0, 1}, port: 3707}]
      else
        []
      end

    Supervisor.start_link(repo_children ++ children,
      strategy: :one_for_one,
      name: SlouchingServer.Supervisor
    )
  end
end
