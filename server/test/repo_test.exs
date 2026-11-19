defmodule SlouchingServer.RepoTest do
  use ExUnit.Case, async: false

  alias SlouchingServer.Directory.Device

  setup do
    repo().delete_all(Device)
    :ok
  end

  test "selected repository starts with the directory schema and persists a device row" do
    public_key = :crypto.strong_rand_bytes(32)

    assert {:ok, %Device{signing_public_key: ^public_key}} =
             %Device{}
             |> Device.enrollment_changeset(%{signing_public_key: public_key})
             |> repo().insert()

    assert [%Device{signing_public_key: ^public_key}] = repo().all(Device)
  end

  defp repo, do: Application.fetch_env!(:slouching_server, :repo_module)
end
