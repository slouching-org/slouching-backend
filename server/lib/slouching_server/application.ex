defmodule SlouchingServer.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    repo_children =
      if Application.get_env(:slouching_server, :start_repo, false),
        do: [Application.fetch_env!(:slouching_server, :repo_module)],
        else: []

    pairing_children = [
      {SlouchingServer.PairingSessions, name: SlouchingServer.PairingSessions},
      {SlouchingServer.Calls.SfuCallRooms, name: SlouchingServer.Calls.SfuCallRooms}
    ]

    delivery_children =
      if Application.get_env(:slouching_server, :start_repo, false),
        do: [SlouchingServer.Delivery.Expiry],
        else: []

    children =
      if Application.get_env(:slouching_server, :start_server, true) do
        [
          {Bandit,
           Keyword.merge(
             [
               plug: SlouchingServer.Router,
               ip: Application.fetch_env!(:slouching_server, :server_ip),
               port: Application.fetch_env!(:slouching_server, :server_port)
             ],
             Application.get_env(:slouching_server, :server_tls_options, [])
           )}
        ]
      else
        []
      end

    Supervisor.start_link(repo_children ++ pairing_children ++ delivery_children ++ children,
      strategy: :one_for_one,
      name: SlouchingServer.Supervisor
    )
  end
end
