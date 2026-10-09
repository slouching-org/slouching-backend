defmodule SlouchingServer.Repo.Migrations.CreateDevices do
  use Ecto.Migration

  def change do
    create table(:devices, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :signing_public_key, :binary, null: false
      add :revoked_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:devices, [:signing_public_key])
  end
end
