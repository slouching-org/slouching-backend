defmodule SlouchingServer.Release do
  @moduledoc """
  Release tasks for deploying the optional Slouching helper.
  """

  @app :slouching_server

  def migrate do
    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      pool_size = Keyword.get(repo.config(), :pool_size, 2)

      {:ok, _, _} =
        Ecto.Migrator.with_repo(
          repo,
          fn repo ->
            Ecto.Migrator.run(repo, :up, all: true)
          end,
          pool_size: pool_size
        )
    end

    :ok
  end
end
