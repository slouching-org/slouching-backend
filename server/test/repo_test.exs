defmodule SlouchingServer.RepoTest do
  use ExUnit.Case, async: false

  alias SlouchingServer.Directory.Device
  alias SlouchingServer.Repo

  test "SQLite starts with the directory schema and persists a device row" do
    assert %{rows: [["devices"]]} =
             Ecto.Adapters.SQL.query!(
               Repo,
               "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'devices'"
             )

    public_key = :crypto.strong_rand_bytes(32)

    assert {:ok, %Device{signing_public_key: ^public_key}} =
             %Device{}
             |> Device.enrollment_changeset(%{signing_public_key: public_key})
             |> Repo.insert()

    assert [%Device{signing_public_key: ^public_key}] = Repo.all(Device)
  end
end
