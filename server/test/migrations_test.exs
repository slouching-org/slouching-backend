defmodule SlouchingServer.MigrationsTest do
  use ExUnit.Case, async: false

  test "both adapters discover the same migration versions" do
    paths =
      for repo <- [SlouchingServer.Repo, SlouchingServer.PostgresRepo] do
        path = Ecto.Migrator.migrations_path(repo)
        assert Path.wildcard(Path.join(path, "*.exs")) |> length() == 2
        path
      end

    assert Enum.uniq(paths) |> length() == 1
  end
end
